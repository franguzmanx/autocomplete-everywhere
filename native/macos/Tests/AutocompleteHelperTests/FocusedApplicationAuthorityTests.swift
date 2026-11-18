import ApplicationServices
import XCTest
@testable import AutocompleteHelper

final class FocusedApplicationAuthorityTests: XCTestCase {
    func testSystemAXFocusWinsOverStaleWorkspaceParentMetadata() {
        var diagnostics: [(Int32?, Int32?)] = []
        let reader = SystemAccessibilityReader(
            excludedProcessIdentifier: 4_242,
            focusedApplicationProvider: { AXUIElementCreateApplication(7_777) },
            workspaceProcessProvider: { 4_242 },
            focusDiagnostic: { diagnostics.append(($0, $1)) }
        )
        XCTAssertEqual(reader.frontmostProcessIdentifier(), 7_777)
        XCTAssertEqual(reader.frontmostProcessIdentifier(), 7_777)
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.0, 7_777)
        XCTAssertEqual(diagnostics.first?.1, 4_242)
    }

    func testMissingAXFocusDoesNotFallBackToWorkspaceMetadata() {
        let reader = SystemAccessibilityReader(focusedApplicationProvider: { nil }, workspaceProcessProvider: { 7_777 })
        XCTAssertNil(reader.frontmostProcessIdentifier())
        XCTAssertNil(reader.frontmostApplicationBundleIdentifier())
    }

    func testRealAXParentIsStillIdentifiedForEarlyExclusion() {
        let reader = SystemAccessibilityReader(excludedProcessIdentifier: 4_242, focusedApplicationProvider: { AXUIElementCreateApplication(4_242) }, workspaceProcessProvider: { 7_777 })
        XCTAssertEqual(reader.frontmostProcessIdentifier(), 4_242)
        XCTAssertNil(reader.focusedElement())
    }
}
