import XCTest
@testable import AutocompleteHelper

@MainActor
final class ContextArtifactSourceTests: XCTestCase {
    func testExactExpiryBoundaryAndClockRollbackDiscardCachedContext() {
        for end in [Int64(61_000), Int64(999)] {
            let source = ContextArtifactSource(clipboardChangeCount: { 0 }, clipboardText: { nil })
            source.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false))
            XCTAssertEqual(source.artifacts(selectedText: "selected", timestampMs: 1_000).count, 1)
            XCTAssertTrue(source.artifacts(selectedText: "", timestampMs: end).isEmpty)
        }
    }

    func testDoesNotReadClipboardWithoutExplicitOptIn() {
        var textReads = 0
        let source = ContextArtifactSource(
            clipboardChangeCount: { 7 },
            clipboardText: {
                textReads += 1
                return "private"
            }
        )

        XCTAssertEqual(source.artifacts(selectedText: "", timestampMs: 1_000), [])
        XCTAssertEqual(textReads, 0)
    }

    func testKeepsOnlyTheCurrentClipboardVersionUntilItsTTLExpires() {
        var changeCount = 7
        var clipboardText = "Hola Dana,\r\n\r\nTotal:\t€ 1.250 🚀"
        let source = ContextArtifactSource(
            clipboardChangeCount: { changeCount },
            clipboardText: { clipboardText }
        )
        source.updateConfiguration(
            .init(isEnabled: true, clipboardContextEnabled: true)
        )

        XCTAssertEqual(
            source.artifacts(selectedText: "", timestampMs: 1_000),
            [
                .init(
                    id: "clipboard-current",
                    kind: "clipboard",
                    text: clipboardText,
                    capturedAtMs: 1_000
                )
            ]
        )
        XCTAssertEqual(
            source.artifacts(selectedText: "", timestampMs: 600_999).count,
            1
        )
        XCTAssertEqual(
            source.artifacts(selectedText: "", timestampMs: 601_001),
            []
        )

        changeCount = 8
        clipboardText = "Nueva versión"
        XCTAssertEqual(
            source.artifacts(selectedText: "", timestampMs: 700_000),
            [
                .init(
                    id: "clipboard-current",
                    kind: "clipboard",
                    text: "Nueva versión",
                    capturedAtMs: 700_000
                )
            ]
        )
    }

    func testCarriesOneRecentSelectionAcrossFieldsAndThenForgetsIt() {
        let source = ContextArtifactSource(
            clipboardChangeCount: { 0 },
            clipboardText: { nil }
        )
        source.updateConfiguration(
            .init(isEnabled: true, clipboardContextEnabled: false)
        )

        XCTAssertEqual(
            source.artifacts(selectedText: "Exact selected text", timestampMs: 1_000),
            [
                .init(
                    id: "selection-recent",
                    kind: "selection",
                    text: "Exact selected text",
                    capturedAtMs: 1_000
                )
            ]
        )
        XCTAssertEqual(
            source.artifacts(selectedText: "", timestampMs: 60_999).count,
            1
        )
        XCTAssertEqual(
            source.artifacts(selectedText: "", timestampMs: 61_001),
            []
        )
    }
}
