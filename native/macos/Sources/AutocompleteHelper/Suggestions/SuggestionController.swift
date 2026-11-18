import AppKit
import Foundation

@MainActor
protocol GhostPresenting: AnyObject {
    var visibleIdentity: SuggestionRequestMessage.Identity? { get }
    var visibleText: String? { get }
    var visibleGlyphRegions: [CGRect] { get }
    var lastRejectionReason: GhostTextPresenterRejectionReason? { get }
    var lastParagraphLayoutFailureReason: ParagraphMirrorLayoutFailureReason? { get }
    var lastHorizontalDrawOffset: CGFloat? { get }

    @discardableResult
    func present(
        identity: SuggestionRequestMessage.Identity,
        text: String,
        snapshot: ActiveFieldSnapshot,
        protectedText: [String],
        allowsFitting: Bool
    ) -> Bool
    func advance(
        identity: SuggestionRequestMessage.Identity,
        typed: String,
        remaining: String
    ) -> ActiveFieldSnapshot?
    @discardableResult
    func dismiss(identity: SuggestionRequestMessage.Identity?) -> Bool
    @discardableResult
    func dismissForGeometryChange() -> Bool
    func refreshAppearance()
    func dismissForAcceptance(identity: SuggestionRequestMessage.Identity)
}

protocol SuggestionInserting: AnyObject, Sendable {
    func prepare(for expectedSnapshot: ActiveFieldSnapshot) -> NotesInsertionPreparation
    func insert(_ text: String, prepared: PreparedNotesInsertion, isCurrent: () -> Bool) -> NotesInsertionResult
}

protocol HelperMessageWriting: AnyObject, Sendable {
    func writeSuggestionRequest(_ message: SuggestionRequestMessage) throws
    func writeCancelRequest(_ message: CancelRequestMessage) throws
    func writeInteraction(
        identity: SuggestionRequestMessage.Identity,
        outcome: InteractionOutcome,
        acceptedCharacters: Int
    ) throws
    func writeDiagnostic(_ code: String)
}

/// Owns the live suggestion loop: stable-snapshot requests, response
/// validation, anchored presentation, type-through, scroll reacquisition,
/// and verified acceptance. It is the single owner of Tab and click
/// consumption. Accessibility reads and insertion never run on the main
/// thread; presentation and event decisions never leave it.
@MainActor
final class SuggestionController {
    typealias MainDispatcher = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
    typealias BackgroundDispatcher = @Sendable (@escaping @Sendable () -> Void) -> Void
    typealias ContextArtifacts = (
        _ snapshot: ActiveFieldSnapshot,
        _ timestampMs: Int64
    ) -> [SuggestionRequestMessage.Payload.Artifact]

    static let asyncMainDispatcher: MainDispatcher = { work in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { work() }
        }
    }

    private let foregroundApplication: () -> String?
    private let presenter: any GhostPresenting
    private let inserter: any SuggestionInserting
    private let writer: any HelperMessageWriting
    private let diagnostics: FixtureDiagnostics
    private let timeline: (any HelperTimelineTracing)?
    private let contextArtifacts: ContextArtifacts
    private let onAccepted: (SuggestionRequestMessage.Identity, String, ActiveFieldSnapshot) -> Void
    private let generation: ActiveFieldGeneration
    // Geometry callbacks revoke readiness before waiting for main-actor work.
    private let anchorRevision: ActiveFieldGeneration
    private var session = SuggestionSession()
    // Each version retains its own validated insertion authority. These are
    // ephemeral alternatives, never observed writing or accepted context.
    private var alternatives: [SuggestionSession] = []
    private var alternativeIndex = 0
    private var pendingAlternative: (session: SuggestionSession, generation: UInt64)?
    private var stabilized = StabilizedSuggestionState()
    private let dispatchToMain: MainDispatcher
    private let backgroundDispatcher: BackgroundDispatcher?
    private var configuration = CaptureConfiguration.disabled
    private var explicitRequest: (appId: String, deadline: TimeInterval)?
    private var sourceRecovery: (snapshot: ActiveFieldSnapshot, explicit: Bool)?
    private var activeRequestExplicit = false
    private var activeRequestArtifacts: [SuggestionRequestMessage.Payload.Artifact] = []
    private var cooldown = SuggestionCooldown()
    private var cooldownWakeup: UUID?
    private var timestampMilliseconds: Int64 {
        Int64((now() + Date.timeIntervalBetween1970AndReferenceDate) * 1_000)
    }
    private var requestContextIsFresh: Bool {
        let timestamp = timestampMilliseconds
        return activeRequestArtifacts.allSatisfy { ContextArtifactFreshness.isFresh($0, at: timestamp) }
    }
    private let now: () -> TimeInterval
    private let scheduleCooldown: ActiveFieldMonitor.PostInputScheduler
    private var awaitingUserInput = false
    private var activation = SuggestionActivation()
    private var typedAppendPending = false
    private var reportedShownIdentity: SuggestionRequestMessage.Identity?

    /// A capability check for the exact authoritative presentation. The AX
    /// preparation itself is never reused for a write: acceptance prepares again.
    private struct AcceptancePreparation {
        let id: UUID
        let generation: UInt64
        let anchorRevision: UInt64
        let presentation: SuggestionPresentation
        var isReady = false
    }
    private var acceptancePreparation: AcceptancePreparation?
    private(set) var monitor: ActiveFieldMonitor!

    var sessionState: SuggestionSessionState { session.state }
    var currentIdentity: SuggestionRequestMessage.Identity? { session.currentIdentity }
    var visibleGlyphRegions: [CGRect] { presenter.visibleGlyphRegions }

    init(
        capture: @escaping () -> ActiveFieldCaptureResult,
        presenter: any GhostPresenting,
        inserter: any SuggestionInserting,
        writer: any HelperMessageWriting,
        diagnostics: FixtureDiagnostics,
        foregroundApplication: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        contextArtifacts: @escaping ContextArtifacts = { _, _ in [] },
        onAccepted: @escaping (SuggestionRequestMessage.Identity, String, ActiveFieldSnapshot) -> Void = { _, _, _ in },
        quietInterval: TimeInterval = 0.3,
        scheduleAfterHostPublication: ActiveFieldMonitor.PostInputScheduler? = nil,
        scheduleCooldown: ActiveFieldMonitor.PostInputScheduler? = nil,
        scheduleQuietDeadline: ActiveFieldMonitor.PostInputScheduler? = nil,
        now: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
        timeline: (any HelperTimelineTracing)? = nil,
        monotonicMilliseconds: @escaping () -> Double = {
            ProcessInfo.processInfo.systemUptime * 1_000
        },
        dispatchToMain: MainDispatcher? = nil,
        dispatchToBackground: BackgroundDispatcher? = nil
    ) {
        self.now = now
        self.scheduleCooldown = scheduleCooldown ?? { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        self.foregroundApplication = foregroundApplication
        self.presenter = presenter
        self.inserter = inserter
        self.writer = writer
        self.diagnostics = diagnostics
        self.timeline = timeline
        self.contextArtifacts = contextArtifacts
        self.onAccepted = onAccepted
        self.dispatchToMain = dispatchToMain ?? Self.asyncMainDispatcher
        self.backgroundDispatcher = dispatchToBackground
        let generation = ActiveFieldGeneration()
        self.generation = generation
        let anchorRevision = ActiveFieldGeneration()
        self.anchorRevision = anchorRevision
        let toMain = self.dispatchToMain
        monitor = ActiveFieldMonitor(
            capture: capture,
            quietInterval: quietInterval,
            onStableSnapshot: { [weak self] snapshot, callbackGeneration in
                toMain { [weak self] in
                    guard let self, generation.isCurrent(callbackGeneration) else { return }
                    self.beginSuggestion(snapshot, generation: callbackGeneration)
                }
            },
            onGeometryChanged: { [weak self] snapshot, callbackGeneration in
                guard generation.isCurrent(callbackGeneration) else { return }
                anchorRevision.advance()
                toMain { [weak self] in
                    guard let self, generation.isCurrent(callbackGeneration) else { return }
                    self.acceptGeometry(snapshot, generation: callbackGeneration)
                }
            },
            onGeometryHidden: { [weak self] callbackGeneration in
                guard generation.isCurrent(callbackGeneration) else { return }
                anchorRevision.advance()
                toMain { [weak self] in
                    guard let self, generation.isCurrent(callbackGeneration) else { return }
                    self.hideForUnstableGeometry()
                }
            },
            onInvalidated: { [weak self] snapshot, callbackGeneration in
                guard generation.isCurrent(callbackGeneration) else { return }
                anchorRevision.advance()
                toMain { [weak self] in
                    guard let self, generation.isCurrent(callbackGeneration) else { return }
                    self.invalidateSuggestion(with: snapshot)
                }
            },
            onObservedDraftEdit: { [weak self] snapshot, callbackGeneration in
                toMain { [weak self] in
                    guard let self, generation.isCurrent(callbackGeneration),
                          self.configuration.allows(snapshot.applicationBundleIdentifier) else { return }
                    // AX value edits from dictation/paste/accessibility also
                    // resume automation; they do not establish memory authorship.
                    self.awaitingUserInput = false
                    self.activation.observedEdit(snapshot)
                    self.observeCooldownTarget(snapshot)
                    if let delay = self.cooldown.observeDraftEdit(target: .init(snapshot), at: self.now()) {
                        self.scheduleCooldownReevaluation(after: delay)
                    }
                }
            },
            generation: generation,
            scheduleAfterHostPublication: scheduleAfterHostPublication,
            scheduleQuietDeadline: scheduleQuietDeadline,
            timeline: timeline,
            monotonicMilliseconds: monotonicMilliseconds,
            now: now
        )
    }

    // MARK: - Configuration and commands

    func updateConfiguration(_ configuration: CaptureConfiguration, waitForInput: Bool = false) {
        guard self.configuration != configuration else { return }
        acceptancePreparation = nil
        var previousWithNewColor = self.configuration
        previousWithNewColor.ghostAlpha = configuration.ghostAlpha
        GhostTextColor.opacity = CGFloat(configuration.ghostAlpha)
        if previousWithNewColor == configuration {
            self.configuration = configuration
            presenter.refreshAppearance()
            if let identity = session.currentIdentity,
               let stored = session.presentationFromLastValidatedSnapshot(for: identity),
               let presentation = stabilized.anchored(stored, currentGeneration: generation.current) {
                prepareAcceptance(for: presentation)
            }
            return
        }
        self.configuration = configuration
        activeRequestArtifacts = []
        clearAlternatives()
        explicitRequest = nil
        sourceRecovery = nil
        awaitingUserInput = waitForInput
        do {
            stabilized.clear()
            if let cancellation = session.dismiss() {
                writeCancellation(cancellation)
            }
            _ = presenter.dismiss(identity: nil)
        }
        monitor.updateConfiguration(configuration)
    }

    func handle(_ command: HelperCommand) {
        switch command {
        case .contextInvalidate(let ids):
            let activeIds = [session.currentIdentity?.requestId, pendingAlternative?.session.currentIdentity?.requestId].compactMap { $0 }
                + alternatives.compactMap { $0.currentIdentity?.requestId }
            if !Set(ids).isDisjoint(with: activeIds) { shutdown(reason: .contentChanged) }
        case .contextRequestScreenPermission, .configure, .transformConfigure, .transformResult:
            break
        case .requestSuggestion:
            writer.writeDiagnostic("manual_request_received")
            clearAlternatives()
            acceptancePreparation = nil
            // Resolve here, in the capture process. The UI's mirrored activation
            // state can still describe the previous app when a hotkey arrives.
            guard let appId = foregroundApplication(), configuration.allows(appId) else {
                writer.writeDiagnostic("manual_request_target_unavailable")
                return
            }
            monitor.updateConfiguration(.disabled)
            monitor.updateConfiguration(configuration)
            explicitRequest = (appId, ProcessInfo.processInfo.systemUptime + 5)
            monitor.refreshAfterInput()
        case let .suggestionFinal(final):
            if receiveAlternative(command, identity: final.identity) { return }
            if session.currentIdentity == final.identity, !requestContextIsFresh {
                shutdown(reason: .contentChanged)
                return
            }
            diagnostics.suggestionFinalCommandReceived()
            diagnostics.suggestionFinalResult(final.result)
            let requestSnapshot = session.snapshotForRequest(final.identity)
            let receivedDisposition = session.handle(command)
            let sourceChanged = receivedDisposition == .accepted
                && requestSnapshot.map { monitor.sourceEvidenceChanged(matching: $0) } == true
            let disposition: SuggestionResponseDisposition = sourceChanged ? .rejectedCurrent : receivedDisposition
            diagnostics.sessionOutcome(disposition)
            timeline?.responseReceived(
                identity: final.identity,
                disposition: disposition
            )
            if sourceChanged, let requestSnapshot {
                if case .text = final.result {
                    timeline?.presentRejected(identity: final.identity, rejection: .sourceChanged, anchorWaitMilliseconds: nil)
                }
                recoverSource(from: requestSnapshot, identity: final.identity)
                return
            }
            switch disposition {
            case .accepted:
                if case .text = final.result {
                    updatePresentation(for: final.identity)
                } else {
                    acceptancePreparation = nil
                    stabilized.clear()
                    _ = presenter.dismiss(identity: final.identity)
                }
            case .rejectedCurrent:
                acceptancePreparation = nil
                stabilized.clear()
                _ = presenter.dismiss(identity: final.identity)
            case .ignoredStale:
                break
            }
        case let .requestFailed(failure):
            if receiveAlternative(command, identity: failure.identity) { return }
            switch session.handle(command) {
            case .accepted, .rejectedCurrent:
                acceptancePreparation = nil
                stabilized.clear()
                _ = presenter.dismiss(identity: failure.identity)
            case .ignoredStale:
                break
            }
        }
    }

    func shutdown(reason: CancelRequestReason = .shutdown) {
        activeRequestArtifacts = []
        clearAlternatives(reason: reason)
        if let recovery = sourceRecovery { monitor.markHandled(recovery.snapshot) }
        sourceRecovery = nil
        cooldownWakeup = nil
        acceptancePreparation = nil
        if let cancellation = session.dismiss(reason: reason) {
            writeCancellation(cancellation)
        }
        _ = presenter.dismiss(identity: nil)
    }

    // MARK: - Capture callbacks (main actor)

    private func beginSuggestion(_ snapshot: ActiveFieldSnapshot, generation: UInt64) {
        guard configuration.allows(snapshot.applicationBundleIdentifier) else { return }
        observeCooldownTarget(snapshot)
        let recovery = sourceRecovery
        sourceRecovery = nil
        let recoveringExplicit = recovery.map { $0.explicit && $0.snapshot.contentSignature == snapshot.contentSignature } == true
        let explicit = recoveringExplicit || explicitRequest.map { $0.appId == snapshot.applicationBundleIdentifier && $0.deadline >= ProcessInfo.processInfo.systemUptime } == true
        if explicitRequest != nil && !explicit {
            explicitRequest = nil
            monitor.markHandled(snapshot)
            return
        }
        explicitRequest = nil
        guard explicit || (configuration.automaticSuggestions && !awaitingUserInput
            && activation.allows(snapshot, now: now())) else {
            monitor.markHandled(snapshot)
            return
        }
        guard explicit || !cooldown.isBlocked(at: now()) else {
            monitor.markHandled(snapshot)
            if cooldownWakeup == nil, let delay = cooldown.remainingDelay(at: now()) {
                scheduleCooldownReevaluation(after: delay)
            }
            return
        }
        if !explicit, session.hasReadySuggestion,
           let currentIdentity = session.currentIdentity,
           currentIdentity.focusSequence == snapshot.focusGeneration,
           session.presentationFromLastValidatedSnapshot(for: currentIdentity)?
                .snapshot.contentSignature == snapshot.contentSignature
        {
            // A geometry-only refresh can keep the ready ghost when the
            // reply target and draft identity are unchanged. An explicit
            // invocation requests a replacement, including when this result
            // could not be displayed. Do not depend on the monitor's queued
            // invalidation: its generation can be superseded by the refresh.
            monitor.markHandled(snapshot)
            return
        }
        let timestampMs = timestampMilliseconds
        let artifacts = contextArtifacts(snapshot, timestampMs).filter { ContextArtifactFreshness.isFresh($0, at: timestampMs) }
        guard explicit || SuggestionRequestEligibility.shouldRequest(
            textBefore: snapshot.textBefore,
            selectedText: snapshot.selectedText,
            textAfter: snapshot.textAfter,
            fieldContext: snapshot.fieldContext
        ) else {
            // Current sources may establish a reply task. Relevance and intent
            // belong to the model; a field without any writing evidence still
            // does not trigger generation merely from its placeholder.
            monitor.markHandled(snapshot)
            stabilized.clear()
            return
        }
        clearAlternatives()
        acceptancePreparation = nil
        diagnostics.request(snapshot)
        stabilized.begin(at: snapshot, generation: generation)
        let message = SuggestionRequestMessage(
            snapshot: snapshot,
            timestampMs: timestampMs,
            artifacts: artifacts,
            explicit: explicit
        )
        do {
            if let cancellation = session.begin(message, snapshot: snapshot) {
                try writer.writeCancelRequest(cancellation)
                timeline?.cancelWritten(
                    identity: cancellation.identity,
                    reason: cancellation.payload.reason,
                    typedAppend: false
                )
            }
            _ = presenter.dismiss(identity: nil)
            activeRequestExplicit = explicit
            activeRequestArtifacts = artifacts
            try writer.writeSuggestionRequest(message)
            // A request has now handled this draft, including a manual bypass.
            // Its old expiry must not retry a later silence or failure.
            cooldownWakeup = nil
            timeline?.requestWritten(
                identity: message.identity,
                surface: snapshot.surface,
                shape: snapshot.fieldContext.shape,
                textBeforeUTF16Count: snapshot.textBefore.utf16.count,
                textAfterUTF16Count: snapshot.textAfter.utf16.count,
                hasSelection: snapshot.selectionRange.length > 0,
                relatedFieldCount: snapshot.fieldContext.relatedFields.count,
                geometryQuality: snapshot.geometryQuality,
                anchorResolved: monitor.stabilizedSnapshot(matching: snapshot) != nil,
                explicit: explicit
            )
        } catch {
            _ = session.dismiss()
            stabilized.clear()
            writer.writeDiagnostic("suggestion_request_write_failed")
        }
    }

    private func invalidateSuggestion(with snapshot: ActiveFieldSnapshot?) {
        if let snapshot { _ = activation.allows(snapshot, now: now()) }
        clearAlternatives(reason: snapshot == nil ? .focusChanged : .contentChanged)
        if snapshot?.contentSignature != sourceRecovery?.snapshot.contentSignature { sourceRecovery = nil }
        acceptancePreparation = nil
        let typedAppend = typedAppendPending
        typedAppendPending = false
        if let snapshot {
            observeCooldownTarget(snapshot)
            switch session.reconcileTypeThrough(with: snapshot) {
            case .ignored:
                break
            case let .advanced(presentation, _, _):
                monitor.markHandled(snapshot)
                let keptVisible = stabilized.reconcileAuthoritativeAdvance()
                if !keptVisible {
                    _ = presenter.dismiss(identity: presentation.identity)
                }
                return
            case let .completed(identity, completedSnapshot, acceptedCharacters):
                activeRequestArtifacts = []
                monitor.markHandled(completedSnapshot)
                stabilized.clear()
                _ = presenter.dismiss(identity: identity)
                writeInteraction(
                    identity: identity,
                    outcome: .typedThrough,
                    acceptedCharacters: acceptedCharacters
                )
                return
            case let .cancelled(cancellation):
                activeRequestArtifacts = []
                stabilized.clear()
                _ = presenter.dismiss(identity: cancellation.identity)
                writeCancellation(cancellation, typedAppend: typedAppend)
                return
            }
        }
        activeRequestArtifacts = []
        guard let cancellation = session.invalidate(with: snapshot) else {
            stabilized.clear()
            _ = presenter.dismiss(identity: nil)
            return
        }
        _ = presenter.dismiss(identity: cancellation.identity)
        stabilized.clear()
        writeCancellation(cancellation, typedAppend: typedAppend)
    }

    private func recoverSource(from snapshot: ActiveFieldSnapshot, identity: SuggestionRequestMessage.Identity) {
        activeRequestArtifacts = []
        clearAlternatives(reason: .contentChanged)
        sourceRecovery = (snapshot, activeRequestExplicit)
        acceptancePreparation = nil
        stabilized.clear()
        _ = presenter.dismiss(identity: identity)
        if let cancellation = session.dismiss(reason: .contentChanged) {
            writeCancellation(cancellation)
        }
        monitor.refreshSource(after: snapshot)
    }

    private func updatePresentation(for identity: SuggestionRequestMessage.Identity, recordShown: Bool = true) {
        guard let stored = session.presentationFromLastValidatedSnapshot(for: identity) else {
            diagnostics.presentation(.sessionUnavailable)
            timeline?.presentRejected(
                identity: identity,
                rejection: .sessionUnavailable,
                anchorWaitMilliseconds: nil
            )
            if !stabilized.isReacquiringAfterPreview {
                _ = presenter.dismiss(identity: identity)
            }
            return
        }
        guard let liveSnapshot = monitor.stabilizedSnapshot(
            matching: stored.snapshot
        ) else {
            diagnostics.presentation(
                .anchorUnavailable(
                    reacquiringAfterPreview: stabilized.isReacquiringAfterPreview
                )
            )
            timeline?.presentRejected(
                identity: identity,
                rejection: monitor.sourceEvidenceChanged(matching: stored.snapshot)
                    ? .sourceChanged : stabilized.isReacquiringAfterPreview
                    ? .anchorReacquiring
                    : .anchorUnavailable,
                anchorWaitMilliseconds: nil
            )
            if monitor.sourceEvidenceChanged(matching: stored.snapshot) {
                recoverSource(from: stored.snapshot, identity: identity)
            } else {
                monitor.requestReanchor()
            }
            return
        }
        stabilized.acceptGeometry(
            liveSnapshot,
            generation: generation.current
        )
        guard let presentation = stabilized.anchored(
            stored,
            currentGeneration: generation.current
        ) else {
            diagnostics.presentation(
                .anchorUnavailable(
                    reacquiringAfterPreview: stabilized.isReacquiringAfterPreview
                )
            )
            timeline?.presentRejected(
                identity: identity,
                rejection: stabilized.isReacquiringAfterPreview
                    ? .anchorReacquiring
                    : .anchorValidation,
                anchorWaitMilliseconds: nil
            )
            if !stabilized.isReacquiringAfterPreview {
                _ = presenter.dismiss(identity: identity)
            }
            return
        }
        diagnostics.presentation(.available)
        present(presentation, recordShown: recordShown)
    }

    private func present(_ offered: SuggestionPresentation, recordShown: Bool = true) {
        var presentation = offered
        let wasReportedShown = reportedShownIdentity == presentation.identity
            || alternatives.contains { $0.currentIdentity == presentation.identity }
        diagnostics.presentInvoked()
        var didPresent = presenter.present(
            identity: presentation.identity,
            text: presentation.text,
            snapshot: presentation.snapshot,
            protectedText: session.protectedText,
            allowsFitting: !wasReportedShown
        )
        if didPresent, presenter.visibleText != presentation.text {
            if !wasReportedShown, let visible = presenter.visibleText,
               session.selectVisiblePrefix(visible, identity: presentation.identity) {
                presentation = .init(identity: presentation.identity, text: visible, snapshot: presentation.snapshot)
            } else {
                _ = presenter.dismiss(identity: presentation.identity)
                didPresent = false
            }
        }
        diagnostics.presenter(
            didPresent: didPresent,
            rejectionReason: presenter.lastRejectionReason,
            paragraphLayoutFailureReason: presenter.lastParagraphLayoutFailureReason
        )
        if didPresent, !wasReportedShown, recordShown {
            timeline?.presented(identity: presentation.identity)
        } else {
            if !didPresent {
                timeline?.presentRejected(
                    identity: presentation.identity,
                    rejection: Self.timelineRejection(
                        presenter.lastRejectionReason
                    ),
                    anchorWaitMilliseconds: nil
                )
            }
        }
        if didPresent, diagnostics.isEnabled {
            let style = presentation.snapshot.paragraphMetrics?.textStyle
                ?? presentation.snapshot.textStyle
            diagnostics.visualCalibration(
                fontResolution: GhostTextTypography.resolution(for: style),
                typographyIsEstimated:
                    presentation.snapshot.paragraphMetrics?.typographyIsEstimated ?? false,
                horizontalOffset: presenter.lastHorizontalDrawOffset
            )
        }
        if didPresent {
            prepareAcceptance(for: presentation)
        } else {
            acceptancePreparation = nil
        }
        if didPresent, recordShown { reportedShownIdentity = presentation.identity }
        if didPresent, !wasReportedShown, recordShown {
            writeInteraction(
                identity: presentation.identity,
                outcome: .shown,
                acceptedCharacters: 0
            )
        }
    }

    private func acceptGeometry(_ snapshot: ActiveFieldSnapshot, generation: UInt64) {
        if session.hasUnconfirmedPreview(against: snapshot) {
            acceptancePreparation = nil
            // The keystroke was previewed but never reached this field; the
            // predicted ghost was hidden and the suggestion no longer matches
            // what the user did.
            stabilized.clear()
            if let cancellation = session.dismiss(reason: .contentChanged) {
                _ = presenter.dismiss(identity: cancellation.identity)
                writeCancellation(cancellation, typedAppend: typedAppendPending)
                typedAppendPending = false
            }
            return
        }
        stabilized.acceptGeometry(snapshot, generation: generation)
        guard let identity = session.currentIdentity,
              let stored = session.presentationFromLastValidatedSnapshot(for: identity),
              let presentation = stabilized.anchored(
                  stored,
                  currentGeneration: self.generation.current
              )
        else {
            stabilized.clear()
            _ = presenter.dismissForGeometryChange()
            return
        }
        updatePresentation(for: presentation.identity)
    }

    private func hideForUnstableGeometry() {
        acceptancePreparation = nil
        guard stabilized.shouldHideForUnstableGeometry() else { return }
        _ = presenter.dismissForGeometryChange()
    }

    // MARK: - Keyboard and pointer (main actor, event-tap hot path)

    func keyboardStatus() -> KeyboardSessionStatus {
        guard let visibleIdentity = presenter.visibleIdentity else {
            return session.state == .idle ? .inactive : .activeWithoutGhost
        }
        guard let presentation = session.presentationFromLastValidatedSnapshot(
            for: visibleIdentity
        ) else {
            _ = presenter.dismiss(identity: visibleIdentity)
            return session.state == .idle ? .inactive : .activeWithoutGhost
        }
        guard presenter.visibleText == presentation.text else {
            _ = presenter.dismiss(identity: visibleIdentity)
            return .activeWithoutGhost
        }
        guard !stabilized.isReacquiringAfterPreview,
              monitor.stabilizedSnapshot(matching: presentation.snapshot) != nil
        else { return .ghostVisible }
        return isAcceptanceReady(for: presentation) ? .ready : .ghostVisible
    }

    func noteUserEdit() {
        if let app = foregroundApplication() { activation.input(app: app, now: now()) }
        awaitingUserInput = false
        cooldown.noteUserEdit(at: now())
    }

    func notePointerInput(at point: CGPoint) {
        if let app = foregroundApplication() {
            activation.input(app: app, point: point, now: now())
            monitor.reevaluateHandledDraft()
        }
        awaitingUserInput = false
    }

    private func observeCooldownTarget(_ snapshot: ActiveFieldSnapshot) {
        if cooldown.observeTarget(.init(snapshot)) { cooldownWakeup = nil }
    }

    private func scheduleCooldownReevaluation(after delay: TimeInterval) {
        let wakeup = UUID()
        cooldownWakeup = wakeup
        let toMain = dispatchToMain
        scheduleCooldown(delay) { [weak self] in
            toMain { [weak self] in
                guard let self, self.cooldownWakeup == wakeup else { return }
                self.cooldownWakeup = nil
                guard !self.cooldown.isBlocked(at: self.now()),
                      self.configuration.isEnabled,
                      self.configuration.automaticSuggestions,
                      !self.awaitingUserInput,
                      self.session.state == .idle else { return }
                // Capture current authority again; never generate from the
                // snapshot which happened to start the cooldown timer.
                self.monitor.reevaluateHandledDraft()
            }
        }
    }

    @discardableResult
    func handle(_ action: KeyboardAction) -> Bool {
        diagnostics.keyboard(action)
        switch action {
        case .hostText, .hostAmbiguousText, .hostStateChanged, .dismissSuggestion:
            clearAlternatives()
        default: break
        }
        switch action {
        case let .hostText(text):
            noteUserEdit()
            acceptancePreparation = nil
            awaitingUserInput = false
            typedAppendPending = true
            guard let identity = session.currentIdentity else {
                monitor.refreshAfterInput()
                return false
            }
            switch session.previewTypeThrough(text) {
            case let .advanced(presentation, _):
                if let predicted = presenter.advance(
                    identity: identity,
                    typed: text,
                    remaining: presentation.text
                ) {
                    // The ghost stays where it is; the host is expected to
                    // catch up within a frame. Tab is not consumable until
                    // an authoritative capture agrees.
                    monitor.expect(predicted)
                    monitor.refreshAfterInput()
                    stabilized.beginPrediction(predicted, generation: generation.current)
                    return false
                }
                stabilized.beginReacquisition()
                monitor.requestReanchor()
                _ = presenter.dismiss(identity: identity)
            case .ignored:
                stabilized.beginReacquisition()
                _ = presenter.dismiss(identity: identity)
            case let .completed(completedIdentity, _):
                stabilized.clear()
                _ = presenter.dismiss(identity: completedIdentity)
            case let .cancelled(cancellation):
                stabilized.clear()
                _ = presenter.dismiss(identity: cancellation.identity)
                writeCancellation(cancellation, typedAppend: true)
                typedAppendPending = false
            }
            monitor.refreshAfterInput()
            return false
        case .hostAmbiguousText:
            acceptancePreparation = nil
            typedAppendPending = false
            stabilized.clear()
            _ = presenter.dismiss(identity: nil)
            monitor.refreshAfterInput()
            return false
        case .hostStateChanged:
            acceptancePreparation = nil
            typedAppendPending = false
            stabilized.clear()
            guard let cancellation = session.dismiss() else {
                _ = presenter.dismiss(identity: nil)
                monitor.refreshAfterInput()
                return false
            }
            _ = presenter.dismiss(identity: cancellation.identity)
            writeCancellation(cancellation)
            monitor.refreshAfterInput()
            return false
        case .hostGeometryDisturbed:
            acceptancePreparation = nil
            typedAppendPending = false
            // Scrolling moves the field, not the text. Hide now, keep the
            // request, and republish the anchor once two reads agree.
            if presenter.visibleIdentity != nil {
                stabilized.beginReacquisition()
                _ = presenter.dismissForGeometryChange()
            }
            monitor.requestReanchor()
            monitor.refreshAfterInput()
            return false
        case .dismissSuggestion:
            if let recovery = sourceRecovery {
                monitor.markHandled(recovery.snapshot)
                sourceRecovery = nil
            }
            acceptancePreparation = nil
            typedAppendPending = false
            if presenter.visibleIdentity == nil {
                if let cancellation = session.dismiss() {
                    stabilized.clear()
                    writeCancellation(cancellation)
                }
                // Cancel unseen work without consuming the host's Escape or
                // reporting a rejection of text the user never saw.
                return false
            }
            guard let identity = presenter.visibleIdentity,
                  let presentation = session.presentationFromLastValidatedSnapshot(for: identity),
                  let cancellation = session.dismiss()
            else { return false }
            _ = presenter.dismiss(identity: identity)
            stabilized.clear()
            writeCancellation(cancellation)
            cooldown.dismiss(target: .init(presentation.snapshot), at: now())
            cooldownWakeup = nil
            writeInteraction(identity: identity, outcome: .dismissed, acceptedCharacters: 0)
            return true
        case .acceptSuggestion:
            return attemptAcceptance()
        case .acceptNextWord:
            return attemptAcceptance(nextWordOnly: true)
        case .nextAlternative:
            return navigateAlternative(forward: true)
        case .previousAlternative:
            return navigateAlternative(forward: false)
        }
    }

    private func cancelPendingAlternative(reason: CancelRequestReason = .dismissed) {
        if let pending = pendingAlternative,
           let cancellation = pending.session.dismiss(reason: reason) {
            writeCancellation(cancellation)
        }
        pendingAlternative = nil
    }

    private func clearAlternatives(reason: CancelRequestReason = .contentChanged) {
        cancelPendingAlternative(reason: reason)
        alternatives.removeAll()
        alternativeIndex = 0
    }

    /// Navigation uses the same live draft/source/geometry authority as a
    /// visible ghost. It never performs a synchronous AX read on the event tap.
    private func navigateAlternative(forward: Bool) -> Bool {
        guard let identity = presenter.visibleIdentity,
              let stored = session.presentationFromLastValidatedSnapshot(for: identity),
              presenter.visibleText == stored.text,
              configuration.allows(stored.snapshot.applicationBundleIdentifier),
              !stabilized.isReacquiringAfterPreview,
              let snapshot = monitor.stabilizedSnapshot(matching: stored.snapshot)
        else { return false }
        if !requestContextIsFresh {
            // Neither expired sources nor their generated candidates may seed
            // another request. Recapture the current field and fresh evidence.
            shutdown(reason: .contentChanged)
            handle(.requestSuggestion)
            return true
        }
        if alternatives.isEmpty {
            alternatives = [session]
            alternativeIndex = 0
        }
        if !forward || alternativeIndex < alternatives.count - 1 {
            cancelPendingAlternative()
            let index = forward ? alternativeIndex + 1 : max(0, alternativeIndex - 1)
            guard index != alternativeIndex else { return true }
            alternativeIndex = index
            session = alternatives[index]
            acceptancePreparation = nil
            if let identity = session.currentIdentity { updatePresentation(for: identity) }
            return true
        }
        guard pendingAlternative == nil else { return true }
        let timestampMs = timestampMilliseconds
        let message = SuggestionRequestMessage(
            snapshot: snapshot,
            timestampMs: timestampMs,
            artifacts: activeRequestArtifacts,
            explicit: true,
            alternativeTo: alternatives.compactMap { version in
                version.currentIdentity.flatMap { version.presentationFromLastValidatedSnapshot(for: $0)?.text }
            }
        )
        let candidate = SuggestionSession()
        _ = candidate.begin(message, snapshot: snapshot)
        pendingAlternative = (candidate, generation.current)
        do {
            try writer.writeSuggestionRequest(message)
        } catch {
            cancelPendingAlternative()
            writer.writeDiagnostic("suggestion_request_write_failed")
        }
        return true
    }

    /// A failed/empty/duplicate alternative must not retire the active ghost.
    /// Only a response bound to the current pending request can switch it.
    private func receiveAlternative(_ command: HelperCommand, identity: SuggestionRequestMessage.Identity) -> Bool {
        guard let pending = pendingAlternative,
              pending.session.currentIdentity == identity else { return false }
        guard requestContextIsFresh else {
            shutdown(reason: .contentChanged)
            return true
        }
        pendingAlternative = nil
        guard generation.isCurrent(pending.generation),
              let snapshot = pending.session.snapshotForRequest(identity),
              configuration.allows(snapshot.applicationBundleIdentifier),
              !monitor.sourceEvidenceChanged(matching: snapshot),
              session.hasReadySuggestion else {
            clearAlternatives()
            return true
        }
        guard pending.session.handle(command) == .accepted,
              let candidate = pending.session.presentationFromLastValidatedSnapshot(for: identity),
              !alternatives.contains(where: { version in
                  version.currentIdentity.flatMap { version.presentationFromLastValidatedSnapshot(for: $0)?.text } == candidate.text
              }) else { return true }
        // If geometry is temporarily unstable, discard this alternative. The
        // existing version will reanchor through its ordinary geometry path.
        guard monitor.stabilizedSnapshot(matching: snapshot) != nil else { return true }
        let previous = session
        session = pending.session
        acceptancePreparation = nil
        updatePresentation(for: identity, recordShown: false)
        guard presenter.visibleIdentity == identity,
              let visibleText = presenter.visibleText,
              !alternatives.contains(where: { version in
                  version.currentIdentity.flatMap { version.presentationFromLastValidatedSnapshot(for: $0)?.text } == visibleText
              }) else {
            session = previous
            acceptancePreparation = nil
            if let previousIdentity = previous.currentIdentity { updatePresentation(for: previousIdentity) }
            return true
        }
        reportedShownIdentity = identity
        timeline?.presented(identity: identity)
        writeInteraction(identity: identity, outcome: .shown, acceptedCharacters: 0)
        alternatives.append(session)
        if alternatives.count > 5 { alternatives.removeFirst() }
        alternativeIndex = alternatives.count - 1
        activeRequestExplicit = true
        return true
    }

    /// Consumes Tab or a direct glyph click only for a current, final,
    /// corroborated suggestion whose insertion capability was checked off-main.
    /// Insertion and verification also run off-main; the event tap never waits
    /// for Accessibility reads or writes.
    @discardableResult
    func attemptAcceptance(nextWordOnly: Bool = false) -> Bool {
        guard let identity = presenter.visibleIdentity,
              let stored = session.presentationFromLastValidatedSnapshot(for: identity)
        else { return false }
        guard isAcceptanceReady(for: stored),
              let preparedSnapshot = acceptancePreparation?.presentation.snapshot
        else { return false }
        guard !stabilized.isReacquiringAfterPreview,
              monitor.stabilizedSnapshot(matching: stored.snapshot) != nil
        else {
            stabilized.clear()
            _ = presenter.dismiss(identity: identity)
            monitor.refreshAfterInput()
            return false
        }
        guard let reserved = session.reserveAcceptance(
            visibleIdentity: identity,
            visibleText: presenter.visibleText,
            stabilizedSnapshot: preparedSnapshot,
            nextWordOnly: nextWordOnly
        ) else {
            stabilized.clear()
            _ = presenter.dismiss(identity: identity)
            monitor.refreshAfterInput()
            return false
        }
        clearAlternatives()
        acceptancePreparation = nil
        monitor.setInsertionInProgress(true)
        stabilized.clear()
        presenter.dismissForAcceptance(identity: identity)
        let inserter = self.inserter
        let toMain = dispatchToMain
        let session = self.session
        let generation = self.generation
        let acceptanceGeneration = generation.current
        runInBackground { [weak self] in
            let isCurrent = {
                generation.isCurrent(acceptanceGeneration)
                    && session.isAccepting(identity: reserved.identity)
            }
            let outcome: InsertionOutcome
            if !isCurrent() {
                outcome = .notPrepared
            } else {
                switch inserter.prepare(for: reserved.snapshot) {
                case let .prepared(prepared):
                    outcome = .performed(inserter.insert(reserved.text, prepared: prepared, isCurrent: isCurrent))
                case .staleField, .fieldUnavailable, .unsupportedSelection, .safeMethodUnavailable:
                    outcome = .notPrepared
                }
            }
            toMain { [weak self] in
                self?.finishAcceptance(reserved, outcome: outcome)
            }
        }
        return true
    }

    private func prepareAcceptance(for presentation: SuggestionPresentation) {
        let currentGeneration = generation.current
        let currentAnchorRevision = anchorRevision.current
        guard presenter.visibleIdentity == presentation.identity,
              presenter.visibleText == presentation.text,
              !presentation.text.isEmpty,
              !stabilized.isReacquiringAfterPreview,
              monitor.stabilizedSnapshot(matching: presentation.snapshot) != nil
        else {
            acceptancePreparation = nil
            return
        }
        if let current = acceptancePreparation,
           current.generation == currentGeneration,
           current.anchorRevision == currentAnchorRevision,
           current.presentation == presentation { return }
        let pending = AcceptancePreparation(
            id: UUID(),
            generation: currentGeneration,
            anchorRevision: currentAnchorRevision,
            presentation: presentation
        )
        acceptancePreparation = pending
        let inserter = self.inserter
        let toMain = dispatchToMain
        runInBackground { [weak self] in
            let result = inserter.prepare(for: presentation.snapshot)
            toMain { [weak self] in
                guard let self,
                      self.acceptancePreparation?.id == pending.id,
                      self.generation.isCurrent(pending.generation),
                      self.anchorRevision.isCurrent(pending.anchorRevision),
                      self.configuration.allows(presentation.snapshot.applicationBundleIdentifier),
                      let stored = self.session.presentationFromLastValidatedSnapshot(for: presentation.identity),
                      self.stabilized.anchored(stored, currentGeneration: pending.generation) == presentation,
                      self.monitor.stabilizedSnapshot(matching: presentation.snapshot) != nil,
                      self.presenter.visibleIdentity == presentation.identity,
                      self.presenter.visibleText == presentation.text
                else { return }
                if case let .prepared(prepared) = result,
                   prepared.expectedSnapshot == presentation.snapshot {
                    self.acceptancePreparation?.isReady = true
                }
            }
        }
    }

    private func isAcceptanceReady(for stored: SuggestionPresentation) -> Bool {
        guard let preparation = acceptancePreparation,
              preparation.isReady,
              generation.isCurrent(preparation.generation),
              anchorRevision.isCurrent(preparation.anchorRevision),
              presenter.visibleIdentity == preparation.presentation.identity,
              presenter.visibleText == preparation.presentation.text,
              stabilized.anchored(stored, currentGeneration: preparation.generation)
                == preparation.presentation
        else { return false }
        return true
    }

    private enum InsertionOutcome: Sendable {
        case notPrepared
        case performed(NotesInsertionResult)
    }

    private func finishAcceptance(_ reserved: ReservedSuggestion, outcome: InsertionOutcome) {
        var resumed = false
        if case let .performed(.inserted(_, snapshot)) = outcome,
           !reserved.remainingText.isEmpty {
            resumed = session.resumeAfterPartialAcceptance(reserved, snapshot: snapshot)
        }
        if !resumed { session.completeAcceptance(identity: reserved.identity) }
        switch outcome {
        case .notPrepared:
            monitor.setInsertionInProgress(false)
            monitor.refreshAfterInput()
            writeInteraction(identity: reserved.identity, outcome: .stale, acceptedCharacters: 0)
        case let .performed(result):
            switch result {
            case let .inserted(_, snapshot):
                cooldown.reset()
                cooldownWakeup = nil
                onAccepted(reserved.identity, reserved.text, snapshot)
                monitor.markHandled(snapshot)
                monitor.setInsertionInProgress(false)
                if resumed {
                    stabilized.beginReacquisition()
                    monitor.requestReanchor()
                    monitor.refreshAfterInput()
                }
                writeInteraction(
                    identity: reserved.identity,
                    outcome: reserved.isPartialAcceptance ? .acceptedPartial : .acceptedFull,
                    acceptedCharacters: reserved.typedThroughCharacters
                        + reserved.text.utf16.count
                )
            case .staleField:
                monitor.setInsertionInProgress(false)
                writeInteraction(identity: reserved.identity, outcome: .stale, acceptedCharacters: 0)
            case .fieldUnavailable,
                 .unsupportedSelection,
                 .safeMethodUnavailable,
                 .writeFailed,
                 .verificationFailed:
                monitor.setInsertionInProgress(false)
                writeInteraction(identity: reserved.identity, outcome: .failed, acceptedCharacters: 0)
            }
        }
    }

    private func runInBackground(_ work: @escaping @Sendable () -> Void) {
        if let backgroundDispatcher {
            backgroundDispatcher(work)
        } else {
            monitor.performOffMain(work)
        }
    }

    // MARK: - Writer helpers

    private func writeCancellation(
        _ cancellation: CancelRequestMessage,
        typedAppend: Bool = false
    ) {
        do {
            try writer.writeCancelRequest(cancellation)
            timeline?.cancelWritten(
                identity: cancellation.identity,
                reason: cancellation.payload.reason,
                typedAppend: typedAppend
            )
        } catch {
            writer.writeDiagnostic("cancel_request_write_failed")
        }
    }

    private func writeInteraction(
        identity: SuggestionRequestMessage.Identity,
        outcome: InteractionOutcome,
        acceptedCharacters: Int
    ) {
        do {
            try writer.writeInteraction(
                identity: identity,
                outcome: outcome,
                acceptedCharacters: acceptedCharacters
            )
            timeline?.interaction(identity: identity, outcome: outcome)
        } catch {
            writer.writeDiagnostic("interaction_write_failed")
        }
    }

    private static func timelineRejection(
        _ reason: GhostTextPresenterRejectionReason?
    ) -> HelperPresentationRejection {
        switch reason {
        case .staleCapture: .presenterStaleCapture
        case .paragraphEmptyCompletion: .presenterParagraphEmptyCompletion
        case .paragraphFocusChanged: .presenterParagraphFocusChanged
        case .paragraphCaptureUnavailable: .presenterParagraphCaptureUnavailable
        case .paragraphSelectionActive: .presenterParagraphSelectionActive
        case .paragraphNotAtEnd: .presenterParagraphNotAtEnd
        case .paragraphGeometryUnavailable: .presenterParagraphGeometryUnavailable
        case .paragraphCaretUnavailable: .presenterParagraphCaretUnavailable
        case .paragraphFieldUnavailable: .presenterParagraphFieldUnavailable
        case .paragraphCaretInvalid: .presenterParagraphCaretInvalid
        case .paragraphFieldInvalid: .presenterParagraphFieldInvalid
        case .paragraphCaretOutsideField: .presenterParagraphCaretOutsideField
        case .paragraphDisplayUnavailable: .presenterParagraphDisplayUnavailable
        case .paragraphMetricsUnavailable: .presenterParagraphMetricsUnavailable
        case .paragraphPrefixMismatch: .presenterParagraphPrefixMismatch
        case .paragraphLayout: .presenterParagraphLayout
        case .paragraphOutsideVisibleField: .presenterParagraphOutsideVisibleField
        case .singleLineLayout: .presenterSingleLineLayout
        case .displayRejected, .none: .presenterDisplayRejected
        }
    }
}

extension GhostTextPresenter: GhostPresenting {}

extension MessageWriter: HelperMessageWriting {}

extension NotesTextInserter: SuggestionInserting {}
