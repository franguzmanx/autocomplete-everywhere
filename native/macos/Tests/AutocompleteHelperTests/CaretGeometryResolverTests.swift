import Foundation
import XCTest
@testable import AutocompleteHelper

final class CaretGeometryResolverTests: XCTestCase {
    private let field = CGRect(x: 40, y: 60, width: 360, height: 240)
    private let displays = [
        DisplayGeometry(
            accessibilityFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        ),
    ]

    func testAcceptsPlausibleZeroLengthCandidate() {
        let result = resolve([
            .init(rect: CGRect(x: 120, y: 100, width: 0, height: 18), source: .zeroLengthRange),
        ])

        XCTAssertEqual(result?.source, .zeroLengthRange)
        XCTAssertEqual(result?.quality, .exact)
        XCTAssertEqual(result?.rect, CGRect(x: 120, y: 864, width: 0, height: 18))
    }

    func testRejectsFiniteZeroLengthCandidateOutsideField() {
        XCTAssertNil(resolve([
            .init(rect: CGRect(x: 900, y: 700, width: 0, height: 18), source: .zeroLengthRange),
        ]))
    }

    func testRejectsCandidateThatOnlyPartiallyFitsFieldTolerance() {
        XCTAssertNil(resolve([
            .init(rect: CGRect(x: 399, y: 100, width: 10, height: 18), source: .precedingGrapheme),
        ]))
    }

    func testAcceptsPartiallyClippedFollowingGlyphWhenItsCaretEdgeIsInside() {
        let result = resolve([
            .init(
                rect: CGRect(x: 399, y: 100, width: 10, height: 18),
                source: .followingGrapheme
            ),
        ])

        XCTAssertEqual(result?.source, .followingGrapheme)
        XCTAssertEqual(result?.rect.minX, 399)
    }

    func testRejectsWideRangeMasqueradingAsAZeroLengthCaret() {
        XCTAssertNil(resolve([
            .init(
                rect: CGRect(x: 100, y: 100, width: 120, height: 18),
                source: .zeroLengthRange
            ),
        ]))
    }

    func testUsesCompletePrecedingGraphemeCaretCandidate() {
        let rect = CGRect(x: 136, y: 100, width: 8, height: 18)
        let result = resolve([
            .init(rect: rect, source: .precedingGrapheme),
        ])

        XCTAssertEqual(result?.source, .precedingGrapheme)
        XCTAssertEqual(result?.rect, CGRect(x: 144, y: 864, width: 0, height: 18))
    }

    func testUsesFollowingGraphemeAtParagraphStart() {
        let result = resolve([
            .init(rect: CGRect(x: 48, y: 100, width: 8, height: 18), source: .followingGrapheme),
        ])

        XCTAssertEqual(result?.source, .followingGrapheme)
    }

    func testRejectsSpatiallyConflictingCandidates() {
        XCTAssertNil(resolve([
            .init(rect: CGRect(x: 120, y: 100, width: 0, height: 18), source: .zeroLengthRange),
            .init(rect: CGRect(x: 118, y: 180, width: 2, height: 18), source: .precedingGrapheme),
        ]))
    }

    func testCollapsedEndPrefersPrecedingGlyphOverStaleSameLineZeroRange() {
        let cases: [(direction: CaretWritingDirection, glyph: CGRect, expectedX: CGFloat)] = [
            (.leftToRight, CGRect(x: 112, y: 100, width: 8, height: 18), 120),
            (.rightToLeft, CGRect(x: 112, y: 100, width: 8, height: 18), 112),
        ]

        for item in cases {
            let result = resolve(
                [
                    .init(
                        rect: CGRect(x: 220, y: 100, width: 0, height: 18),
                        source: .zeroLengthRange
                    ),
                    .init(rect: item.glyph, source: .precedingGrapheme),
                ],
                direction: item.direction,
                selectionContext: .collapsedAtTextEnd
            )

            XCTAssertEqual(result?.source, .precedingGrapheme)
            XCTAssertEqual(result?.quality, .derived)
            XCTAssertEqual(result?.rect.minX, item.expectedX)
        }
    }

    func testCollapsedEndUsesPrecedingGraphemeAcrossVerticalZeroRangeConflicts() {
        let cases: [(
            direction: CaretWritingDirection,
            exactX: CGFloat,
            exactY: CGFloat,
            preceding: CGRect,
            expectedX: CGFloat
        )] = [
            (.leftToRight, 48, 118, CGRect(x: 380, y: 100, width: 8, height: 18), 388),
            (.rightToLeft, 392, 118, CGRect(x: 44, y: 100, width: 8, height: 18), 44),
            (.leftToRight, 180, 220, CGRect(x: 200, y: 100, width: 8, height: 18), 208),
            (.leftToRight, 48, 82, CGRect(x: 380, y: 100, width: 8, height: 18), 388),
        ]

        for item in cases {
            let result = resolve(
                [
                    .init(
                        rect: CGRect(x: item.exactX, y: item.exactY, width: 0, height: 18),
                        source: .zeroLengthRange
                    ),
                    .init(rect: item.preceding, source: .precedingGrapheme),
                ],
                direction: item.direction,
                selectionContext: .collapsedAtTextEnd
            )

            XCTAssertEqual(result?.source, .precedingGrapheme)
            XCTAssertEqual(result?.quality, .derived)
            XCTAssertEqual(result?.rect.minX, item.expectedX)
        }
    }

    func testCollapsedEndDoesNotPreferPrecedingWithMixedCandidates() {
        let mixed = resolve(
            [
                .init(
                    rect: CGRect(x: 220, y: 100, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
                .init(
                    rect: CGRect(x: 112, y: 100, width: 8, height: 18),
                    source: .precedingGrapheme
                ),
                .init(
                    rect: CGRect(x: 220, y: 100, width: 8, height: 18),
                    source: .followingGrapheme
                ),
            ],
            selectionContext: .collapsedAtTextEnd
        )
        XCTAssertNil(mixed)
    }

    func testCollapsedEndPreferenceNeverBypassesDisplayContainment() {
        let offDisplay = resolve(
            [
                .init(
                    rect: CGRect(x: 120, y: 100, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
                .init(
                    rect: CGRect(x: 140, y: 100, width: 8, height: 18),
                    source: .precedingGrapheme
                ),
            ],
            selectionContext: .collapsedAtTextEnd,
            displays: [
                DisplayGeometry(
                    accessibilityFrame: CGRect(x: 0, y: 0, width: 130, height: 982),
                    appKitFrame: CGRect(x: 0, y: 0, width: 130, height: 982)
                ),
            ]
        )
        XCTAssertEqual(offDisplay?.source, .zeroLengthRange)
        XCTAssertEqual(offDisplay?.rect.minX, 120)
    }

    func testCollapsedMiddleUsesConcordantAdjacentEdgesOverStaleZeroRange() {
        let cases: [(
            direction: CaretWritingDirection,
            preceding: CGRect,
            following: CGRect,
            expectedX: CGFloat
        )] = [
            (
                .leftToRight,
                CGRect(x: 100, y: 100, width: 10, height: 18),
                CGRect(x: 110, y: 100, width: 10, height: 18),
                110
            ),
            (
                .rightToLeft,
                CGRect(x: 120, y: 100, width: 14, height: 18),
                CGRect(x: 106, y: 100, width: 14, height: 18),
                120
            ),
        ]

        for item in cases {
            let result = resolve(
                [
                    .init(
                        rect: CGRect(x: 220, y: 100, width: 0, height: 18),
                        source: .zeroLengthRange
                    ),
                    .init(rect: item.preceding, source: .precedingGrapheme),
                    .init(rect: item.following, source: .followingGrapheme),
                ],
                direction: item.direction,
                selectionContext: .collapsedInText
            )

            XCTAssertEqual(result?.source, .precedingGrapheme)
            XCTAssertEqual(result?.quality, .derived)
            XCTAssertEqual(result?.rect.minX, item.expectedX)
        }
    }

    func testCollapsedMiddlePreservesExactWhenAllCandidatesAgree() {
        let result = resolve(
            [
                .init(
                    rect: CGRect(x: 110, y: 100, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
                .init(
                    rect: CGRect(x: 100, y: 100, width: 10, height: 18),
                    source: .precedingGrapheme
                ),
                .init(
                    rect: CGRect(x: 110, y: 100, width: 10, height: 18),
                    source: .followingGrapheme
                ),
            ],
            selectionContext: .collapsedInText
        )

        XCTAssertEqual(result?.source, .zeroLengthRange)
        XCTAssertEqual(result?.quality, .exact)
        XCTAssertEqual(result?.rect.minX, 110)
    }

    func testCollapsedMiddleRejectsAdjacentEdgesAcrossSoftWrap() {
        let crossLine = resolve(
            [
                .init(
                    rect: CGRect(x: 48, y: 118, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
                .init(
                    rect: CGRect(x: 380, y: 100, width: 8, height: 18),
                    source: .precedingGrapheme
                ),
                .init(
                    rect: CGRect(x: 48, y: 118, width: 8, height: 18),
                    source: .followingGrapheme
                ),
            ],
            selectionContext: .collapsedInText
        )
        XCTAssertNil(crossLine)
    }

    func testCollapsedMiddleRejectsAdjacentEdgesAtBidiBoundary() {
        let bidiBoundary = resolve(
            [
                .init(
                    rect: CGRect(x: 140, y: 100, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
                .init(
                    rect: CGRect(x: 100, y: 100, width: 20, height: 18),
                    source: .precedingGrapheme
                ),
                .init(
                    rect: CGRect(x: 140, y: 100, width: 20, height: 18),
                    source: .followingGrapheme
                ),
            ],
            selectionContext: .collapsedInText
        )
        XCTAssertNil(bidiBoundary)
    }

    func testCollapsedMiddleConsensusRequiresBothEdgesOnDisplay() {
        let result = resolve(
            [
                .init(
                    rect: CGRect(x: 120, y: 100, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
                .init(
                    rect: CGRect(x: 100, y: 100, width: 10, height: 18),
                    source: .precedingGrapheme
                ),
                .init(
                    rect: CGRect(x: 110, y: 100, width: 30, height: 18),
                    source: .followingGrapheme
                ),
            ],
            selectionContext: .collapsedInText,
            displays: [
                DisplayGeometry(
                    accessibilityFrame: CGRect(x: 0, y: 0, width: 130, height: 982),
                    appKitFrame: CGRect(x: 0, y: 0, width: 130, height: 982)
                ),
            ]
        )

        XCTAssertNil(result)
    }

    func testDerivesFullGlyphEdgesFromActualUnicodeGraphemeRanges() {
        let cases: [(text: String, firstUTF16: Int, lastUTF16: Int, direction: CaretWritingDirection, precedingX: CGFloat, followingX: CGFloat)] = [
            ("👋🏽", 4, 4, .leftToRight, 152, 140),
            ("café", 1, 1, .leftToRight, 149, 140),
            ("日本語", 1, 1, .leftToRight, 149, 140),
            ("العربية", 1, 1, .rightToLeft, 140, 149),
            ("עברית", 1, 1, .rightToLeft, 140, 149),
        ]

        for item in cases {
            let firstEnd = item.text.index(after: item.text.startIndex)
            let firstRange = NSRange(item.text.startIndex..<firstEnd, in: item.text)
            let lastStart = item.text.index(before: item.text.endIndex)
            let lastRange = NSRange(lastStart..<item.text.endIndex, in: item.text)
            XCTAssertEqual(firstRange, NSRange(location: 0, length: item.firstUTF16), item.text)
            XCTAssertEqual(
                lastRange,
                NSRange(
                    location: item.text.utf16.count - item.lastUTF16,
                    length: item.lastUTF16
                ),
                item.text
            )

            let precedingGlyph = CGRect(
                x: 140,
                y: 120,
                width: CGFloat(8 + lastRange.length),
                height: 20
            )
            let followingGlyph = CGRect(
                x: 140,
                y: 120,
                width: CGFloat(8 + firstRange.length),
                height: 20
            )
            let preceding = resolve(
                [.init(rect: precedingGlyph, source: .precedingGrapheme)],
                direction: item.direction
            )
            let following = resolve(
                [.init(rect: followingGlyph, source: .followingGrapheme)],
                direction: item.direction
            )
            XCTAssertEqual(preceding?.rect.minX, item.precedingX, item.text)
            XCTAssertEqual(following?.rect.minX, item.followingX, item.text)
        }
    }

    func testRejectsImplausibleLineHeightAndMissingGeometry() {
        XCTAssertNil(resolve([]))
        XCTAssertNil(resolve([
            .init(rect: CGRect(x: 120, y: 100, width: 0, height: 44), source: .zeroLengthRange),
        ], lineHeight: 18))
    }

    func testEvaluationExplainsClosedFailureReasonsWithoutCoordinates() {
        let missing = evaluate([])
        XCTAssertNil(missing.geometry)
        XCTAssertFalse(missing.displayMatched)
        XCTAssertEqual(missing.outcome, .failed(.noCandidates))

        let outside = evaluate([
            .init(
                rect: CGRect(x: 900, y: 700, width: 0, height: 18),
                source: .zeroLengthRange
            ),
        ])
        XCTAssertNil(outside.geometry)
        XCTAssertTrue(outside.displayMatched)
        XCTAssertEqual(outside.outcome, .failed(.outsideInputFrame))

        let conflicting = evaluate([
            .init(
                rect: CGRect(x: 120, y: 100, width: 0, height: 18),
                source: .zeroLengthRange
            ),
            .init(
                rect: CGRect(x: 180, y: 100, width: 8, height: 18),
                source: .precedingGrapheme
            ),
        ])
        XCTAssertNil(conflicting.geometry)
        XCTAssertTrue(conflicting.displayMatched)
        XCTAssertEqual(conflicting.outcome, .failed(.conflictingCandidates))
    }

    private func resolve(
        _ candidates: [CaretGeometryCandidate],
        lineHeight: CGFloat = 18,
        direction: CaretWritingDirection = .leftToRight,
        selectionContext: CaretSelectionContext = .other,
        displays: [DisplayGeometry]? = nil
    ) -> ResolvedCaretGeometry? {
        CaretGeometryResolver.resolve(
            .init(
                candidates: candidates,
                inputFrame: field,
                measuredLineHeight: lineHeight,
                writingDirection: direction,
                displays: displays ?? self.displays,
                selectionContext: selectionContext
            )
        )
    }

    private func evaluate(
        _ candidates: [CaretGeometryCandidate],
        lineHeight: CGFloat = 18,
        direction: CaretWritingDirection = .leftToRight
    ) -> CaretGeometryEvaluation {
        CaretGeometryResolver.evaluate(
            .init(
                candidates: candidates,
                inputFrame: field,
                measuredLineHeight: lineHeight,
                writingDirection: direction,
                displays: displays,
                selectionContext: .other
            )
        )
    }
}
