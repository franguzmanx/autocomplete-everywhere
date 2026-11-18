import Foundation
import XCTest
@testable import AutocompleteHelper

final class CaretAnchorStabilizerTests: XCTestCase {
    func testRequiresTwoConcordantSamplesBeforeAcceptingAnchor() {
        var stabilizer = CaretAnchorStabilizer()
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 1)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 121, sequence: 2)), .accept)
    }

    func testDivergentPendingSampleMustBeConfirmedAgainBeforeAcceptance() {
        var stabilizer = CaretAnchorStabilizer()
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 1)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 900, sequence: 2)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 3)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 121, sequence: 4)), .accept)
    }

    func testInitialFarSampleIsReplacedBeforeTwoGoodSamplesAreAccepted() {
        var stabilizer = CaretAnchorStabilizer()

        XCTAssertEqual(stabilizer.observe(sample(x: 900, sequence: 1)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 2)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 121, sequence: 3)), .accept)
    }

    func testAlternatingPillCoordinatesNeverMoveVisibleAnchor() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 2)), .accept)
        XCTAssertEqual(stabilizer.observe(sample(x: 500, sequence: 3)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 4)), .hold)
    }

    func testTwoConsecutiveDiscordantSamplesHideFrozenVisibleAnchor() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 2)), .accept)

        XCTAssertEqual(stabilizer.observe(sample(x: 300, sequence: 3)), .hold)
        XCTAssertEqual(stabilizer.observe(sample(x: 500, sequence: 4)), .hide)
        XCTAssertFalse(stabilizer.isResolved)
        XCTAssertEqual(stabilizer.observe(sample(x: 501, sequence: 5)), .accept)
    }

    func testVisibleAnchorMovesOnlyAfterTwoConcordantNewSamples() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 2)), .accept)
        XCTAssertTrue(stabilizer.isResolved)

        XCTAssertEqual(stabilizer.observe(sample(x: 220, sequence: 3)), .hold)
        XCTAssertFalse(stabilizer.isResolved)
        XCTAssertEqual(stabilizer.observe(sample(x: 221, sequence: 4)), .accept)
        XCTAssertTrue(stabilizer.isResolved)
    }

    func testChangedIdentityHidesAndSeedsReacquisition() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        _ = stabilizer.observe(sample(x: 120, sequence: 2))

        XCTAssertEqual(
            stabilizer.observe(sample(x: 220, sequence: 3, field: "other")),
            .hide
        )
        XCTAssertEqual(
            stabilizer.observe(sample(x: 221, sequence: 4, field: "other")),
            .accept
        )
    }

    func testChangedContentHidesAndSeedsReacquisition() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        _ = stabilizer.observe(sample(x: 120, sequence: 2))

        XCTAssertEqual(
            stabilizer.observe(sample(x: 130, sequence: 3, content: "changed")),
            .hide
        )
        XCTAssertEqual(
            stabilizer.observe(sample(x: 131, sequence: 4, content: "changed")),
            .accept
        )
    }

    func testStaleSequenceAndChangedIdentityHide() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 2))
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 1)), .hide)
        stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 2))
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 3, field: "other")), .hide)
    }

    func testExpectedSampleStandsInForTheFirstConcordantSample() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 2)), .accept)

        stabilizer.expect(sample(x: 129, sequence: 2, content: "typed"))
        XCTAssertFalse(stabilizer.isResolved)
        XCTAssertEqual(
            stabilizer.observe(sample(x: 128.5, sequence: 3, content: "typed")),
            .accept
        )
        XCTAssertTrue(stabilizer.isResolved)
    }

    func testExpectedSampleContradictedByTheHostHides() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        _ = stabilizer.observe(sample(x: 120, sequence: 2))

        stabilizer.expect(sample(x: 129, sequence: 2, content: "typed"))
        XCTAssertEqual(
            stabilizer.observe(sample(x: 48, sequence: 3, content: "typed")),
            .hide
        )
        XCTAssertEqual(
            stabilizer.observe(sample(x: 48.5, sequence: 4, content: "typed")),
            .accept
        )
    }

    func testExpectedSampleWithUnchangedHostContentHides() {
        var stabilizer = CaretAnchorStabilizer()
        _ = stabilizer.observe(sample(x: 120, sequence: 1))
        _ = stabilizer.observe(sample(x: 120, sequence: 2))

        stabilizer.expect(sample(x: 129, sequence: 2, content: "typed"))
        XCTAssertEqual(stabilizer.observe(sample(x: 120, sequence: 3)), .hide)
    }

    private func sample(
        x: CGFloat,
        sequence: UInt64,
        field: String = "notes",
        content: String = "content"
    ) -> CaretAnchorSample {
        CaretAnchorSample(
            fieldIdentity: field,
            contentIdentity: content,
            captureSequence: sequence,
            rect: CGRect(x: x, y: 100, width: 0, height: 18)
        )
    }
}
