import XCTest
@testable import AutocompleteHelper

final class UserActivityReporterTests: XCTestCase {
    @MainActor
    func testPhysicalEditsEmitOffCallbackAndCoalesceWhilePipeIsPending() {
        let output = Output()
        var pending: [@Sendable () -> Void] = []
        let reporter = UserActivityReporter(dispatch: { pending.append($0) }, emit: { output.count += 1 })
        for _ in 0..<10_000 { reporter.noteUserEdit() }
        XCTAssertEqual(output.count, 0, "The event tap must never wait for a pipe write")
        XCTAssertEqual(pending.count, 1)
        pending.removeFirst()()
        XCTAssertEqual(output.count, 1)
        reporter.noteUserEdit()
        XCTAssertEqual(pending.count, 1)
        pending.removeFirst()()
        XCTAssertEqual(output.count, 2)
    }

    private final class Output: @unchecked Sendable {
        var count = 0
    }
}
