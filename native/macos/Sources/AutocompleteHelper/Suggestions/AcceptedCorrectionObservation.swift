import Foundation

/// One bounded, RAM-only observation of a verified insertion. Capture and
/// mutation comparison run on the capture queue; physical keys only mark time.
final class AcceptedCorrectionObservation: @unchecked Sendable {
    enum Event: Sendable {
        case interaction(SuggestionRequestMessage.Identity, InteractionOutcome)
        case correction(CorrectionObservedMessage)
    }

    private struct Window {
        let text: String
        let start: Int
        let captureSequence: UInt64

        init?(_ snapshot: ActiveFieldSnapshot) {
            guard snapshot.selectionRange.location >= snapshot.textBefore.utf16.count,
                  snapshot.selectionRange.length == snapshot.selectedText.utf16.count else { return nil }
            let text = snapshot.textBefore + snapshot.selectedText + snapshot.textAfter
            guard text.utf16.count <= 12_000 else { return nil }
            self.text = text
            start = snapshot.selectionRange.location - snapshot.textBefore.utf16.count
            captureSequence = snapshot.captureSequence
        }
    }

    private struct Observation {
        let identity: SuggestionRequestMessage.Identity
        let target: SuggestionCooldown.Target
        let before: String
        let sessionId: String
        let startedAt: Int64
        var range: NSRange
        var window: Window
        var verifiedAt: Int64
        var editOpportunity: Int64?
    }

    private let lock = NSLock()
    private let now: @Sendable () -> Int64
    private let capture: @Sendable () -> ActiveFieldCaptureResult
    private let scheduleExpiry: (TimeInterval, @escaping @Sendable () -> Void) -> Void
    private let emit: @Sendable (Event) -> Void
    private var configuration = CaptureConfiguration.disabled
    private var observation: Observation?
    private var lastAcceptedRequest: String?
    private var sessionId = UUID().uuidString
    private var lastActivity: Int64?

    init(now: @escaping @Sendable () -> Int64, capture: @escaping @Sendable () -> ActiveFieldCaptureResult,
         scheduleExpiry: @escaping (TimeInterval, @escaping @Sendable () -> Void) -> Void,
         emit: @escaping @Sendable (Event) -> Void) {
        self.now = now
        self.capture = capture
        self.scheduleExpiry = scheduleExpiry
        self.emit = emit
    }

    func updateConfiguration(_ configuration: CaptureConfiguration) {
        let events = lock.withLock { () -> [Event] in
            self.configuration = configuration
            guard let observation,
                  !configuration.learningEnabled || !configuration.allows(observation.target.appId) else { return [] }
            return abandonLocked()
        }
        events.forEach(emit)
    }

    func noteUserEdit(timestampMs: Int64) {
        lock.withLock {
            noteActivityLocked(timestampMs)
            guard let current = observation,
                  timestampMs >= current.startedAt,
                  timestampMs < current.startedAt + 30_000 else { return }
            observation?.editOpportunity = timestampMs
        }
    }

    func recordAcceptance(identity: SuggestionRequestMessage.Identity, text: String, snapshot: ActiveFieldSnapshot, timestampMs: Int64) {
        var scheduledIdentity: String?
        let seedTime = now()
        let events = lock.withLock { () -> [Event] in
            guard configuration.learningEnabled, configuration.allows(snapshot.applicationBundleIdentifier),
                  lastAcceptedRequest != identity.requestId else { return [] }
            let previousEvents = abandonLocked()
            lastAcceptedRequest = identity.requestId
            noteActivityLocked(timestampMs)
            guard timestampMs >= 0, timestampMs <= Int64.max - 30_000,
                  seedTime >= timestampMs, seedTime < timestampMs + 30_000,
                  !text.isEmpty, text.utf16.count <= 2_000,
                  identity.focusSequence == snapshot.focusGeneration,
                  snapshot.selectionRange.length == 0,
                  snapshot.textBefore.hasSuffix(text), let window = Window(snapshot) else {
                return previousEvents + [.interaction(identity, .observationUnavailable)]
            }
            let range = NSRange(location: snapshot.textBefore.utf16.count - text.utf16.count, length: text.utf16.count)
            observation = Observation(identity: identity, target: .init(snapshot), before: text, sessionId: sessionId,
                                      startedAt: timestampMs, range: range, window: window, verifiedAt: timestampMs)
            scheduledIdentity = identity.requestId
            return previousEvents
        }
        events.forEach(emit)
        guard let requestId = scheduledIdentity else { return }
        scheduleExpiry(max(0, Double(timestampMs + 30_000 - now()) / 1_000)) { [weak self] in
            guard let self, self.lock.withLock({ self.observation?.identity.requestId == requestId }) else { return }
            // This scheduler is wired to the capture queue. Read current field
            // authority at expiry, rather than emitting a stale cached contrast.
            let result = self.capture()
            let events = self.lock.withLock { () -> [Event] in
                guard self.observation?.identity.requestId == requestId else { return [] }
                return self.observeLocked(result, timestampMs: self.now())
            }
            events.forEach(self.emit)
        }
    }

    func observe(_ result: ActiveFieldCaptureResult, timestampMs: Int64) {
        let events = lock.withLock { observeLocked(result, timestampMs: timestampMs) }
        events.forEach(emit)
    }

    private func observeLocked(_ result: ActiveFieldCaptureResult, timestampMs: Int64) -> [Event] {
        guard var current = observation else { return [] }
        guard configuration.learningEnabled, configuration.allows(current.target.appId),
              case let .captured(snapshot) = result,
              SuggestionCooldown.Target(snapshot) == current.target,
              let window = Window(snapshot), window.start == current.window.start,
              window.captureSequence >= current.window.captureSequence,
              timestampMs >= current.verifiedAt else { return abandonLocked() }
        if current.window.text != window.text {
            guard timestampMs <= current.startedAt + 30_000,
                  window.captureSequence > current.window.captureSequence,
                  let edit = current.editOpportunity, timestampMs >= edit, timestampMs - edit <= 1_000,
                  let range = correctedRange(from: current.window.text, to: window.text, owned: current.range),
                  range.length <= 2_000 else { return abandonLocked() }
            current.range = range
            current.editOpportunity = nil
            if range.length == 0 {
                observation = nil
                return [.interaction(current.identity, .removedAfterAcceptance)]
            }
        }
        current.window = window
        current.verifiedAt = timestampMs
        observation = current
        guard timestampMs >= current.startedAt + 30_000 else { return [] }
        observation = nil
        guard let range = Range(current.range, in: window.text) else {
            return [.interaction(current.identity, .observationUnavailable)]
        }
        let after = String(window.text[range])
        guard after != current.before else { return [] }
        return [
            .interaction(current.identity, .editedAfterAcceptance),
            .correction(.init(identity: current.identity, payload: .init(appId: current.target.appId,
                sessionId: current.sessionId, before: current.before, after: after, observedAtMs: timestampMs))),
        ]
    }

    /// Find a bounded replacement in grapheme coordinates, then use UTF-16
    /// document ranges. Repeated-text edits with multiple possible locations
    /// are unknown, as are insertions at either edge (ordinary continuation).
    private func correctedRange(from old: String, to new: String, owned: NSRange) -> NSRange? {
        let oldChars = Array(old), newChars = Array(new)
        let shortest = min(oldChars.count, newChars.count)
        var prefix = 0, suffix = 0
        while prefix < shortest, oldChars[prefix] == newChars[prefix] { prefix += 1 }
        while suffix < shortest, oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] { suffix += 1 }
        guard prefix + suffix <= shortest else { return nil }
        let start = String(oldChars.prefix(prefix)).utf16.count
        let removed = String(oldChars[prefix..<(oldChars.count - suffix)]).utf16.count
        let inserted = String(newChars[prefix..<(newChars.count - suffix)]).utf16.count
        guard start >= owned.location, start + removed <= NSMaxRange(owned),
              removed > 0 || (start > owned.location && start < NSMaxRange(owned)) else { return nil }
        return NSRange(location: owned.location, length: owned.length - removed + inserted)
    }

    private func abandonLocked() -> [Event] {
        guard let observation else { return [] }
        self.observation = nil
        return [.interaction(observation.identity, .observationUnavailable)]
    }

    private func noteActivityLocked(_ timestampMs: Int64) {
        if let lastActivity, timestampMs < lastActivity || timestampMs - lastActivity >= 30 * 60 * 1_000 {
            sessionId = UUID().uuidString
        }
        lastActivity = timestampMs
    }
}
