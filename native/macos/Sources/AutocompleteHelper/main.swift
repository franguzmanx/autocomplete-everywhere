import AppKit
import Darwin
import Foundation

@MainActor
final class HelperRuntime {
    private let writer: MessageWriter
    private let parentMonitor: ParentMonitor
    private let parentProcessIdentifier: pid_t
    private let fixtureDiagnostics: FixtureDiagnostics
    private let timelineTracer: HelperTimelineTracer
    private lazy var accessibilityReader = SystemAccessibilityReader(
        excludedProcessIdentifier: parentProcessIdentifier,
        focusDiagnostic: { [writer] axPID, workspacePID in
            writer.writeDiagnostic("focus_authority ax_pid=\(axPID ?? -1) workspace_pid=\(workspacePID ?? -1) mismatch=\(axPID != workspacePID)")
        },
        webCaretDiagnostic: { [fixtureDiagnostics] in fixtureDiagnostics.webCaret($0) },
        typographyDiagnostic: { [fixtureDiagnostics] in fixtureDiagnostics.fontMeasurement($0) },
        webReadDiagnostic: { [fixtureDiagnostics] in fixtureDiagnostics.webRead($0) },
        sourceReadDiagnostic: { [fixtureDiagnostics] in fixtureDiagnostics.sourceRead($0) }
    )
    private let inputQueue = DispatchQueue(label: "com.autocompletion.command-input")
    private lazy var contextObserver = ContextObserver(excludedPID: parentProcessIdentifier, writer: writer)
    private var shuttingDown = false
    private var configuration = CaptureConfiguration.disabled
    private lazy var applicationMonitor = ApplicationMonitor(parentPID: parentProcessIdentifier, writer: writer)

    private lazy var activeFieldCapture = ActiveFieldCapture(
        reader: accessibilityReader,
        excludedProcessIdentifier: Int32(parentProcessIdentifier)
    )
    private lazy var ghostPresenter = GhostTextPresenter(
        display: GhostTextPanel(),
        overflowDiagnostic: { [fixtureDiagnostics, timelineTracer] identity, overflow in
            fixtureDiagnostics.overflow(overflow)
            timelineTracer.presentationOverflow(identity: identity, overflow: overflow)
        },
        typographyDiagnostic: { [timelineTracer] identity, measurement in
            timelineTracer.typography(identity: identity, measurement: measurement)
        }
    )
    private lazy var insertionAccessibility = SystemNotesInsertionAccessibility(
        reader: accessibilityReader,
        capture: { [activeFieldCapture] in activeFieldCapture.capture() }
    )
    private lazy var textInserter = NotesTextInserter(
        accessibility: insertionAccessibility,
        unicodePoster: SystemUnicodeTextPoster(),
        verificationDelay: { Thread.sleep(forTimeInterval: 0.05) }
    )
    private let recentWritingContext = RecentWritingContext()
    private lazy var correctionObservation: AcceptedCorrectionObservation = AcceptedCorrectionObservation(
        now: { Int64(Date().timeIntervalSince1970 * 1_000) },
        capture: { [activeFieldCapture] in activeFieldCapture.capture() },
        scheduleExpiry: { [weak self] delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.suggestionController.monitor.performOffMain(work)
            }
        },
        emit: { [writer, timelineTracer] event in
            do {
                switch event {
                case let .interaction(identity, outcome):
                    try writer.writeInteraction(identity: identity, outcome: outcome, acceptedCharacters: 0)
                    timelineTracer.interaction(identity: identity, outcome: outcome)
                case let .correction(message):
                    try writer.writeCorrectionObserved(message)
                }
            } catch {
                writer.writeDiagnostic("learning_message_write_failed")
            }
        }
    )
    private let userActivityQueue = DispatchQueue(label: "com.autocompletion.user-activity")
    private lazy var userActivityReporter = UserActivityReporter(
        dispatch: { [userActivityQueue] work in userActivityQueue.async(execute: work) },
        emit: { [writer] in
            do { try writer.writeUserActivity() }
            catch { writer.writeDiagnostic("user_activity_write_failed") }
        }
    )
    private lazy var contextArtifactSource = ContextArtifactSource(
        clipboardChangeCount: { NSPasteboard.general.changeCount },
        clipboardText: { NSPasteboard.general.string(forType: .string) }
    )
    private lazy var suggestionController: SuggestionController = SuggestionController(
        capture: { [activeFieldCapture, fixtureDiagnostics, recentWritingContext, correctionObservation] in
            let result = activeFieldCapture.capture()
            fixtureDiagnostics.capture(result)
            let timestampMs = Int64(Date().timeIntervalSince1970 * 1_000)
            recentWritingContext.observe(result, timestampMs: timestampMs)
            correctionObservation.observe(result, timestampMs: timestampMs)
            return result
        },
        presenter: ghostPresenter,
        inserter: textInserter,
        writer: writer,
        diagnostics: fixtureDiagnostics,
        contextArtifacts: { [contextArtifactSource, recentWritingContext] snapshot, timestampMs in
            let explicit = contextArtifactSource.artifacts(
                selectedText: snapshot.selectedText,
                timestampMs: timestampMs
            )
            let recent = recentWritingContext.artifacts(for: snapshot, timestampMs: timestampMs)
                .filter { artifact in !explicit.contains { $0.text == artifact.text } }
            return explicit + recent
        },
        onAccepted: { [weak self, recentWritingContext, correctionObservation] identity, text, snapshot in
            recentWritingContext.recordAcceptance(
                text: text, snapshot: snapshot,
                timestampMs: Int64(Date().timeIntervalSince1970 * 1_000)
            )
            let timestampMs = Int64(Date().timeIntervalSince1970 * 1_000)
            self?.suggestionController.monitor.performOffMain {
                correctionObservation.recordAcceptance(identity: identity, text: text, snapshot: snapshot, timestampMs: timestampMs)
            }
        },
        timeline: timelineTracer
    )
    private lazy var transformController = TransformController(
        capture: { [activeFieldCapture, fixtureDiagnostics] in
            let result = activeFieldCapture.capture()
            fixtureDiagnostics.capture(result)
            return result
        },
        replace: { [textInserter] text, snapshot, isCurrent in
            switch textInserter.prepareReplacement(for: snapshot) {
            case let .prepared(prepared): return textInserter.insert(text, prepared: prepared, isCurrent: isCurrent)
            case .staleField: return .staleField
            case .fieldUnavailable: return .fieldUnavailable
            case .unsupportedSelection: return .unsupportedSelection
            case .safeMethodUnavailable: return .safeMethodUnavailable
            }
        },
        background: { [monitor = suggestionController.monitor!] work in monitor.performOffMain(work) },
        writer: writer,
        diagnostic: { [fixtureDiagnostics] in fixtureDiagnostics.transform($0) },
        onFailure: { NSSound.beep() },
        suspendSuggestions: { [weak self] suspended in
            guard let self else { return }
            if suspended { self.suggestionController.shutdown(reason: .dismissed) }
            self.suggestionController.monitor.setInsertionInProgress(suspended)
            if !suspended { self.suggestionController.monitor.refreshAfterInput() }
        }
    )
    private lazy var permissionMonitor = PermissionStateMonitor(
        provider: SystemPermissionStateProvider()
    ) { [writer, fixtureDiagnostics] state in
        fixtureDiagnostics.permission(state)
        do {
            try writer.writePermissionState(state)
        } catch {
            writer.writeDiagnostic("permission_state_write_failed")
        }
    }
    private lazy var keyboardMonitor = KeyboardMonitor(
        sessionProvider: { [weak self] in
            self?.suggestionController.keyboardStatus() ?? .inactive
        },
        actionHandler: { [weak self] action in
            self?.suggestionController.handle(action) ?? false
        },
        onUserEdit: { [weak self] in
            guard let self else { return }
            if case .accepting = self.suggestionController.sessionState { return }
            if self.transformController.isActive { return }
            self.suggestionController.noteUserEdit()
            self.correctionObservation.noteUserEdit(timestampMs: Int64(Date().timeIntervalSince1970 * 1_000))
            self.userActivityReporter.noteUserEdit()
            self.recentWritingContext.noteUserEdit(timestampMs: Int64(Date().timeIntervalSince1970 * 1_000))
        }
    )
    private lazy var pointerMonitor = PointerMonitor(
        hitRegionsProvider: { [weak self] in
            self?.suggestionController.visibleGlyphRegions ?? []
        },
        acceptanceHandler: { [weak self] in
            self?.suggestionController.attemptAcceptance() ?? false
        },
        stateChangeHandler: { [weak self] in
            self?.transformController.cancel()
            _ = self?.suggestionController.handle(.hostStateChanged)
        },
        inputHandler: { [weak self] point in
            self?.suggestionController.notePointerInput(at: point)
        },
        geometryDisturbedHandler: { [weak self] in
            _ = self?.suggestionController.handle(.hostGeometryDisturbed)
        }
    )

    init(parentPID: pid_t, writer: MessageWriter) {
        self.writer = writer
        fixtureDiagnostics = FixtureDiagnostics()
        timelineTracer = HelperTimelineTracer()
        parentMonitor = ParentMonitor(parentPID: parentPID)
        parentProcessIdentifier = parentPID
    }

    func start() throws {
        // Initialize AppKit's display environment on the main thread before
        // the first bounded source read runs on the capture queue.
        _ = accessibilityReader.displayGeometries()
        parentMonitor.start()
        try writer.writeHello()
        contextObserver.publishScreenPermission()
        keyboardMonitor.inputHandler = { [weak self] input in self?.transformController.handle(input) ?? false }
        applicationMonitor.start()
        permissionMonitor.start()
        suggestionController.monitor.start()
        startCommandInput()
    }

    private func startCommandInput() {
        let writer = writer
        inputQueue.async { [weak self] in
            let reader = LineReader()
            let decoder = HelperCommandDecoder()
            reader.readStandardInput { line in
                guard line.utf8.count <= 65_536 else {
                    writer.writeDiagnostic("command_too_large")
                    return
                }
                guard let command = decoder.decode(line) else {
                    writer.writeDiagnostic("invalid_command")
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    self?.handle(command)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.shutdown()
            }
        }
    }

    private func handle(_ command: HelperCommand) {
        if case .contextRequestScreenPermission = command {
            contextObserver.requestScreenPermission()
        } else if case let .contextInvalidate(ids) = command {
            transformController.invalidateContext(requestIds: ids)
            suggestionController.handle(command)
        } else if case let .configure(configuration) = command {
            apply(configuration)
        } else if case let .transformConfigure(shortcuts) = command {
            transformController.configure(shortcuts)
        } else if case let .transformResult(result) = command {
            transformController.receive(result)
        } else {
            suggestionController.handle(command)
        }
    }

    private func apply(_ configuration: CaptureConfiguration) {
        guard self.configuration != configuration else { return }
        let resuming = !self.configuration.isEnabled && configuration.isEnabled
        self.configuration = configuration
        keyboardMonitor.configure(accept: configuration.acceptShortcut, dismiss: configuration.dismissShortcut)
        var effectiveConfiguration = configuration
        if configuration.isEnabled {
            if !keyboardMonitor.start() {
                writer.writeDiagnostic("keyboard_monitor_unavailable")
                effectiveConfiguration = .disabled
            } else if !pointerMonitor.start() {
                writer.writeDiagnostic("pointer_monitor_unavailable")
                effectiveConfiguration = .disabled
            }
        }
        if !effectiveConfiguration.isEnabled {
            keyboardMonitor.stop()
            pointerMonitor.stop()
        }
        transformController.setEnabled(effectiveConfiguration.isEnabled)
        contextObserver.configure(effectiveConfiguration)
        activeFieldCapture.updateConfiguration(effectiveConfiguration)
        contextArtifactSource.updateConfiguration(effectiveConfiguration)
        recentWritingContext.updateConfiguration(effectiveConfiguration)
        correctionObservation.updateConfiguration(effectiveConfiguration)
        suggestionController.updateConfiguration(effectiveConfiguration, waitForInput: resuming)
    }

    private func shutdown() {
        guard !shuttingDown else { return }
        shuttingDown = true
        contextObserver.configure(.disabled)
        keyboardMonitor.stop()
        applicationMonitor.stop()
        pointerMonitor.stop()
        suggestionController.monitor.stop()
        permissionMonitor.stop()
        transformController.cancel()
        suggestionController.shutdown()
        recentWritingContext.updateConfiguration(.disabled)
        correctionObservation.updateConfiguration(.disabled)
        NSApplication.shared.terminate(nil)
    }
}

let writer = MessageWriter()
guard let parentPID = HelperArguments.parentPID(from: CommandLine.arguments) else {
    writer.writeDiagnostic("invalid_arguments")
    exit(EX_USAGE)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let runtime = HelperRuntime(parentPID: parentPID, writer: writer)
do {
    try runtime.start()
} catch {
    writer.writeDiagnostic("hello_write_failed")
    exit(EX_IOERR)
}
application.run()
