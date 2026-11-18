import Foundation

/// Content-free, transient dismissal state for the current physical field.
/// A key only marks an edit opportunity; a corroborated draft change releases
/// the edit gate. There is no semantic inference or retained writing here.
struct SuggestionCooldown {
    struct Target: Equatable {
        let appId: String
        let elementId: String
        let focusGeneration: UInt64

        init(appId: String, elementId: String, focusGeneration: UInt64) {
            self.appId = appId
            self.elementId = elementId
            self.focusGeneration = focusGeneration
        }

        init(_ snapshot: ActiveFieldSnapshot) {
            self.init(
                appId: snapshot.applicationBundleIdentifier,
                elementId: snapshot.elementIdentifier,
                focusGeneration: snapshot.focusGeneration
            )
        }
    }

    private var target: Target?
    private var lastDismissal: TimeInterval?
    private var deadline: TimeInterval?
    private var editOpportunity: TimeInterval?
    private var hasAuthoredEdit = false

    mutating func dismiss(target: Target, at now: TimeInterval) {
        observeTarget(target)
        let repeated = lastDismissal.map { now >= $0 && now - $0 <= 60 } == true
        self.target = target
        lastDismissal = now
        deadline = now + (repeated ? 3 : 1)
        editOpportunity = nil
        hasAuthoredEdit = false
    }

    @discardableResult
    mutating func observeTarget(_ target: Target) -> Bool {
        guard let previous = self.target, previous != target else { return false }
        reset()
        return true
    }

    mutating func noteUserEdit(at now: TimeInterval) {
        guard deadline != nil, !hasAuthoredEdit else { return }
        editOpportunity = now
    }

    /// Returns a single wakeup delay once a physical edit is corroborated.
    mutating func observeDraftEdit(target: Target, at now: TimeInterval) -> TimeInterval? {
        observeTarget(target)
        guard self.target == target, let deadline, !hasAuthoredEdit,
              let editOpportunity, now >= editOpportunity,
              now - editOpportunity <= 1 else { return nil }
        hasAuthoredEdit = true
        self.editOpportunity = nil
        return max(0, deadline - now)
    }

    /// A new stable draft may need a wakeup after a manual request retired
    /// the previous one. Preserve the original deadline and authored edit gate.
    func remainingDelay(at now: TimeInterval) -> TimeInterval? {
        guard hasAuthoredEdit, let deadline, deadline > now else { return nil }
        return deadline - now
    }

    func isBlocked(at now: TimeInterval) -> Bool {
        guard let deadline else { return false }
        return !hasAuthoredEdit || now < deadline
    }

    mutating func reset() {
        self = SuggestionCooldown()
    }
}
