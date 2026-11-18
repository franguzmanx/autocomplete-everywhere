import Foundation
import XCTest
@testable import AutocompleteHelper

final class SuggestionCooldownTests: XCTestCase {
    private let target = SuggestionCooldown.Target(appId: "app", elementId: "field", focusGeneration: 1)

    func testTimeAloneAndUnattributedChangesCannotResume() {
        var cooldown = SuggestionCooldown()
        cooldown.dismiss(target: target, at: 10)
        XCTAssertTrue(cooldown.isBlocked(at: 100))
        XCTAssertNil(cooldown.observeDraftEdit(target: target, at: 100))
        XCTAssertTrue(cooldown.isBlocked(at: 100))
        cooldown.noteUserEdit(at: 100)
        XCTAssertTrue(cooldown.isBlocked(at: 100), "A key opportunity without a changed draft is not an edit")
        XCTAssertEqual(cooldown.observeDraftEdit(target: target, at: 100.1), 0)
        XCTAssertFalse(cooldown.isBlocked(at: 100.1))
    }

    func testAuthoredEditStillWaitsOneSecondAndSchedulesOnlyOnce() {
        var cooldown = SuggestionCooldown()
        cooldown.dismiss(target: target, at: 10)
        cooldown.noteUserEdit(at: 10.25)
        XCTAssertEqual(cooldown.observeDraftEdit(target: target, at: 10.25), 0.75)
        cooldown.noteUserEdit(at: 10.5)
        XCTAssertNil(cooldown.observeDraftEdit(target: target, at: 10.5))
        XCTAssertTrue(cooldown.isBlocked(at: 10.999))
        XCTAssertFalse(cooldown.isBlocked(at: 11))
    }

    func testRepeatedDismissalWithinMinuteRequiresNewEditAndThreeSeconds() {
        var cooldown = SuggestionCooldown()
        cooldown.dismiss(target: target, at: 10)
        cooldown.noteUserEdit(at: 11)
        _ = cooldown.observeDraftEdit(target: target, at: 11)
        cooldown.dismiss(target: target, at: 20)
        XCTAssertTrue(cooldown.isBlocked(at: 100))
        cooldown.noteUserEdit(at: 21)
        XCTAssertEqual(cooldown.observeDraftEdit(target: target, at: 21), 2)
        XCTAssertTrue(cooldown.isBlocked(at: 22.999))
        XCTAssertFalse(cooldown.isBlocked(at: 23))
        cooldown.dismiss(target: target, at: 81)
        cooldown.noteUserEdit(at: 82)
        XCTAssertEqual(cooldown.observeDraftEdit(target: target, at: 82), 0)
    }

    func testAcceptanceAndChangedTargetResetEscalation() {
        var cooldown = SuggestionCooldown()
        cooldown.dismiss(target: target, at: 10)
        cooldown.reset()
        XCTAssertFalse(cooldown.isBlocked(at: 11))
        cooldown.dismiss(target: target, at: 12)
        cooldown.noteUserEdit(at: 13)
        XCTAssertEqual(cooldown.observeDraftEdit(target: target, at: 13), 0)
        let other = SuggestionCooldown.Target(appId: "app", elementId: "field", focusGeneration: 2)
        cooldown.observeTarget(other)
        XCTAssertFalse(cooldown.isBlocked(at: 13))
        cooldown.dismiss(target: target, at: 14)
        cooldown.noteUserEdit(at: 15)
        XCTAssertEqual(cooldown.observeDraftEdit(target: target, at: 15), 0)
    }

    func testExpiredEditOpportunityDoesNotAttributeLaterChange() {
        var cooldown = SuggestionCooldown()
        cooldown.dismiss(target: target, at: 10)
        cooldown.noteUserEdit(at: 11)
        XCTAssertNil(cooldown.observeDraftEdit(target: target, at: 12.01))
        XCTAssertTrue(cooldown.isBlocked(at: 20))
    }
}
