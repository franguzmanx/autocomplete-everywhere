@preconcurrency import ApplicationServices
import Foundation

enum PermissionGrant: String, Encodable {
    case required
    case granted
}

struct NativePermissionState: Encodable, Equatable {
    let accessibility: PermissionGrant
    let inputMonitoring: PermissionGrant
}

struct PermissionStateMessage: Encodable {
    let protocolVersion = 5
    let type = "permission_state"
    let payload: NativePermissionState

    init(state: NativePermissionState) {
        payload = state
    }
}

protocol PermissionStateProviding {
    func currentState() -> NativePermissionState
    func requestAccess()
}

struct SystemPermissionStateProvider: PermissionStateProviding {
    func currentState() -> NativePermissionState {
        NativePermissionState(
            accessibility: AXIsProcessTrusted() ? .granted : .required,
            inputMonitoring: CGPreflightListenEventAccess() ? .granted : .required
        )
    }

    func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
    }
}

final class PermissionStateMonitor<Provider: PermissionStateProviding>: @unchecked Sendable {
    private let provider: Provider
    private let onChange: (NativePermissionState) -> Void
    private let queue = DispatchQueue(label: "com.autocompletion.permission-state")
    private let lock = NSLock()
    private var lastState: NativePermissionState?
    private var timer: DispatchSourceTimer?

    init(
        provider: Provider,
        onChange: @escaping (NativePermissionState) -> Void
    ) {
        self.provider = provider
        self.onChange = onChange
    }

    func checkForChanges() {
        let state = provider.currentState()
        lock.lock()
        let changed = state != lastState
        if changed {
            lastState = state
        }
        lock.unlock()

        if changed {
            onChange(state)
        }
    }

    func start() {
        guard timer == nil else { return }
        provider.requestAccess()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [self] in
            checkForChanges()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        guard let timer else { return }
        timer.setEventHandler {}
        timer.cancel()
        self.timer = nil
    }
}
