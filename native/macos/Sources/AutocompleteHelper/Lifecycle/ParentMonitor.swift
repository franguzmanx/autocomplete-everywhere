import Darwin
import Foundation

final class ParentMonitor: @unchecked Sendable {
    private let parentPID: pid_t
    private let queue = DispatchQueue(label: "com.autocompletion.parent-monitor")
    private var timer: DispatchSourceTimer?

    init(parentPID: pid_t) {
        self.parentPID = parentPID
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [parentPID] in
            errno = 0
            if kill(parentPID, 0) == -1 && errno == ESRCH {
                exit(EXIT_SUCCESS)
            }
        }
        self.timer = timer
        timer.resume()
    }
}
