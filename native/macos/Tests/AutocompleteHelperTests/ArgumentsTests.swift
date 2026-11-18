import XCTest
@testable import AutocompleteHelper

final class ArgumentsTests: XCTestCase {
    func testReadsParentPID() {
        XCTAssertEqual(
            HelperArguments.parentPID(from: ["helper", "--parent-pid", "4242"]),
            4242
        )
    }

    func testRejectsMissingOrUnsafeParentPID() {
        XCTAssertNil(HelperArguments.parentPID(from: ["helper"]))
        XCTAssertNil(HelperArguments.parentPID(from: ["helper", "--parent-pid", "1"]))
        XCTAssertNil(HelperArguments.parentPID(from: ["helper", "--parent-pid", "not-a-pid"]))
    }
}
