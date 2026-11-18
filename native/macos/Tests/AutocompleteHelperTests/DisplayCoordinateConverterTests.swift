import Foundation
import XCTest
@testable import AutocompleteHelper

final class DisplayCoordinateConverterTests: XCTestCase {
    func testConvertsRectsOnDisplaysInAllQuadrants() {
        let displays = [
            DisplayGeometry(accessibilityFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            DisplayGeometry(accessibilityFrame: CGRect(x: -800, y: 0, width: 800, height: 600), appKitFrame: CGRect(x: -800, y: 200, width: 800, height: 600)),
            DisplayGeometry(accessibilityFrame: CGRect(x: 0, y: -600, width: 800, height: 600), appKitFrame: CGRect(x: 0, y: 800, width: 800, height: 600)),
            DisplayGeometry(accessibilityFrame: CGRect(x: 0, y: 800, width: 800, height: 600), appKitFrame: CGRect(x: 0, y: -600, width: 800, height: 600)),
        ]

        XCTAssertEqual(convert(CGRect(x: 100, y: 100, width: 2, height: 20), displays), CGRect(x: 100, y: 680, width: 2, height: 20))
        XCTAssertEqual(convert(CGRect(x: -700, y: 100, width: 2, height: 20), displays), CGRect(x: -700, y: 680, width: 2, height: 20))
        XCTAssertEqual(convert(CGRect(x: 100, y: -500, width: 2, height: 20), displays), CGRect(x: 100, y: 1280, width: 2, height: 20))
        XCTAssertEqual(convert(CGRect(x: 100, y: 900, width: 2, height: 20), displays), CGRect(x: 100, y: -120, width: 2, height: 20))
    }

    func testRetinaAccessibilityCoordinatesRemainLogicalAppKitPoints() {
        let displays = [
            DisplayGeometry(
                accessibilityFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
            ),
        ]

        XCTAssertEqual(
            convert(CGRect(x: 100, y: 200, width: 2, height: 20), displays),
            CGRect(x: 100, y: 762, width: 2, height: 20)
        )
    }

    func testConvertsPointerLocationsWithTheSameDisplayTransformAsCaretRects() {
        let displays = [
            DisplayGeometry(
                accessibilityFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
            ),
        ]

        XCTAssertEqual(
            DisplayCoordinateConverter.appKitPoint(
                fromAccessibilityPoint: CGPoint(x: 140, y: 590),
                displays: displays
            ),
            CGPoint(x: 140, y: 210)
        )
        XCTAssertNil(
            DisplayCoordinateConverter.appKitPoint(
                fromAccessibilityPoint: CGPoint(x: 1_500, y: 100),
                displays: displays
            )
        )
    }

    func testProductionAdapterKeepsRetinaScreenFramesInLogicalPoints() {
        let displays = SystemAccessibilityReader.displayGeometries(
            from: [
                AppKitScreenDescriptor(
                    frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                    backingScaleFactor: 2
                ),
            ]
        )

        XCTAssertEqual(
            displays,
            [
                DisplayGeometry(
                    accessibilityFrame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                    appKitFrame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                    backingScaleFactor: 2
                ),
            ]
        )
        XCTAssertEqual(
            convert(CGRect(x: 855, y: 556, width: 1, height: 20), displays),
            CGRect(x: 855, y: 536, width: 1, height: 20)
        )
    }

    func testRejectsRectOutsideEveryConcreteDisplay() {
        let displays = [
            DisplayGeometry(accessibilityFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
        ]

        XCTAssertNil(convert(CGRect(x: 1500, y: 100, width: 2, height: 20), displays))
        XCTAssertNil(convert(CGRect(x: 999, y: 100, width: 4, height: 20), displays))
        XCTAssertNil(convert(CGRect(x: 100, y: 100, width: -2, height: 20), displays))
    }

    private func convert(_ rect: CGRect, _ displays: [DisplayGeometry]) -> CGRect? {
        DisplayCoordinateConverter.appKitRect(fromAccessibilityRect: rect, displays: displays)
    }
}
