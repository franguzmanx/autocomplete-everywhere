import Foundation
import XCTest
@testable import AutocompleteHelper

final class PermissionStateMonitorTests: XCTestCase {
    func testHelloAdvertisesPermissionStateCapability() {
        XCTAssertEqual(
            HelloMessage().payload.capabilities,
            [
                "lifecycle",
                "permission_state",
                "notes_capture",
                "ghost_text",
                "notes_insertion",
            ]
        )
    }

    func testEmitsInitialStateAndOnlySubsequentChanges() {
        let provider = FakePermissionStateProvider(
            state: NativePermissionState(
                accessibility: .required,
                inputMonitoring: .required
            )
        )
        var received: [NativePermissionState] = []
        let monitor = PermissionStateMonitor(provider: provider) { state in
            received.append(state)
        }

        monitor.checkForChanges()
        monitor.checkForChanges()
        provider.state = NativePermissionState(
            accessibility: .granted,
            inputMonitoring: .required
        )
        monitor.checkForChanges()

        XCTAssertEqual(
            received,
            [
                NativePermissionState(
                    accessibility: .required,
                    inputMonitoring: .required
                ),
                NativePermissionState(
                    accessibility: .granted,
                    inputMonitoring: .required
                ),
            ]
        )
    }

    func testStartRequestsOSAccessOnlyOnce() {
        let provider = FakePermissionStateProvider(
            state: NativePermissionState(
                accessibility: .required,
                inputMonitoring: .required
            )
        )
        let monitor = PermissionStateMonitor(provider: provider) { _ in }

        monitor.start()
        monitor.start()

        XCTAssertEqual(provider.requestCount, 1)
        monitor.stop()
    }

    func testStartedMonitorStaysAliveLongEnoughToEmit() {
        let emitted = expectation(description: "initial permission state")
        var monitor: PermissionStateMonitor<FakePermissionStateProvider>? =
            PermissionStateMonitor(
                provider: FakePermissionStateProvider(
                    state: NativePermissionState(
                        accessibility: .granted,
                        inputMonitoring: .granted
                    )
                )
            ) { _ in
                emitted.fulfill()
            }
        weak var runningMonitor = monitor

        monitor?.start()
        monitor = nil

        wait(for: [emitted], timeout: 0.5)
        XCTAssertNotNil(runningMonitor)
        runningMonitor?.stop()
    }

    func testPermissionMessageContainsOnlyTheContentFreeState() throws {
        let message = PermissionStateMessage(
            state: NativePermissionState(
                accessibility: .granted,
                inputMonitoring: .required
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any]
        )

        XCTAssertEqual(object["protocolVersion"] as? Int, 5)
        XCTAssertEqual(object["type"] as? String, "permission_state")
        XCTAssertEqual(
            object["payload"] as? [String: String],
            ["accessibility": "granted", "inputMonitoring": "required"]
        )
        XCTAssertEqual(Set(object.keys), ["protocolVersion", "type", "payload"])
    }
}

private final class FakePermissionStateProvider: PermissionStateProviding {
    var state: NativePermissionState
    private(set) var requestCount = 0

    init(state: NativePermissionState) {
        self.state = state
    }

    func currentState() -> NativePermissionState { state }

    func requestAccess() {
        requestCount += 1
    }
}
