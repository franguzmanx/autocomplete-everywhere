import Foundation

protocol TransformMessageWriting: AnyObject, Sendable {
    func writeTransformRequest(_ message: TransformRequestMessage) throws
    func writeCancelRequest(_ message: CancelRequestMessage) throws
}
extension MessageWriter: TransformMessageWriting {}

/// Keeps replacement authority in the helper. Requests and insertions
/// are invalidated by any host input; an authoritative read precedes each write.
enum TransformDiagnostic: String {
    case invoked, captured, requested, received, inserted
    case captureUnavailable = "capture_unavailable", selectionUnavailable = "selection_unavailable"
    case generationFailed = "generation_failed", unchanged, sourceChanged = "source_changed"
    case insertionFailed = "insertion_failed", cancelled
}

@MainActor
final class TransformController {
    private let capture: @Sendable () -> ActiveFieldCaptureResult
    private let replace: @Sendable (String, ActiveFieldSnapshot, @Sendable () -> Bool) -> NotesInsertionResult
    private let background: SuggestionController.BackgroundDispatcher
    private let writer: any TransformMessageWriting
    private let diagnostic: (TransformDiagnostic) -> Void
    private let onFailure: () -> Void
    private let suspendSuggestions: (Bool) -> Void
    private var shortcuts: [TransformShortcut] = []
    private var enabled = false
    private var generation: UInt64 = 0
    private let insertionGeneration = ActiveFieldGeneration()
    private var pendingCapture = false
    private var inserting = false
    private var target: ActiveFieldSnapshot?
    private var identity: SuggestionRequestMessage.Identity?
    private var timer: Timer?
    private var checking = false
    private var deadline = Date.distantPast
    var isActive: Bool { pendingCapture || target != nil || inserting }

    init(capture: @escaping @Sendable () -> ActiveFieldCaptureResult,
         replace: @escaping @Sendable (String, ActiveFieldSnapshot, @Sendable () -> Bool) -> NotesInsertionResult,
         background: @escaping SuggestionController.BackgroundDispatcher,
         writer: any TransformMessageWriting,
         diagnostic: @escaping (TransformDiagnostic) -> Void = { _ in },
         onFailure: @escaping () -> Void = {},
         suspendSuggestions: @escaping (Bool) -> Void) {
        self.capture = capture
        self.replace = replace
        self.background = background
        self.writer = writer
        self.onFailure = onFailure
        self.diagnostic = diagnostic
        self.suspendSuggestions = suspendSuggestions
    }

    func invalidateContext(requestIds: [String]) {
        guard let identity, requestIds.contains(identity.requestId) else { return }
        cancel()
    }

    func configure(_ shortcuts: [TransformShortcut]) { cancel(); self.shortcuts = shortcuts }
    func setEnabled(_ enabled: Bool) { cancel(); self.enabled = enabled }

    func handle(_ input: KeyboardInput) -> Bool {
        if enabled, let shortcut = TransformPolicy.shortcut(for: input, shortcuts: shortcuts) {
            guard !inserting else { return true }
            begin(shortcut)
            return true
        }
        guard isActive else { return false }
        if input.modifiers.isEmpty && !input.isRepeat && input.keyCode == 53 {
            cancel()
            return true
        }
        // The user's keystroke proceeds normally. It must never be overwritten.
        cancel()
        return false
    }

    func cancel(report: Bool = true) {
        if report, isActive { diagnostic(.cancelled) }
        generation &+= 1
        insertionGeneration.advance()
        if let identity {
            try? writer.writeCancelRequest(.init(identity: identity, payload: .init(reason: .dismissed)))
        }
        pendingCapture = false
        target = nil
        identity = nil
        timer?.invalidate()
        timer = nil
        // An already-reserved insertion owns the capture queue until it returns.
        if !inserting { suspendSuggestions(false) }
    }

    private func fail() {
        cancel()
        onFailure()
    }

    private func begin(_ shortcut: TransformShortcut) {
        cancel()
        pendingCapture = true
        diagnostic(.invoked)
        suspendSuggestions(true)
        let version = generation
        let capture = self.capture
        background { [weak self] in
            let result = capture()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == version, self.enabled else { return }
                self.pendingCapture = false
                guard case let .captured(snapshot) = result else {
                    self.diagnostic(.captureUnavailable)
                    self.fail()
                    return
                }
                guard TransformPolicy.eligible(snapshot) else {
                    self.diagnostic(.selectionUnavailable)
                    self.fail()
                    return
                }
                self.diagnostic(.captured)
                self.target = snapshot
                let identity = SuggestionRequestMessage(snapshot: snapshot).identity
                self.identity = identity
                self.deadline = Date().addingTimeInterval(17)
                do {
                    self.diagnostic(.requested)
                    try self.writer.writeTransformRequest(.init(identity: identity, payload: .init(
                        appId: snapshot.applicationBundleIdentifier, transformId: shortcut.id, text: snapshot.selectedText, singleLine: snapshot.fieldKind == .singleLine)))
                } catch { self.fail(); return }
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.validateTarget() }
                }
            }
        }
    }

    func validateTarget() {
        guard !checking, !inserting, let target else { return }
        if Date() > deadline { fail(); return }
        checking = true
        let version = generation
        let capture = self.capture
        background { [weak self] in
            let result = capture()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.checking = false
                guard self.generation == version else { return }
                // An unavailable AX sample is not evidence of a changed target.
                // Keep the pending request until the next bounded poll; final
                // insertion still requires a fresh matching capture.
                if case let .skipped(reason) = result, reason.isTransientReadFailure { return }
                guard case let .captured(current) = result, TransformPolicy.matches(current, target) else {
                    self.diagnostic(.sourceChanged); self.cancel(); return
                }
            }
        }
    }

    func receive(_ result: TransformResultCommand) {
        guard result.identity == identity, let target, !inserting else { return }
        guard Date() <= deadline else { fail(); return }
        guard let text = result.text, TransformPolicy.validOutput(text, singleLine: target.fieldKind == .singleLine) else {
            diagnostic(.generationFailed)
            fail(); return
        }
        diagnostic(.received)
        guard text != target.selectedText else { diagnostic(.unchanged); cancel(report: false); return }
        let capture = self.capture
        let version = generation
        background { [weak self] in
            let captured = capture()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == version, !self.inserting else { return }
                guard case let .captured(current) = captured, TransformPolicy.matches(current, target) else {
                    self.diagnostic(.sourceChanged); self.cancel(); return
                }
                self.replaceSelection(with: text)
            }
        }
    }

    private func replaceSelection(with text: String) {
        guard let target else { return }
        guard Date() <= deadline else { cancel(); return }
        inserting = true
        timer?.invalidate()
        timer = nil
        let replace = self.replace
        let gate = insertionGeneration
        let token = gate.current
        let version = generation
        background { [weak self] in
            let result = gate.isCurrent(token)
                ? replace(text, target, { gate.isCurrent(token) })
                : .staleField
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inserting = false
                let wasCancelled = self.generation != version
                self.cancel(report: false)
                if wasCancelled { return }
                switch result {
                case .inserted: self.diagnostic(.inserted)
                default:
                    self.diagnostic(.insertionFailed)
                    self.fail()
                }
            }
        }
    }
}
