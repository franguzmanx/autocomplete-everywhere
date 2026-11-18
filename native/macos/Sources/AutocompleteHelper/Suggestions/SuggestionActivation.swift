import Foundation

/// Focus discovery is not user intent. Authorize only the field reached by an
/// edit or a pointer interaction, and discard intent at a target boundary.
struct SuggestionActivation {
    struct Target: Equatable {
        let app: String
        let element: String
        let focus: UInt64
        init(_ snapshot: ActiveFieldSnapshot) {
            app = snapshot.applicationBundleIdentifier
            element = snapshot.elementIdentifier
            focus = snapshot.focusGeneration
        }
    }
    private var target: Target?
    private var pending: (app: String, point: CGPoint?, deadline: TimeInterval)?

    mutating func input(app: String, point: CGPoint? = nil, now: TimeInterval) {
        target = nil
        pending = (app, point, now + 1)
    }
    mutating func observedEdit(_ snapshot: ActiveFieldSnapshot) {
        target = Target(snapshot)
        pending = nil
    }
    mutating func allows(_ snapshot: ActiveFieldSnapshot, now: TimeInterval) -> Bool {
        let current = Target(snapshot)
        if let pending {
            if pending.deadline < now || pending.app != current.app {
                self.pending = nil
            } else if pending.point.map({ snapshot.inputFrame?.contains($0) == true }) ?? true {
                target = current
                self.pending = nil
            }
        }
        if target != current { target = nil }
        return target == current
    }
}
