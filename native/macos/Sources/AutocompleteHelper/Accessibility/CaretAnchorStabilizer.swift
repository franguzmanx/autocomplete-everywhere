import Foundation

struct CaretAnchorSample: Equatable, Sendable {
    let fieldIdentity: String
    let contentIdentity: String
    let captureSequence: UInt64
    let rect: CGRect
}

enum CaretAnchorDecision: Equatable, Sendable { case hold, accept, hide }

/// Two spatially concordant samples for the same field and content state are
/// required before an anchor may be shown or moved. A predicted sample (the
/// caret position implied by locally typed text) may stand in for the first
/// of the two, so that an authoritative read that agrees with it confirms
/// immediately and one that disagrees hides the prediction.
struct CaretAnchorStabilizer: Sendable {
    private var identity: (String, String)?
    private var sequence: UInt64 = 0
    private var pending: CaretAnchorSample?
    private var accepted: CaretAnchorSample?
    private var pendingIsPrediction = false

    var isResolved: Bool { accepted != nil && pending == nil }

    mutating func observe(_ sample: CaretAnchorSample) -> CaretAnchorDecision {
        if sequence > 0, sample.captureSequence <= sequence { reset(); return .hide }
        let nextIdentity = (sample.fieldIdentity, sample.contentIdentity)
        if let identity, identity != nextIdentity {
            reset()
            self.identity = nextIdentity
            sequence = sample.captureSequence
            pending = sample
            return .hide
        }
        identity = nextIdentity; sequence = sample.captureSequence
        if let accepted {
            pendingIsPrediction = false
            if concordant(accepted.rect, sample.rect) { pending = nil; return .hold }
            if let pending, concordant(pending.rect, sample.rect) {
                self.accepted = sample
                self.pending = nil
                return .accept
            }
            if pending != nil {
                // One bad sample can be a transient host/macOS popover. Two
                // different bad samples mean the host is moving or reflowing;
                // keeping the old overlay visible would leave a frozen ghost.
                self.accepted = nil
                self.pending = sample
                return .hide
            }
            pending = sample
            return .hold
        }
        if let pending, concordant(pending.rect, sample.rect) {
            self.accepted = sample; self.pending = nil; pendingIsPrediction = false; return .accept
        }
        if pendingIsPrediction {
            // The host disagrees with the locally predicted caret: the
            // prediction is on screen and must go.
            pendingIsPrediction = false
            pending = sample
            return .hide
        }
        pending = sample
        return .hold
    }

    /// Seeds the next content state with a predicted sample. The next
    /// authoritative sample with the same identity is accepted immediately
    /// when it agrees, and hides the prediction when it does not.
    mutating func expect(_ sample: CaretAnchorSample) {
        identity = (sample.fieldIdentity, sample.contentIdentity)
        sequence = sample.captureSequence
        pending = sample
        accepted = nil
        pendingIsPrediction = true
    }

    private mutating func reset() {
        identity = nil; sequence = 0; pending = nil; accepted = nil; pendingIsPrediction = false
    }

    private func concordant(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.midX - b.midX) <= 2 && abs(a.midY - b.midY) <= 2 && abs(a.height - b.height) <= 1
    }
}
