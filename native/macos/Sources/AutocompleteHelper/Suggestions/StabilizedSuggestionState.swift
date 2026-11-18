import Foundation

/// The runtime's view of which snapshot a visible suggestion is anchored to.
/// A presentation is only ever drawn from a snapshot the monitor accepted (or
/// predicted and then had corroborated) for the current field generation.
struct StabilizedSuggestionState: Sendable {
    private var acceptedSnapshot: ActiveFieldSnapshot?
    private var acceptedGeneration: UInt64?
    private(set) var isReacquiringAfterPreview = false

    mutating func begin(at snapshot: ActiveFieldSnapshot, generation: UInt64) {
        acceptedSnapshot = snapshot
        acceptedGeneration = generation
        isReacquiringAfterPreview = false
    }

    mutating func clear() {
        acceptedSnapshot = nil
        acceptedGeneration = nil
        isReacquiringAfterPreview = false
    }

    /// The ghost was hidden on a keystroke and waits for authoritative
    /// geometry before it may reappear.
    mutating func beginReacquisition() {
        acceptedSnapshot = nil
        acceptedGeneration = nil
        isReacquiringAfterPreview = true
    }

    /// The ghost stayed visible on a keystroke at a locally predicted caret.
    /// Until the host corroborates it, nothing may be inserted and no server
    /// response may render against the prediction.
    mutating func beginPrediction(_ predicted: ActiveFieldSnapshot, generation: UInt64) {
        acceptedSnapshot = predicted
        acceptedGeneration = generation
        isReacquiringAfterPreview = true
    }

    mutating func reconcileAuthoritativeAdvance() -> Bool {
        acceptedSnapshot = nil
        acceptedGeneration = nil
        return isReacquiringAfterPreview
    }

    mutating func acceptGeometry(
        _ snapshot: ActiveFieldSnapshot,
        generation: UInt64
    ) {
        acceptedSnapshot = snapshot
        acceptedGeneration = generation
        isReacquiringAfterPreview = false
    }

    mutating func shouldHideForUnstableGeometry() -> Bool {
        acceptedSnapshot = nil
        acceptedGeneration = nil
        return true
    }

    func anchored(
        _ presentation: SuggestionPresentation,
        currentGeneration: UInt64
    ) -> SuggestionPresentation? {
        guard !isReacquiringAfterPreview,
              acceptedGeneration == currentGeneration,
              let acceptedSnapshot,
              acceptedSnapshot.applicationBundleIdentifier
                == presentation.snapshot.applicationBundleIdentifier,
              acceptedSnapshot.elementIdentifier
                == presentation.snapshot.elementIdentifier,
              acceptedSnapshot.focusGeneration
                == presentation.snapshot.focusGeneration,
              acceptedSnapshot.contentSignature
                == presentation.snapshot.contentSignature
        else { return nil }
        return SuggestionPresentation(
            identity: presentation.identity,
            text: presentation.text,
            snapshot: acceptedSnapshot
        )
    }
}
