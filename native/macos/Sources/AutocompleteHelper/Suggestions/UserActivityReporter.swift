import Foundation

/// Keeps physical key callbacks content-free and nonblocking even if the
/// desktop pipe is busy. One queued signal is enough to cancel background work.
@MainActor
final class UserActivityReporter {
    private let dispatch: (@escaping @Sendable () -> Void) -> Void
    private let emit: @Sendable () -> Void
    private let pending = Pending()

    private final class Pending: @unchecked Sendable {
        let lock = NSLock()
        var value = false
    }

    init(dispatch: @escaping (@escaping @Sendable () -> Void) -> Void, emit: @escaping @Sendable () -> Void) {
        self.dispatch = dispatch
        self.emit = emit
    }

    func noteUserEdit() {
        let pending = self.pending, emit = self.emit
        let shouldDispatch = pending.lock.withLock {
            guard !pending.value else { return false }
            pending.value = true
            return true
        }
        guard shouldDispatch else { return }
        dispatch {
            emit()
            pending.lock.withLock { pending.value = false }
        }
    }
}
