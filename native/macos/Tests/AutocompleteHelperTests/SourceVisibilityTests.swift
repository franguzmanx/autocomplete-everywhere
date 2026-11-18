import XCTest
@testable import AutocompleteHelper

final class SourceVisibilityTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    private let window = SourceVisibility.Ancestor(frame: CGRect(x: 0, y: 0, width: 800, height: 800), clips: true, hidden: false, isWindow: true)

    func testNestedWebMessageCanReachItsWindowThroughHostAndDocumentContainers() {
        // Electron contributes host containers in addition to the page's DOM.
        // A fully visible message must not disappear at an arbitrary depth of 12.
        let containers = Array(repeating: SourceVisibility.Ancestor(frame: nil, clips: false, hidden: false, isWindow: false), count: 15)
        let visible = SourceVisibility.readText(frame: CGRect(x: 10, y: 240, width: 100, height: 30), displays: [display], ancestors: containers + [window]) { "Current message" }
        XCTAssertEqual(visible, "Current message")
    }

    func testAncestryRemainsBoundedBeforeAnyTextRead() {
        let container = SourceVisibility.Ancestor(frame: nil, clips: false, hidden: false, isWindow: false)
        var reads = 0
        XCTAssertNil(SourceVisibility.readText(frame: CGRect(x: 10, y: 240, width: 100, height: 30), displays: [display], ancestors: Array(repeating: container, count: 32) + [window]) { reads += 1; return "Never read" })
        XCTAssertEqual(reads, 0)
    }

    func testScrolledOutTextIsNeverReadEvenWhenInsideTheDisplay() {
        let viewport = SourceVisibility.Ancestor(frame: CGRect(x: 0, y: 200, width: 500, height: 300), clips: true, hidden: false, isWindow: false)
        var reads = 0
        let hidden = SourceVisibility.readText(frame: CGRect(x: 10, y: 100, width: 100, height: 30), displays: [display], ancestors: [viewport, window]) { reads += 1; return "Old message" }
        XCTAssertNil(hidden)
        XCTAssertEqual(reads, 0)
        let visible = SourceVisibility.readText(frame: CGRect(x: 10, y: 240, width: 100, height: 30), displays: [display], ancestors: [viewport, window]) { reads += 1; return "Current message" }
        XCTAssertEqual(visible, "Current message")
        XCTAssertEqual(reads, 1)
    }

    func testPartlyClippedStaticValueIsNotReadAsFullyVisibleText() {
        let viewport = SourceVisibility.Ancestor(frame: CGRect(x: 0, y: 200, width: 500, height: 300), clips: true, hidden: false, isWindow: false)
        var reads = 0
        XCTAssertNil(SourceVisibility.readText(frame: CGRect(x: 10, y: 190, width: 100, height: 30), displays: [display], ancestors: [viewport, window]) { reads += 1; return "Includes hidden words" })
        XCTAssertEqual(reads, 0)
    }

    func testUnknownClippingGeometryOrMissingWindowFailsBeforeTextRead() {
        for ancestors in [[SourceVisibility.Ancestor(frame: nil, clips: true, hidden: false, isWindow: false), window], []] {
            var reads = 0
            XCTAssertNil(SourceVisibility.readText(frame: CGRect(x: 10, y: 240, width: 100, height: 30), displays: [display], ancestors: ancestors) { reads += 1; return "Never read" })
            XCTAssertEqual(reads, 0)
        }
    }

    func testSixEmptyOrOffscreenNodesDoNotSpendTheSourceBudget() {
        var reads = 0
        let selected = ReadOnlySourceTraversal.collect(roots: Array(0..<20), maximumSources: 6, shouldContinue: { true }) { index in
            let frame = index < 3 ? CGRect(x: 1100, y: 100, width: 100, height: 30) : CGRect(x: 10, y: 240, width: 100, height: 30)
            let text = SourceVisibility.readText(frame: frame, displays: [self.display], ancestors: [self.window]) { reads += 1; return index < 6 ? "  " : "Message" }
            return text == nil ? .prune : .source
        }
        XCTAssertEqual(selected, [6, 7, 8, 9, 10, 11])
        XCTAssertEqual(reads, 9)
    }

    func testNearestInadmissibleRingDoesNotHideOuterReadableSource() {
        let selected = ReadOnlySourceTraversal.collectNearest(maximumSources: 6, shouldContinue: { true }, rootsForRing: { ring in ring == 0 ? ["empty"] : ring == 1 ? ["message"] : nil }) { node in
            node == "empty" ? .prune : .source
        }
        XCTAssertEqual(selected, ["message"])
    }
    func testFullyVisibleMessageDoesNotQueryAnExcerpt() {
        XCTAssertEqual(SourceVisibility.readText(
            frame: CGRect(x: 10, y: 240, width: 100, height: 30), displays: [display], ancestors: [window],
            readExcerpt: { XCTFail("Full visibility needs no extra AX queries"); return nil },
            read: { "Current message" }
        ), "Current message")
    }

    func testHiddenAncestorPreventsEvenExcerptDiscovery() {
        let hidden = SourceVisibility.Ancestor(frame: nil, clips: false, hidden: true, isWindow: false)
        XCTAssertNil(SourceVisibility.readText(
            frame: CGRect(x: 10, y: 240, width: 100, height: 30), displays: [display], ancestors: [hidden, window],
            readExcerpt: { XCTFail("Hidden sources must not be queried"); return nil },
            read: { XCTFail("Hidden sources must not be read"); return nil }
        ))
    }

    func testPartlyClippedMessageUsesOnlyMeasuredVisibleExcerpt() {
        let viewport = SourceVisibility.Ancestor(frame: CGRect(x: 0, y: 200, width: 500, height: 300), clips: true, hidden: false, isWindow: false)
        var fullReads = 0
        var excerptReads = 0
        let result = SourceVisibility.readText(
            frame: CGRect(x: 10, y: 100, width: 400, height: 600),
            displays: [display], ancestors: [viewport, window],
            readExcerpt: { .init(frame: CGRect(x: 10, y: 220, width: 300, height: 100), read: { excerptReads += 1; return "Visible final question" }) },
            read: { fullReads += 1; return "Offscreen history plus question" }
        )
        XCTAssertEqual(result, "Visible final question")
        XCTAssertEqual(fullReads, 0)
        XCTAssertEqual(excerptReads, 1)
    }

    func testExcerptOutsideViewportIsRejectedBeforeReadingItsText() {
        let viewport = SourceVisibility.Ancestor(frame: CGRect(x: 0, y: 200, width: 500, height: 300), clips: true, hidden: false, isWindow: false)
        var reads = 0
        XCTAssertNil(SourceVisibility.readText(
            frame: CGRect(x: 10, y: 100, width: 400, height: 600), displays: [display], ancestors: [viewport, window],
            readExcerpt: { .init(frame: CGRect(x: 10, y: 190, width: 300, height: 100), read: { reads += 1; return "Contains hidden text" }) },
            read: { XCTFail("Must not read full value"); return nil }
        ))
        XCTAssertEqual(reads, 0)
    }

}
