import CryptoKit
import Foundation

final class ActiveFieldGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    var current: UInt64 { lock.withLock { value } }

    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        lock.withLock { generation == value }
    }
}

final class ActiveFieldMonitor: @unchecked Sendable {
    typealias PostInputScheduler = (
        TimeInterval,
        @escaping @Sendable () -> Void
    ) -> Void

    /// Reads scheduled after a keystroke. The first observes the host's
    /// publication; the second corroborates it without waiting for the next
    /// timer tick, so a typed-through ghost is confirmed within a frame.
    static let postInputReadDelays: [TimeInterval] = [0.012, 0.045]
    /// Chromium can briefly publish focus, value, range, or marker state out
    /// of phase while its renderer is busy. Count-based tolerance is unsafe
    /// because post-input reads intentionally arrive in a burst.
    static let transientReadFailureToleranceMilliseconds: Double = 250

    private let capture: () -> ActiveFieldCaptureResult
    private var quietInterval: TimeInterval
    private let onStableSnapshot: (ActiveFieldSnapshot, UInt64) -> Void
    private let onGeometryChanged: (ActiveFieldSnapshot, UInt64) -> Void
    private let onGeometryHidden: (UInt64) -> Void
    private let onInvalidated: (ActiveFieldSnapshot?, UInt64) -> Void
    private let queue: DispatchQueue
    private let scheduleAfterHostPublication: PostInputScheduler
    private let scheduleQuietDeadline: PostInputScheduler
    private let now: () -> TimeInterval
    private let timeline: (any HelperTimelineTracing)?
    private let monotonicMilliseconds: () -> Double
    private let generation: ActiveFieldGeneration
    private let lock = NSLock()
    private var configuration = CaptureConfiguration.disabled
    private var observedSignature: String?
    private var lastDraftSnapshot: ActiveFieldSnapshot?
    private let onObservedDraftEdit: (ActiveFieldSnapshot, UInt64) -> Void
    private var observedRequestSignature: String?
    private var observedAt: TimeInterval?
    private var pendingSnapshot: ActiveFieldSnapshot?
    private var isRefreshingSource = false
    private var lastEmittedRequestSignature: String?
    private var anchorStabilizer = CaretAnchorStabilizer()
    private var hasAcceptedAnchor = false
    private var acceptedAnchorSnapshot: ActiveFieldSnapshot?
    private var shouldNotifyAfterReacquisition = false
    private var insertionInProgress = false
    private var transientFailureStartedMilliseconds: Double?
    private var traceConsecutiveSkips = 0
    private var lastSuccessfulCaptureMilliseconds: Double?
    private var lastSuccessfulFocusSequence: UInt64?
    private var quietDeadlineSequence: UInt64 = 0
    private var schedulesQuietDeadlines: Bool
    private var timer: DispatchSourceTimer?

    init(
        capture: @escaping () -> ActiveFieldCaptureResult,
        quietInterval: TimeInterval = 0.3,
        onStableSnapshot: @escaping (ActiveFieldSnapshot, UInt64) -> Void,
        onGeometryChanged: @escaping (ActiveFieldSnapshot, UInt64) -> Void = { _, _ in },
        onGeometryHidden: @escaping (UInt64) -> Void = { _ in },
        onInvalidated: @escaping (ActiveFieldSnapshot?, UInt64) -> Void = { _, _ in },
        onObservedDraftEdit: @escaping (ActiveFieldSnapshot, UInt64) -> Void = { _, _ in },
        generation: ActiveFieldGeneration = ActiveFieldGeneration(),
        scheduleAfterHostPublication: PostInputScheduler? = nil,
        scheduleQuietDeadline: PostInputScheduler? = nil,
        timeline: (any HelperTimelineTracing)? = nil,
        monotonicMilliseconds: @escaping () -> Double = {
            ProcessInfo.processInfo.systemUptime * 1_000
        },
        now: @escaping () -> TimeInterval = {
            Date.timeIntervalSinceReferenceDate
        }
    ) {
        let queue = DispatchQueue(label: "com.autocompletion.active-field")
        self.capture = capture
        self.quietInterval = quietInterval
        self.onStableSnapshot = onStableSnapshot
        self.onGeometryChanged = onGeometryChanged
        self.onGeometryHidden = onGeometryHidden
        self.onInvalidated = onInvalidated
        self.onObservedDraftEdit = onObservedDraftEdit
        self.generation = generation
        self.timeline = timeline
        self.monotonicMilliseconds = monotonicMilliseconds
        self.queue = queue
        self.scheduleAfterHostPublication = scheduleAfterHostPublication ?? { delay, work in
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
        self.scheduleQuietDeadline = scheduleQuietDeadline ?? { delay, work in
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
        schedulesQuietDeadlines = scheduleQuietDeadline != nil
        self.now = now
    }

    func updateConfiguration(_ configuration: CaptureConfiguration) {
        var shouldInvalidate = false
        var callbackGeneration: UInt64 = 0
        lock.lock()
        callbackGeneration = advanceGenerationLocked()
        let changed = self.configuration != configuration
        self.configuration = configuration
        self.quietInterval = configuration.automaticSuggestions ? Double(configuration.quietPeriodMs) / 1000 : 0.3
        if changed || !configuration.isEnabled {
            shouldInvalidate = hasObservation
            clearObservationState()
        }
        lock.unlock()
        if shouldInvalidate { onInvalidated(nil, callbackGeneration) }
    }

    /// Re-arm only after a completed result was rejected for changed evidence.
    /// While re-armed, source updates must settle before another request leaves.
    func refreshSource(after expected: ActiveFieldSnapshot) {
        lock.withLock {
            guard let current = lastDraftSnapshot,
                  current.contentSignature == expected.contentSignature,
                  current.recentWritingContextSignature != expected.recentWritingContextSignature
            else { return }
            isRefreshingSource = true
            observedRequestSignature = nil
            lastEmittedRequestSignature = nil
        }
    }

    func markHandled(_ snapshot: ActiveFieldSnapshot) {
        lock.withLock {
            isRefreshingSource = false
            observedSignature = snapshot.contentSignature
            observedRequestSignature = snapshot.requestSignature
            observedAt = nil
            pendingSnapshot = nil
            lastEmittedRequestSignature = snapshot.requestSignature
        }
    }

    func setInsertionInProgress(_ inProgress: Bool) {
        lock.withLock {
            _ = advanceGenerationLocked()
            insertionInProgress = inProgress
            if inProgress { clearObservationState() }
        }
    }

    /// Runs work on the capture queue, serialized with polling. Insertion
    /// and its verification reads belong here, never on the main thread that
    /// services the event taps.
    func performOffMain(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    func refreshAfterInput() {
        let generation = lock.withLock { advanceGenerationLocked() }
        for delay in Self.postInputReadDelays {
            scheduleAfterHostPublication(delay) { [weak self] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                self.poll(at: self.now(), expectedGeneration: generation)
            }
        }
    }

    /// Reopens a handled draft after a field click or dismissal cooldown. Fresh captures and
    /// the usual quiet interval still establish the request and its authority.
    func reevaluateHandledDraft() {
        lock.withLock {
            observedRequestSignature = nil
            lastEmittedRequestSignature = nil
            observedAt = nil
            pendingSnapshot = nil
        }
        refreshAfterInput()
    }

    /// Registers the caret position implied by locally typed text. The next
    /// authoritative capture that agrees is accepted immediately; one that
    /// disagrees hides the predicted ghost.
    func expect(_ predicted: ActiveFieldSnapshot) {
        lock.withLock {
            guard let sample = Self.anchorSample(predicted) else { return }
            anchorStabilizer.expect(sample)
        }
    }

    /// Asks for the current stable anchor to be published again, for example
    /// after the ghost was hidden proactively during a scroll.
    func requestReanchor() {
        lock.withLock { shouldNotifyAfterReacquisition = true }
    }

    func isCurrentGeneration(_ generation: UInt64) -> Bool {
        self.generation.isCurrent(generation)
    }

    func stabilizedSnapshot(
        matching expected: ActiveFieldSnapshot
    ) -> ActiveFieldSnapshot? {
        lock.withLock {
            guard hasAcceptedAnchor,
                  anchorStabilizer.isResolved,
                  let acceptedAnchorSnapshot,
                  acceptedAnchorSnapshot.geometryQuality != .unavailable,
                  acceptedAnchorSnapshot.geometrySource != nil,
                  acceptedAnchorSnapshot.caretBounds != nil,
                  acceptedAnchorSnapshot.applicationBundleIdentifier
                    == expected.applicationBundleIdentifier,
                  acceptedAnchorSnapshot.elementIdentifier
                    == expected.elementIdentifier,
                  acceptedAnchorSnapshot.focusGeneration
                    == expected.focusGeneration,
                  acceptedAnchorSnapshot.contentSignature
                    == expected.contentSignature,
                  acceptedAnchorSnapshot.recentWritingContextSignature
                    == expected.recentWritingContextSignature,
                  acceptedAnchorSnapshot.captureSequence
                    >= expected.captureSequence
            else { return nil }
            return acceptedAnchorSnapshot
        }
    }

    /// Distinguishes changed reply evidence from missing physical geometry.
    /// No source contents or hashes leave the capture process.
    func sourceEvidenceChanged(matching expected: ActiveFieldSnapshot) -> Bool {
        lock.withLock {
            guard let current = lastDraftSnapshot,
                  current.applicationBundleIdentifier == expected.applicationBundleIdentifier,
                  current.elementIdentifier == expected.elementIdentifier,
                  current.focusGeneration == expected.focusGeneration,
                  current.contentSignature == expected.contentSignature,
                  current.captureSequence >= expected.captureSequence else { return false }
            return current.recentWritingContextSignature != expected.recentWritingContextSignature
        }
    }

    func poll(at now: TimeInterval) {
        poll(at: now, expectedGeneration: nil)
    }

    private func poll(
        at now: TimeInterval,
        expectedGeneration: UInt64?
    ) {
        lock.lock()
        guard configuration.isEnabled,
              !insertionInProgress,
              expectedGeneration == nil
                || expectedGeneration == generation.current
        else {
            lock.unlock()
            return
        }
        let startedGeneration = generation.current
        lock.unlock()

        let captureStartedMilliseconds = monotonicMilliseconds()
        let result = capture()
        let captureEndedMilliseconds = monotonicMilliseconds()
        let captureMilliseconds = max(
            0,
            captureEndedMilliseconds - captureStartedMilliseconds
        )
        var stableSnapshot: ActiveFieldSnapshot?
        var stableQuietMilliseconds: Double?
        var observedSnapshot: ActiveFieldSnapshot?
        var skippedTrace: (
            focusSequence: UInt64?,
            reason: ActiveFieldSkipReason,
            consecutive: Int,
            sinceLastOKMilliseconds: Double?
        )?
        var geometrySnapshot: ActiveFieldSnapshot?
        var shouldHideGeometry = false
        var shouldInvalidate = false
        var invalidatedSnapshot: ActiveFieldSnapshot?
        var editedSnapshot: ActiveFieldSnapshot?
        var callbackGeneration: UInt64
        var quietDeadline: (
            observedAt: TimeInterval,
            generation: UInt64,
            sequence: UInt64
        )?

        lock.lock()
        guard configuration.isEnabled,
              !insertionInProgress,
              generation.current == startedGeneration
        else {
            lock.unlock()
            return
        }

        switch result {
        case let .skipped(reason):
            lastDraftSnapshot = nil
            traceConsecutiveSkips += 1
            skippedTrace = (
                focusSequence: lastSuccessfulFocusSequence,
                reason: reason,
                consecutive: traceConsecutiveSkips,
                sinceLastOKMilliseconds: lastSuccessfulCaptureMilliseconds.map {
                    max(0, captureEndedMilliseconds - $0)
                }
            )
            if reason.isTransientReadFailure, hasObservation {
                let failureStartedMilliseconds =
                    transientFailureStartedMilliseconds ?? captureEndedMilliseconds
                transientFailureStartedMilliseconds = failureStartedMilliseconds
                if captureEndedMilliseconds - failureStartedMilliseconds
                    > Self.transientReadFailureToleranceMilliseconds {
                    transientFailureStartedMilliseconds = nil
                    shouldInvalidate = true
                    clearObservationState()
                    _ = advanceGenerationLocked()
                }
            } else {
                transientFailureStartedMilliseconds = nil
                shouldInvalidate = hasObservation
                clearObservationState()
                _ = advanceGenerationLocked()
            }
        case let .captured(snapshot):
            if let previous = lastDraftSnapshot, ObservedDraftMutation.changed(from: previous, to: snapshot) {
                editedSnapshot = snapshot
            }
            let sourceChanged = lastDraftSnapshot?.recentWritingContextSignature != snapshot.recentWritingContextSignature
            lastDraftSnapshot = snapshot
            traceConsecutiveSkips = 0
            lastSuccessfulCaptureMilliseconds = captureEndedMilliseconds
            lastSuccessfulFocusSequence = snapshot.focusGeneration
            transientFailureStartedMilliseconds = nil
            let signature = snapshot.contentSignature
            let requestSignature = snapshot.requestSignature
            let contentChanged = signature != observedSignature
            let requestChanged = requestSignature != observedRequestSignature
                || (isRefreshingSource && sourceChanged)
            if contentChanged {
                isRefreshingSource = false
                observedSnapshot = snapshot
                // `refreshAfterInput` already advanced the generation before
                // scheduling its two corroboration reads. Advancing again on
                // the first read would invalidate the second one and make a
                // single transient sample look authoritative.
                if expectedGeneration == nil {
                    _ = advanceGenerationLocked()
                }
                shouldInvalidate = hasObservation
                invalidatedSnapshot = snapshot
                observedSignature = signature
            }
            if requestChanged {
                observedRequestSignature = requestSignature
                observedAt = now
                pendingSnapshot = snapshot
                quietDeadlineSequence &+= 1
                if schedulesQuietDeadlines {
                    quietDeadline = (
                        observedAt: now,
                        generation: generation.current,
                        sequence: quietDeadlineSequence
                    )
                }
            }

            // Refresh scene text until the draft's quiet deadline, then keep
            // that request intact while the same surrounding objects update.
            if requestSignature != lastEmittedRequestSignature, var pending = pendingSnapshot {
                pending.fieldContext = snapshot.fieldContext
                pendingSnapshot = pending
            }
            let anchorDecision: CaretAnchorDecision
            if let sample = Self.anchorSample(snapshot) {
                anchorDecision = anchorStabilizer.observe(sample)
            } else {
                anchorStabilizer = CaretAnchorStabilizer()
                anchorDecision = .hide
            }
            switch anchorDecision {
            case .hold:
                if hasAcceptedAnchor,
                   let acceptedAnchorSnapshot,
                   Self.fieldFrameMoved(
                       from: acceptedAnchorSnapshot.inputFrame,
                       to: snapshot.inputFrame
                   ) {
                    shouldHideGeometry = true
                    shouldNotifyAfterReacquisition = true
                    hasAcceptedAnchor = false
                    self.acceptedAnchorSnapshot = nil
                } else if hasAcceptedAnchor, anchorStabilizer.isResolved {
                    acceptedAnchorSnapshot = snapshot
                    if shouldNotifyAfterReacquisition {
                        shouldNotifyAfterReacquisition = false
                        geometrySnapshot = snapshot
                    }
                }
            case .accept:
                let shouldNotify = hasAcceptedAnchor || shouldNotifyAfterReacquisition
                hasAcceptedAnchor = true
                acceptedAnchorSnapshot = snapshot
                shouldNotifyAfterReacquisition = false
                if requestSignature != lastEmittedRequestSignature {
                    pendingSnapshot = snapshot
                }
                if shouldNotify {
                    geometrySnapshot = snapshot
                }
            case .hide:
                // A derived caret can briefly oscillate while the host lays
                // out unchanged text. Keep the last valid overlay visible and
                // replace it once a new anchor is corroborated. Explicit
                // scroll events still hide immediately in the controller.
                shouldHideGeometry = hasAcceptedAnchor
                    && (contentChanged || snapshot.geometryQuality != .derived || Self.fieldFrameMoved(
                        from: acceptedAnchorSnapshot?.inputFrame,
                        to: snapshot.inputFrame
                    ))
                shouldNotifyAfterReacquisition =
                    hasAcceptedAnchor || shouldNotifyAfterReacquisition
                hasAcceptedAnchor = false
                acceptedAnchorSnapshot = nil
            }

            if (!contentChanged || quietInterval == 0),
                let firstObservedAt = observedAt,
                now >= firstObservedAt + quietInterval,
                requestSignature != lastEmittedRequestSignature,
                let pendingSnapshot,
                pendingSnapshot.requestSignature == requestSignature
            {
                lastEmittedRequestSignature = requestSignature
                self.pendingSnapshot = nil
                isRefreshingSource = false
                if quietInterval == 0 { quietDeadline = nil }
                stableSnapshot = pendingSnapshot
                stableQuietMilliseconds = max(0, (now - firstObservedAt) * 1_000)
            }
        }
        callbackGeneration = generation.current
        lock.unlock()

        if let quietDeadline {
            let delay = max(
                0,
                quietDeadline.observedAt + quietInterval - self.now()
            )
            scheduleQuietDeadline(delay) { [weak self] in
                guard let self else { return }
                let isCurrent = self.lock.withLock {
                    quietDeadline.sequence == self.quietDeadlineSequence
                        && self.generation.isCurrent(quietDeadline.generation)
                }
                guard isCurrent else { return }
                self.poll(
                    at: self.now(),
                    expectedGeneration: quietDeadline.generation
                )
            }
        }

        if let observedSnapshot {
            timeline?.inputObserved(
                focusSequence: observedSnapshot.focusGeneration,
                captureSequence: observedSnapshot.captureSequence,
                captureMilliseconds: captureMilliseconds
            )
        }
        if let stableSnapshot, let stableQuietMilliseconds {
            timeline?.contentStable(
                focusSequence: stableSnapshot.focusGeneration,
                quietMilliseconds: stableQuietMilliseconds
            )
        }
        if let skippedTrace {
            timeline?.captureSkipped(
                focusSequence: skippedTrace.focusSequence,
                reason: skippedTrace.reason,
                consecutive: skippedTrace.consecutive,
                sinceLastOKMilliseconds: skippedTrace.sinceLastOKMilliseconds
            )
        }

        if let editedSnapshot {
            onObservedDraftEdit(editedSnapshot, callbackGeneration)
        }
        if shouldInvalidate {
            onInvalidated(invalidatedSnapshot, callbackGeneration)
        }
        if shouldHideGeometry {
            onGeometryHidden(callbackGeneration)
        }
        if let geometrySnapshot {
            onGeometryChanged(geometrySnapshot, callbackGeneration)
        }
        // Retire the previous observation before starting an instant request
        // from this capture; invalidation must not clear the new request.
        if let stableSnapshot {
            onStableSnapshot(stableSnapshot, callbackGeneration)
        }
    }

    func start() {
        guard timer == nil else { return }
        lock.withLock { schedulesQuietDeadlines = true }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler { [self] in
            poll(at: Date.timeIntervalSinceReferenceDate)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        lock.withLock { _ = advanceGenerationLocked() }
        guard let timer else { return }
        timer.setEventHandler {}
        timer.cancel()
        self.timer = nil
    }

    private func clearObservationState() {
        isRefreshingSource = false
        lastDraftSnapshot = nil
        quietDeadlineSequence &+= 1
        observedSignature = nil
        observedRequestSignature = nil
        observedAt = nil
        pendingSnapshot = nil
        lastEmittedRequestSignature = nil
        anchorStabilizer = CaretAnchorStabilizer()
        hasAcceptedAnchor = false
        acceptedAnchorSnapshot = nil
        shouldNotifyAfterReacquisition = false
        transientFailureStartedMilliseconds = nil
    }

    @discardableResult
    private func advanceGenerationLocked() -> UInt64 {
        generation.advance()
    }

    private var hasObservation: Bool {
        observedSignature != nil || lastEmittedRequestSignature != nil
    }

    private static func anchorSample(
        _ snapshot: ActiveFieldSnapshot
    ) -> CaretAnchorSample? {
        guard
            snapshot.geometryQuality != .unavailable,
            snapshot.geometrySource != nil,
            let rect = snapshot.caretBounds
        else { return nil }
        let fieldIdentity = [
            snapshot.applicationBundleIdentifier,
            snapshot.elementIdentifier,
            String(snapshot.focusGeneration),
        ].joined(separator: "|")
        return CaretAnchorSample(
            fieldIdentity: fieldIdentity,
            contentIdentity: snapshot.contentSignature,
            captureSequence: snapshot.captureSequence,
            rect: rect
        )
    }

    private static func fieldFrameMoved(from previous: CGRect?, to current: CGRect?) -> Bool {
        guard let previous, let current else { return false }
        return abs(previous.minX - current.minX) > 2
            || abs(previous.minY - current.minY) > 2
            || abs(previous.width - current.width) > 2
            || abs(previous.height - current.height) > 2
    }
}

extension ActiveFieldSnapshot {
    /// Content-free fingerprint of the paragraph layout inputs. The first-line
    /// indent and the vertical origin are excluded on purpose: both move with
    /// the caret while typing through a line-filled completion, and a caret
    /// move is already detected spatially.
    var paragraphRenderFingerprint: String {
        guard let metrics = paragraphMetrics else { return "unavailable" }
        let attributes = metrics.attributes
        let direction = switch metrics.writingDirection {
        case .leftToRight: "ltr"
        case .rightToLeft: "rtl"
        }
        let components = [
            scalarIdentity(metrics.origin.x),
            scalarIdentity(metrics.width),
            scalarIdentity(metrics.lineHeight),
            direction,
            metrics.textStyle.fontName,
            scalarIdentity(metrics.textStyle.fontSize),
            scalarIdentity(attributes.headIndent),
            scalarIdentity(attributes.tailIndent),
            scalarIdentity(attributes.lineSpacing),
            scalarIdentity(attributes.paragraphSpacingBefore),
            scalarIdentity(attributes.paragraphSpacingAfter),
            attributes.listMarker == nil ? "no-list" : "list",
            attributes.listLevel.map(String.init) ?? "no-level",
            metrics.typographyIsEstimated ? "estimated" : "measured",
        ] + attributes.tabStops.map(scalarIdentity) + metrics.prefixStyleRuns.flatMap {
            [
                String($0.range.location),
                String($0.range.length),
                $0.style.fontName,
                scalarIdentity($0.style.fontSize),
            ]
        }
        return stableSignature(components)
    }

    var contentSignature: String {
        let components = [
            applicationBundleIdentifier,
            elementIdentifier,
            String(focusGeneration),
            String(selectionRange.location),
            String(selectionRange.length),
            textBefore,
            selectedText,
            textAfter,
            contextIdentitySignature,
        ]
        return stableSignature(components)
    }

    /// A source's identity belongs to the reply target. Its live text belongs
    /// to the request snapshot, not the insertion revision: streaming text or
    /// changing counters must not cancel an otherwise unchanged draft.
    var contextIdentitySignature: String {
        var components = [fieldContext.shape.rawValue, fieldContext.label ?? "", fieldContext.placeholder ?? ""]
        components.append(String(fieldContext.relatedFields.count))
        for field in fieldContext.relatedFields {
            components.append(contentsOf: [field.shape.rawValue, field.label ?? "", field.placeholder ?? "",
                // Companion single-line controls can select recipients or
                // subjects; preserve their full value as part of the target.
                field.shape == .singleLine ? field.text
                    : (field.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "empty" : "populated")])
        }
        components.append(String(fieldContext.sources.count))
        for source in fieldContext.sources.sorted(by: { $0.id < $1.id }) {
            components.append(contentsOf: [source.id, source.containerId, source.relation.rawValue])
        }
        return stableSignature(components)
    }

    /// Shared evidence digest for recall and final acceptance, including hosts
    /// that reuse editor/message nodes. Scheduling identity remains separate
    /// so streaming context does not endlessly restart generation.
    var recentWritingContextSignature: String {
        stableSignature([contextIdentitySignature]
            + fieldContext.relatedFields.map(\.text)
            + fieldContext.sources.sorted(by: { $0.id < $1.id }).map(\.text))
    }

    var requestSignature: String {
        contentSignature
    }
}

private func scalarIdentity(_ value: CGFloat) -> String {
    String(Double(value).bitPattern)
}

private func stableSignature(_ components: [String]) -> String {
    var data = Data()
    for component in components {
        let bytes = Data(component.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
