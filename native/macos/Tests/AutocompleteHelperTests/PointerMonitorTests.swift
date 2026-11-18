import CoreGraphics
import XCTest
@testable import AutocompleteHelper

final class PointerMonitorTests: XCTestCase {
    @MainActor
    func testConsumesClickOnlyWhenDownLandsOnVisibleGlyphRegionAndAcceptanceSucceeds() {
        var acceptanceCount = 0
        let monitor = PointerMonitor(
            hitRegionsProvider: {
                [CGRect(x: 100, y: 200, width: 80, height: 20)]
            },
            acceptanceHandler: {
                acceptanceCount += 1
                return true
            }
        )

        XCTAssertFalse(
            monitor.process(
                PointerInput(location: CGPoint(x: 99, y: 210)),
                phase: .leftMouseDown
            )
        )
        XCTAssertFalse(
            monitor.process(
                PointerInput(location: CGPoint(x: 99, y: 210)),
                phase: .leftMouseUp
            )
        )
        XCTAssertTrue(
            monitor.process(
                PointerInput(location: CGPoint(x: 140, y: 210)),
                phase: .leftMouseDown
            )
        )
        XCTAssertTrue(
            monitor.process(
                PointerInput(location: CGPoint(x: 140, y: 210)),
                phase: .leftMouseUp
            )
        )
        XCTAssertEqual(acceptanceCount, 1)
    }

    @MainActor
    func testRejectedOrStaleAcceptancePassesClickThrough() {
        var stateChangeCount = 0
        let monitor = PointerMonitor(
            hitRegionsProvider: {
                [CGRect(x: 100, y: 200, width: 80, height: 20)]
            },
            acceptanceHandler: { false },
            stateChangeHandler: { stateChangeCount += 1 }
        )
        let hit = PointerInput(location: CGPoint(x: 140, y: 210))

        XCTAssertFalse(monitor.process(hit, phase: .leftMouseDown))
        XCTAssertFalse(monitor.process(hit, phase: .leftMouseUp))
        XCTAssertEqual(stateChangeCount, 1)
    }

    @MainActor
    func testClickOutsideGhostInvalidatesRetainedStateAndPassesThrough() {
        var stateChangeCount = 0
        let monitor = PointerMonitor(
            hitRegionsProvider: {
                [CGRect(x: 100, y: 200, width: 80, height: 20)]
            },
            acceptanceHandler: {
                XCTFail("Must not accept outside the ghost")
                return false
            },
            stateChangeHandler: { stateChangeCount += 1 }
        )

        XCTAssertFalse(
            monitor.process(
                PointerInput(location: CGPoint(x: 20, y: 20)),
                phase: .leftMouseDown
            )
        )
        XCTAssertFalse(
            monitor.process(
                PointerInput(location: CGPoint(x: 20, y: 20)),
                phase: .leftMouseUp
            )
        )
        XCTAssertEqual(stateChangeCount, 1)
    }

    @MainActor
    func testConsumedClickLatchPreventsDuplicateAcceptanceUntilMatchingMouseUp() {
        var acceptanceCount = 0
        var regions = [CGRect(x: 100, y: 200, width: 80, height: 20)]
        let monitor = PointerMonitor(
            hitRegionsProvider: { regions },
            acceptanceHandler: {
                acceptanceCount += 1
                regions = []
                return true
            }
        )
        let hit = PointerInput(location: CGPoint(x: 140, y: 210))

        XCTAssertTrue(monitor.process(hit, phase: .leftMouseDown))
        XCTAssertTrue(monitor.process(hit, phase: .leftMouseDown))
        XCTAssertTrue(monitor.process(hit, phase: .leftMouseUp))
        XCTAssertFalse(monitor.process(hit, phase: .leftMouseDown))
        XCTAssertFalse(monitor.process(hit, phase: .leftMouseUp))
        XCTAssertEqual(acceptanceCount, 1)
    }

    @MainActor
    func testEventTapUsesTheClickedEventLocationInsteadOfTheCurrentMousePosition() throws {
        let appKitClick = CGPoint(x: 140, y: 210)
        let quartzClick = CGPoint(x: appKitClick.x, y: 800 - appKitClick.y)
        let event = try XCTUnwrap(
            CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: quartzClick,
                mouseButton: .left
            )
        )
        var acceptanceCount = 0
        let monitor = PointerMonitor(
            hitRegionsProvider: {
                [CGRect(x: 100, y: 200, width: 80, height: 20)]
            },
            acceptanceHandler: {
                acceptanceCount += 1
                return true
            },
            displayGeometriesProvider: {
                [
                    DisplayGeometry(
                        accessibilityFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                        appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
                    ),
                ]
            }
        )

        XCTAssertTrue(monitor.handle(event, type: .leftMouseDown))
        XCTAssertEqual(acceptanceCount, 1)
    }
}
