import AppKit
import ApplicationServices
import XCTest
@testable import AutocompleteHelper

final class RelatedFieldScanStateTests: XCTestCase {
    func testRefreshingTopologyDoesNotPublishATemporarilyMissingRecipient() {
        let recipient = RelatedEditableTopology(element: AXUIElementCreateSystemWide(), shape: .singleLine, label: "To", placeholder: nil)
        var state = RelatedFieldScanState(key: "field", expiresAt: 2,
            traversal: EditableNeighborhoodTraversal(seeds: []), editables: [recipient],
            totalVisits: 3, isComplete: true, foundSecureField: false)
        state.restartTraversal(seeds: [], at: 3)
        XCTAssertEqual(state.visibleEditables.count, 1, "A rescan is not evidence that the recipient disappeared")
        // An incomplete traversal still exposes the last completed topology.
        state.totalVisits = 1
        XCTAssertEqual(state.visibleEditables.first?.label, "To")
        // A completed scan proves removal and must publish it immediately.
        state.isComplete = true
        XCTAssertTrue(state.visibleEditables.isEmpty)
    }

    func testSecureFieldDiscoveryImmediatelySuppressesRetainedTopology() {
        let recipient = RelatedEditableTopology(element: AXUIElementCreateSystemWide(), shape: .singleLine, label: "To", placeholder: nil)
        var state = RelatedFieldScanState(key: "field", expiresAt: 2,
            traversal: EditableNeighborhoodTraversal(seeds: []), editables: [recipient],
            totalVisits: 3, isComplete: true, foundSecureField: false)
        state.restartTraversal(seeds: [], at: 3)
        state.foundSecureField = true
        XCTAssertTrue(state.visibleEditables.isEmpty)
    }
}
