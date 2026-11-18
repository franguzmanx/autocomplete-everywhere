import XCTest
@testable import AutocompleteHelper

final class SuggestionActivationTests: XCTestCase {
    func testFocusAloneDoesNotActivateAndClickMustHitInput() {
        var activation = SuggestionActivation()
        let field = snapshot()
        XCTAssertFalse(activation.allows(field, now: 0))
        activation.input(app: "app", point: CGPoint(x: 500, y: 500), now: 0)
        XCTAssertFalse(activation.allows(field, now: 0.1))
        activation.input(app: "app", point: CGPoint(x: 20, y: 20), now: 1)
        XCTAssertTrue(activation.allows(field, now: 1.1))
        XCTAssertTrue(activation.allows(field, now: 3))
        XCTAssertFalse(activation.allows(snapshot(focus: 2), now: 4))
        XCTAssertFalse(activation.allows(field, now: 5))
    }
    func testTypingAndObservedEditActivateButExpiredInputDoesNot() {
        var activation = SuggestionActivation()
        activation.input(app: "app", now: 0)
        XCTAssertFalse(activation.allows(snapshot(), now: 2))
        activation.input(app: "other", now: 2)
        XCTAssertFalse(activation.allows(snapshot(), now: 2.1))
        activation.input(app: "app", now: 3)
        XCTAssertTrue(activation.allows(snapshot(), now: 3.1))
        activation.observedEdit(snapshot(focus: 2))
        XCTAssertTrue(activation.allows(snapshot(focus: 2), now: 8))
    }
    private func snapshot(focus: UInt64 = 1) -> ActiveFieldSnapshot {
        .init(applicationBundleIdentifier: "app", elementIdentifier: "field", focusGeneration: focus,
              textBefore: "", selectedText: "", textAfter: "", selectionRange: NSRange(location: 0, length: 0),
              caretBounds: CGRect(x: 10, y: 10, width: 0, height: 18),
              inputFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
              geometryQuality: .exact, captureSequence: 1)
    }
}
