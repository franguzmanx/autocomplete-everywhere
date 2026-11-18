import AppKit
import Foundation
import XCTest
@testable import AutocompleteHelper

final class GhostTextPresenterTests: XCTestCase {
    @MainActor
    func testReportsRenderedFontInsteadOfOnlyCaptureAvailability() throws {
        for height: CGFloat in [25, 44, 53, 68] {
            var measurements: [GhostTypographyMeasurement] = []
            let display = RecordingGhostTextDisplay()
            let presenter = GhostTextPresenter(display: display, displayGeometries: { [Self.display] },
                typographyDiagnostic: { _, value in measurements.append(value) })
            let snapshot = Self.snapshot(caretBounds: CGRect(x: 80, y: 200, width: 0, height: height),
                textBefore: "", textAfter: "", inputFrame: CGRect(x: 40, y: 100, width: 320, height: 220),
                textStyle: nil, paragraphMetrics: nil, paragraphMetricsFailureReason: .empty, fieldKind: .singleLine)
            XCTAssertFalse(presenter.present(identity: Self.identity(snapshot: snapshot), text: "Example", snapshot: snapshot))
            XCTAssertTrue(measurements.isEmpty)
            XCTAssertTrue(display.presentations.isEmpty)
        }
    }

    @MainActor
    func testConfiguredGhostVisibilityChangesResolvedColor() {
        defer { GhostTextColor.opacity = 0.30 }
        GhostTextColor.opacity = 0.45
        XCTAssertEqual(GhostTextColor.resolve(for: nil).alphaComponent, 0.45, accuracy: 0.001)
    }

    func testPrivateAppleAccessibilityFontResolvesToSystemFontAtTheSameSize() {
        let font = GhostTextTypography.font(
            for: ActiveFieldTextStyle(
                fontName: ".WebKitUnresolvableSystemAlias",
                fontSize: 17
            )
        )

        XCTAssertEqual(font?.fontName, NSFont.systemFont(ofSize: 17).fontName)
        XCTAssertEqual(font?.pointSize, 17)
        XCTAssertEqual(
            GhostTextTypography.resolution(
                for: .init(fontName: ".WebKitUnresolvableSystemAlias", fontSize: 17)
            ),
            .systemFallback
        )
    }

    func testUnknownCustomFontStillFailsClosed() {
        XCTAssertNil(
            GhostTextTypography.font(
                for: ActiveFieldTextStyle(
                    fontName: "DefinitelyMissingCustomFont",
                    fontSize: 17
                )
            )
        )
        XCTAssertEqual(
            GhostTextTypography.resolution(
                for: .init(fontName: "DefinitelyMissingCustomFont", fontSize: 17)
            ),
            .unavailable
        )
    }

    @MainActor
    func testPresentsInlineGhostTextInTextEdit() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            applicationBundleIdentifier: "com.apple.TextEdit"
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.presentations.count, 1)
    }

    @MainActor
    func testSingleLinePresentationFollowsTheHostTextColor() throws {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            surface: .web,
            textStyle: ActiveFieldTextStyle(
                fontName: ".AppleSystemUIFont",
                fontSize: 13,
                foregroundColor: ActiveFieldTextColor(
                    red: 0.13,
                    green: 0.24,
                    blue: 0.35,
                    alpha: 1
                )
            )
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        let color = try XCTUnwrap(
            try XCTUnwrap(display.presentations.first).foregroundColor.usingColorSpace(.sRGB)
        )
        XCTAssertEqual(color.redComponent, 0.13, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0.24, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0.35, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 0.30, accuracy: 0.001)
    }

    @MainActor
    func testPresentsInlineGhostTextInSafariTextarea() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari"
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.presentations.count, 1)
    }

    @MainActor
    func testPresentsInlineGhostTextInChromeField() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            applicationBundleIdentifier: "com.google.Chrome"
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.presentations.count, 1)
    }

    @MainActor
    func testMaskedEmptyCodexComposerUsesMeasuredSingleLineTypography() throws {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            applicationBundleIdentifier: "com.openai.codex",
            surface: .web,
            caretBounds: CGRect(x: 80, y: 100, width: 0, height: 18),
            textBefore: "",
            inputFrame: CGRect(x: 40, y: 80, width: 320, height: 58),
            textStyle: .init(fontName: ".AppleSystemUIFont", fontSize: 14),
            paragraphMetrics: nil,
            fieldKind: .multiline,
            masksHostPlaceholder: true,
            hostPlaceholderBounds: CGRect(x: 80, y: 100, width: 72, height: 18)
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: "A useful next action",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.presentations.count, 1)
        XCTAssertTrue(display.paragraphPresentations.isEmpty)
        XCTAssertEqual(try XCTUnwrap(display.presentations.first).font.pointSize, 14)
        XCTAssertTrue(try XCTUnwrap(display.presentations.first).masksHostPlaceholder)
        XCTAssertEqual(
            try XCTUnwrap(display.presentations.first).hostPlaceholderBounds,
            CGRect(x: 80, y: 100, width: 72, height: 18)
        )
    }

    @MainActor
    func testPresenterPrefersValidatedParagraphMirrorForWrappedCompletion() throws {
        let metrics = try Self.paragraphMetrics(text: "prefix")
        let snapshot = Self.snapshot(
            caretBounds: CGRect(
                x: 86.95996,
                y: 284,
                width: 0,
                height: 16
            ),
            textBefore: metrics.textBeforeCaret,
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " completion\nand next",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.paragraphPresentations.count, 1)
        XCTAssertTrue(display.presentations.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(display.paragraphPresentations.last).attributedText.string,
            "prefix completion\nand next"
        )
        XCTAssertNotNil(presenter.lastHorizontalDrawOffset)
        XCTAssertEqual(presenter.visibleText, " completion\nand next")
        XCTAssertEqual(presenter.visibleIdentity, Self.identity(snapshot: snapshot))
        XCTAssertEqual(display.paragraphPresentations.last?.completionLineSlices.count, 2)
    }

    @MainActor
    func testStructurallyEmptyParagraphUsesExactCaretAsBootstrapAnchor() throws {
        let caret = CGRect(x: 80, y: 284, width: 0, height: 16)
        let snapshot = Self.snapshot(
            caretBounds: caret,
            textBefore: "\n",
            textAfter: "\nExisting paragraph",
            inputFrame: CGRect(x: 40, y: 100, width: 320, height: 220),
            textStyle: .init(fontName: "Menlo-Regular", fontSize: 13),
            paragraphMetrics: nil,
            paragraphMetricsFailureReason: .empty,
            fieldKind: .multiline
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: "A copied paragraph that remains inline when it wraps.",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.paragraphPresentations.count, 1)
        let font = try XCTUnwrap(display.paragraphPresentations.first?.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.fontName, "Menlo-Regular")
        XCTAssertEqual(font.pointSize, 13)
        XCTAssertEqual(
            display.paragraphPresentations.first?.attributedText.string,
            "A copied paragraph that remains inline when it wraps."
        )
        XCTAssertTrue(display.paragraphPresentations.first?.masksHostPlaceholder == true)
        XCTAssertEqual(
            display.paragraphPresentations.first?.anchor.minY,
            caret.minY
        )
    }

    @MainActor
    func testEmptySingleLineUsesExactCaretAsBootstrapAnchor() {
        let snapshot = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            caretBounds: CGRect(x: 80, y: 100, width: 0, height: 18),
            textBefore: "",
            inputFrame: CGRect(x: 40, y: 80, width: 320, height: 40),
            textStyle: ActiveFieldTextStyle(fontName: "HelveticaNeue", fontSize: 15),
            paragraphMetricsFailureReason: .empty,
            fieldKind: .singleLine
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: "Subject from current context",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.presentations.count, 1)
        XCTAssertTrue(display.presentations.first?.masksHostPlaceholder == false)
    }

    @MainActor
    func testParagraphPrerequisiteFailuresIdentifyTheMissingEvidence() {
        let cases: [(ActiveFieldSnapshot, String)] = [
            (Self.snapshot(caretBounds: nil, fieldKind: .multiline), "paragraph_caret_unavailable"),
            (Self.snapshot(inputFrame: nil, fieldKind: .multiline), "paragraph_field_unavailable"),
            (Self.snapshot(geometryQuality: .unavailable, fieldKind: .multiline), "paragraph_geometry_unavailable"),
            (Self.snapshot(caretBounds: CGRect(x: 900, y: 100, width: 1, height: 18), fieldKind: .multiline), "paragraph_caret_outside_field"),
            (Self.snapshot(textAfter: "remaining text", fieldKind: .multiline), "paragraph_not_at_end"),
            (Self.snapshot(textStyle: nil, fieldKind: .multiline), "paragraph_metrics_unavailable")
        ]
        for (snapshot, expected) in cases {
            let display = RecordingGhostTextDisplay()
            let presenter = GhostTextPresenter(display: display, displayGeometries: { [Self.display] })
            XCTAssertFalse(presenter.present(identity: Self.identity(snapshot: snapshot), text: " continuation", snapshot: snapshot))
            XCTAssertEqual(presenter.lastRejectionReason?.rawValue, expected)
            XCTAssertTrue(display.paragraphPresentations.isEmpty)
            XCTAssertTrue(display.presentations.isEmpty)
        }
    }

    @MainActor
    func testMisalignedMirrorStaysSilentInsteadOfChangingRenderer() throws {
        let metrics = try Self.paragraphMetrics(text: "En una interfaz confiable, ")
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            caretBounds: CGRect(x: 120, y: 100, width: 1, height: 18),
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )

        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(presenter.lastRejectionReason?.rawValue, "paragraph_prefix_mismatch")
        XCTAssertTrue(display.paragraphPresentations.isEmpty)
        XCTAssertTrue(display.presentations.isEmpty)
    }

    @MainActor
    func testParagraphRejectsHorizontalOverflowOutsideVisibleField() throws {
        let metrics = try Self.paragraphMetrics(text: "prefix", width: 220)
        let snapshot = Self.snapshot(
            caretBounds: CGRect(x: 86.95996, y: 284, width: 0, height: 16),
            textBefore: metrics.textBeforeCaret,
            inputFrame: CGRect(x: 40, y: 260, width: 100, height: 60),
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )
        let presenter = GhostTextPresenter(
            display: RecordingGhostTextDisplay(),
            displayGeometries: { [Self.display] }
        )

        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " completion",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(presenter.lastRejectionReason, .paragraphOutsideVisibleField)
    }

    @MainActor
    func testSoftWrappedSuggestionFitsOneVisibleLineAtVariousFontSizes() throws {
        for size: CGFloat in [13, 15, 17] {
            let font = NSFont.systemFont(ofSize: size)
            let style = ActiveFieldTextStyle(fontName: font.fontName, fontSize: size)
            let pitch = ceil(font.ascender - font.descender + font.leading)
            let metrics = ActiveFieldParagraphMetrics(textBeforeCaret: "",
                origin: CGPoint(x: 121, y: 80), width: 180, lineHeight: pitch,
                writingDirection: .leftToRight, textStyle: style, prefixStyleRuns: [], attributes: .plain)
            let snapshot = Self.snapshot(applicationBundleIdentifier: "org.example.editor", surface: .web,
                caretBounds: CGRect(x: 120, y: 80 - pitch, width: 1, height: pitch), textBefore: "Draft",
                inputFrame: CGRect(x: 40, y: 80 - pitch - 2, width: 261, height: pitch + 22),
                geometryQuality: .derived, geometrySource: .precedingGrapheme, textStyle: style,
                paragraphMetrics: metrics, fieldKind: .multiline)
            let presenter = GhostTextPresenter(display: RecordingGhostTextDisplay(), displayGeometries: { [Self.display] })
            let completion = " please review the changes and tell me whether the new behavior is correct."
            XCTAssertTrue(presenter.present(identity: Self.identity(snapshot: snapshot), text: completion, snapshot: snapshot), "size \(size): \(String(describing: presenter.lastRejectionReason))")
            XCTAssertNotNil(presenter.visibleText)
            XCTAssertTrue(completion.hasPrefix(presenter.visibleText ?? ""))
        }
    }

    @MainActor
    func testLongFirstWordCanAppearInOneNarrowVisibleLine() throws {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let style = ActiveFieldTextStyle(fontName: font.fontName, fontSize: 13)
        let metrics = ActiveFieldParagraphMetrics(textBeforeCaret: "",
            origin: CGPoint(x: 121, y: 80), width: 48, lineHeight: 16,
            writingDirection: .leftToRight, textStyle: style, prefixStyleRuns: [], attributes: .plain)
        let snapshot = Self.snapshot(applicationBundleIdentifier: "org.example.editor", surface: .web,
            caretBounds: CGRect(x: 120, y: 64, width: 1, height: 16), textBefore: "For",
            inputFrame: CGRect(x: 40, y: 60, width: 129, height: 40),
            geometryQuality: .derived, geometrySource: .precedingGrapheme, textStyle: style,
            paragraphMetrics: metrics, fieldKind: .multiline)
        let presenter = GhostTextPresenter(display: RecordingGhostTextDisplay(), displayGeometries: { [Self.display] })
        let completion = " understanding the result"
        XCTAssertTrue(presenter.present(identity: Self.identity(snapshot: snapshot), text: completion, snapshot: snapshot), "\(String(describing: presenter.lastRejectionReason)) / \(String(describing: presenter.lastParagraphLayoutFailureReason))")
        let visible = try XCTUnwrap(presenter.visibleText)
        XCTAssertFalse(visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(completion.hasPrefix(visible))
        XCTAssertLessThan(visible.utf16.count, " understanding".utf16.count)
    }

    @MainActor
    func testWebParagraphOffersOnlyTheVisibleFirstLine() throws {
        let font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 13))
        let style = ActiveFieldTextStyle(
            fontName: font.fontName,
            fontSize: font.pointSize
        )
        let inputFrame = CGRect(x: 40, y: 60, width: 360, height: 40)
        let metrics = ActiveFieldParagraphMetrics(
            textBeforeCaret: "",
            origin: CGPoint(x: 121, y: 80),
            width: 279,
            lineHeight: 16,
            writingDirection: .leftToRight,
            textStyle: style,
            prefixStyleRuns: [],
            attributes: .plain
        )
        let snapshot = Self.snapshot(
            applicationBundleIdentifier: "org.example.editor",
            surface: .web,
            caretBounds: CGRect(x: 120, y: 64, width: 1, height: 16),
            textBefore: "Draft",
            inputFrame: inputFrame,
            geometryQuality: .derived,
            geometrySource: .precedingGrapheme,
            textStyle: style,
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )
        let completion = " first line\nsecond line\nthird line"
        var overflow: GhostTextOverflow?
        var overflowIdentity: SuggestionRequestMessage.Identity?
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] },
            overflowDiagnostic: { overflowIdentity = $0; overflow = $1 }
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: completion,
                snapshot: snapshot
            )
        )
        XCTAssertNil(presenter.lastRejectionReason)
        XCTAssertEqual(presenter.visibleIdentity, Self.identity(snapshot: snapshot))
        XCTAssertEqual(presenter.visibleText, " first line")
        XCTAssertFalse(presenter.visibleGlyphRegions.isEmpty)
        XCTAssertEqual(display.paragraphPresentations.count, 1)
        XCTAssertEqual(overflowIdentity, Self.identity(snapshot: snapshot))
        let evidence = try XCTUnwrap(overflow)
        XCTAssertEqual(evidence.bottom, .multipleLines)
        XCTAssertEqual(evidence.left, .none)
        XCTAssertEqual(evidence.right, .none)
        XCTAssertEqual(evidence.completionLines, 3)
        XCTAssertEqual(evidence.availableLines, 1)
        // An already shown final cannot silently shrink on reanchoring.
        XCTAssertFalse(presenter.present(identity: Self.identity(snapshot: snapshot),
            text: completion, snapshot: snapshot, allowsFitting: false))
        XCTAssertNil(presenter.visibleText)
        // An exact multiline artifact is indivisible even when its first line fits.
        XCTAssertFalse(presenter.present(identity: Self.identity(snapshot: snapshot),
            text: completion, snapshot: snapshot, protectedText: [completion], allowsFitting: true))
        XCTAssertNil(presenter.visibleText)
    }

    @MainActor
    func testParagraphRejectsEvenSmallUnprovenGlyphClippingAtVisibleFieldEdge() throws {
        let metrics = try Self.paragraphMetrics(text: "prefix", width: 220)
        let caret = CGRect(x: 86.95996, y: 284, width: 0, height: 16)
        let completion = " completion"
        let raw = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: completion,
                caretBounds: caret
            )
        )
        let measuredOverhang: CGFloat = 1.598
        let inputFrame = CGRect(
            x: metrics.origin.x,
            y: 270,
            width: raw.frame.maxX - measuredOverhang - metrics.origin.x,
            height: 50
        )
        let snapshot = Self.snapshot(
            caretBounds: caret,
            textBefore: metrics.textBeforeCaret,
            inputFrame: inputFrame,
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )

        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: completion,
                snapshot: snapshot
            )
        )
        XCTAssertEqual(presenter.lastRejectionReason, .paragraphOutsideVisibleField)
        XCTAssertNil(presenter.visibleText)
        XCTAssertTrue(display.paragraphPresentations.isEmpty)
    }

    @MainActor
    func testSingleLineFieldUsesSingleLineRendererEvenWhenWebKitPublishesParagraphMetrics() throws {
        let metrics = try Self.paragraphMetrics(text: "Search query")
        let snapshot = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            caretBounds: CGRect(x: 120, y: 100, width: 1, height: 18),
            textBefore: metrics.textBeforeCaret,
            paragraphMetrics: metrics,
            fieldKind: .singleLine
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " completion",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.presentations.count, 1)
        XCTAssertTrue(display.paragraphPresentations.isEmpty)
    }

    @MainActor
    func testNewlineCompletionStaysSilentWhenMirrorCannotProveAlignment() throws {
        let metrics = try Self.paragraphMetrics(text: "En una interfaz confiable, ")
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            caretBounds: CGRect(x: 120, y: 100, width: 1, height: 18),
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )

        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " first\nsecond",
                snapshot: snapshot
            )
        )
        XCTAssertTrue(display.paragraphPresentations.isEmpty)
        XCTAssertTrue(display.presentations.isEmpty)
    }

    @MainActor
    func testCurrentUnrenderableFinalDismissesVisiblePartialButStaleOneDoesNot() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let current = Self.snapshot(captureSequence: 8)
        let identity = Self.identity(snapshot: current)

        XCTAssertTrue(
            presenter.present(
                identity: identity,
                text: " partial",
                snapshot: current
            )
        )
        XCTAssertFalse(
            presenter.present(
                identity: identity,
                text: " partial\nfinal",
                snapshot: current
            )
        )
        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(display.dismissCount, 1)

        XCTAssertTrue(
            presenter.present(
                identity: identity,
                text: " partial",
                snapshot: current
            )
        )
        let stale = Self.snapshot(captureSequence: 7)
        XCTAssertFalse(
            presenter.present(
                identity: identity,
                text: " partial\nfinal",
                snapshot: stale
            )
        )
        XCTAssertEqual(presenter.visibleText, " partial")
        XCTAssertEqual(display.dismissCount, 1)
    }

    @MainActor
    func testNewerUnrenderableSnapshotPreventsOlderGhostFromReappearing() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let initial = Self.snapshot(captureSequence: 8)
        let identity = Self.identity(snapshot: initial)

        XCTAssertTrue(
            presenter.present(
                identity: identity,
                text: " partial",
                snapshot: initial
            )
        )
        XCTAssertFalse(
            presenter.present(
                identity: identity,
                text: " partial\nfinal",
                snapshot: Self.snapshot(captureSequence: 9)
            )
        )
        XCTAssertNil(presenter.visibleIdentity)

        XCTAssertFalse(
            presenter.present(
                identity: identity,
                text: " stale partial",
                snapshot: initial
            )
        )
        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertEqual(display.presentations.count, 1)
    }

    @MainActor
    func testPresenterProducesAFullyFittingLTRLineFromResolvedGeometry() throws {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            caretBounds: CGRect(x: 120, y: 100, width: 1, height: 18)
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation that fits",
                snapshot: snapshot
            )
        )

        let line = try XCTUnwrap(display.presentations.last)
        XCTAssertEqual(line.frame.minX, 121, accuracy: 0.01)
        XCTAssertEqual(line.frame.maxX, 400, accuracy: 0.01)
        XCTAssertEqual(line.direction, .leftToRight)
        XCTAssertEqual(line.text, " continuation that fits")
        XCTAssertEqual(
            line.baselineY,
            109 - ((line.font.ascender + line.font.descender) / 2),
            accuracy: 0.01
        )
    }

    @MainActor
    func testSingleLineOffersExactVisiblePrefixAndDoesNotShrinkShownText() throws {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(display: display, displayGeometries: { [Self.display] })
        let snapshot = Self.snapshot(caretBounds: CGRect(x: 280, y: 100, width: 1, height: 18), textBefore: "Draft")
        let completion = " please review the changes before tomorrow"
        XCTAssertTrue(presenter.present(identity: Self.identity(snapshot: snapshot), text: completion, snapshot: snapshot), "\(String(describing: presenter.lastRejectionReason)) / \(String(describing: presenter.lastParagraphLayoutFailureReason))")
        let visible = try XCTUnwrap(presenter.visibleText)
        XCTAssertTrue(completion.hasPrefix(visible))
        XCTAssertLessThan(visible.count, completion.count)
        XCTAssertEqual(display.presentations.last?.text, visible)
        XCTAssertFalse(presenter.present(identity: Self.identity(snapshot: snapshot), text: completion,
            snapshot: snapshot, allowsFitting: false))
        XCTAssertFalse(presenter.present(identity: Self.identity(snapshot: snapshot), text: completion,
            snapshot: snapshot, protectedText: [completion]))
    }

    @MainActor
    func testSingleLineOffersClusterPrefixWhenAWholeWordDoesNotFitInBothDirections() {
        for (prefix, completion, caretX) in [
            ("Draft", " completion too long for this field", CGFloat(380)),
            ("العربية", " تستمر هذه الجملة لفترة طويلة", CGFloat(60)),
        ] {
            let display = RecordingGhostTextDisplay()
            let presenter = GhostTextPresenter(display: display, displayGeometries: { [Self.display] })
            let snapshot = Self.snapshot(
                caretBounds: CGRect(x: caretX, y: 100, width: 1, height: 18),
                textBefore: prefix
            )
            XCTAssertTrue(presenter.present(identity: Self.identity(snapshot: snapshot), text: completion, snapshot: snapshot))
            XCTAssertEqual(presenter.visibleIdentity, Self.identity(snapshot: snapshot))
            XCTAssertTrue(completion.hasPrefix(presenter.visibleText ?? ""))
            XCTAssertFalse((presenter.visibleText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(presenter.visibleGlyphRegions.isEmpty)
            XCTAssertEqual(display.presentations.count, 1)
        }
    }

    @MainActor
    func testGeometryRefreshPreservesTheExactFinalTextAndIdentityWhenItStillFits() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(display: display, displayGeometries: { [Self.display] })
        let initial = Self.snapshot(caretBounds: CGRect(x: 120, y: 100, width: 1, height: 18))
        let identity = Self.identity(snapshot: initial)
        XCTAssertTrue(presenter.present(identity: identity, text: " continuation", snapshot: initial))
        let moved = Self.snapshot(caretBounds: CGRect(x: 130, y: 100, width: 1, height: 18), captureSequence: 9)
        XCTAssertTrue(presenter.reanchor(snapshot: moved))
        XCTAssertEqual(presenter.visibleIdentity, identity)
        XCTAssertEqual(presenter.visibleText, " continuation")
        XCTAssertEqual(display.presentations.map(\.text), [" continuation", " continuation"])
    }

    @MainActor
    func testGeometryRefreshLosingFullVisibilityClearsAcceptance() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(display: display, displayGeometries: { [Self.display] })
        let initial = Self.snapshot(caretBounds: CGRect(x: 120, y: 100, width: 1, height: 18))
        XCTAssertTrue(presenter.present(identity: Self.identity(snapshot: initial), text: " continuation", snapshot: initial))
        let narrowed = Self.snapshot(caretBounds: CGRect(x: 390, y: 100, width: 1, height: 18), captureSequence: 9)
        XCTAssertFalse(presenter.reanchor(snapshot: narrowed))
        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertNil(presenter.visibleText)
        XCTAssertTrue(presenter.visibleGlyphRegions.isEmpty)
    }

    @MainActor
    func testPresenterAnchorsRTLCompletionToTheCaretLeadingEdge() throws {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            caretBounds: CGRect(x: 220, y: 100, width: 1, height: 18),
            textBefore: "العربية"
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " تستمر",
                snapshot: snapshot
            )
        )

        let line = try XCTUnwrap(display.presentations.last)
        XCTAssertEqual(line.frame.minX, 40, accuracy: 0.01)
        XCTAssertEqual(line.frame.maxX, 220, accuracy: 0.01)
        XCTAssertEqual(line.direction, .rightToLeft)
    }

    @MainActor
    func testSingleLineDirectionUsesOnlyTheCurrentParagraphThenSuggestion() throws {
        let cases: [(
            textBefore: String,
            suggestion: String,
            direction: GhostTextWritingDirection,
            minX: CGFloat,
            maxX: CGFloat
        )] = [
            ("العربية\nEnglish", " continues", .leftToRight, 221, 400),
            ("English\nالعربية", " تستمر", .rightToLeft, 40, 220),
            ("العربية\n123 ", "English", .leftToRight, 221, 400),
            ("English\n123 ", "العربية", .rightToLeft, 40, 220),
        ]

        for fixture in cases {
            let display = RecordingGhostTextDisplay()
            let presenter = GhostTextPresenter(
                display: display,
                displayGeometries: { [Self.display] }
            )
            let snapshot = Self.snapshot(
                caretBounds: CGRect(x: 220, y: 100, width: 1, height: 18),
                textBefore: fixture.textBefore
            )

            XCTAssertTrue(
                presenter.present(
                    identity: Self.identity(snapshot: snapshot),
                    text: fixture.suggestion,
                    snapshot: snapshot
                )
            )
            let line = try XCTUnwrap(display.presentations.last)
            XCTAssertEqual(line.direction, fixture.direction, fixture.textBefore)
            XCTAssertEqual(line.frame.minX, fixture.minX, accuracy: 0.01)
            XCTAssertEqual(line.frame.maxX, fixture.maxX, accuracy: 0.01)
        }
    }

    @MainActor
    func testPresenterClipsAtTheConcreteDisplayEdge() throws {
        let concreteDisplay = DisplayGeometry(
            accessibilityFrame: CGRect(x: 0, y: 0, width: 300, height: 400),
            appKitFrame: CGRect(x: 0, y: 0, width: 300, height: 400)
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [concreteDisplay] }
        )
        let snapshot = Self.snapshot(
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(display.presentations.last).frame.maxX,
            concreteDisplay.appKitFrame.maxX,
            accuracy: 0.01
        )
    }

    @MainActor
    func testPresenterAcceptsConverterOutputOnANegativeOriginDisplay() throws {
        let concreteDisplay = DisplayGeometry(
            accessibilityFrame: CGRect(x: -500, y: 0, width: 500, height: 400),
            appKitFrame: CGRect(x: -500, y: 0, width: 500, height: 400)
        )
        let caret = try XCTUnwrap(
            DisplayCoordinateConverter.appKitRect(
                fromAccessibilityRect: CGRect(x: -200, y: 100, width: 1, height: 18),
                displays: [concreteDisplay]
            )
        )
        let field = try XCTUnwrap(
            DisplayCoordinateConverter.appKitRect(
                fromAccessibilityRect: CGRect(x: -450, y: 40, width: 400, height: 300),
                displays: [concreteDisplay]
            )
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [concreteDisplay] }
        )
        let snapshot = Self.snapshot(caretBounds: caret, inputFrame: field)

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertLessThan(try XCTUnwrap(display.presentations.last).frame.minX, 0)
    }

    @MainActor
    func testPresenterRejectsUnresolvedAndSpatiallyInvalidGeometryWithoutDisplayCalls() {
        let cases = [
            Self.snapshot(
                geometryQuality: .unavailable,
                geometrySource: nil
            ),
            Self.snapshot(
                caretBounds: CGRect(x: 20, y: 100, width: 1, height: 18)
            ),
            Self.snapshot(
                caretBounds: CGRect(x: 1_000, y: 100, width: 1, height: 18),
                inputFrame: CGRect(x: 900, y: 60, width: 200, height: 240)
            ),
            Self.snapshot(captureSequence: 0),
            Self.snapshot(geometrySource: nil),
            Self.snapshot(textStyle: nil),
        ]

        for snapshot in cases {
            let display = RecordingGhostTextDisplay()
            let presenter = GhostTextPresenter(
                display: display,
                displayGeometries: { [Self.display] }
            )
            XCTAssertFalse(
                presenter.present(
                    identity: Self.identity(snapshot: snapshot),
                    text: " continuation",
                    snapshot: snapshot
                )
            )
            XCTAssertTrue(display.presentations.isEmpty)
            XCTAssertEqual(display.dismissCount, 0)
        }
    }

    @MainActor
    func testPresenterRejectsNegativeLocalAnchorWithoutMovingThePanel() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(
            caretBounds: CGRect(x: -1, y: 100, width: 1, height: 18),
            inputFrame: CGRect(x: -10, y: 60, width: 410, height: 240)
        )

        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertTrue(display.presentations.isEmpty)
        XCTAssertEqual(display.dismissCount, 0)
    }

    @MainActor
    func testStaleCaptureCannotMoveOrReorderAVisibleLine() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let current = Self.snapshot(captureSequence: 8)
        let stale = Self.snapshot(
            caretBounds: CGRect(x: 180, y: 100, width: 1, height: 18),
            captureSequence: 7
        )
        let identity = Self.identity(snapshot: current)

        XCTAssertTrue(
            presenter.present(identity: identity, text: " continuation", snapshot: current)
        )
        XCTAssertFalse(
            presenter.present(identity: identity, text: " continuation", snapshot: stale)
        )
        XCTAssertEqual(display.presentations.count, 1)
        XCTAssertEqual(display.dismissCount, 0)
    }

    @MainActor
    func testSameCaptureMayUpdateStreamingTextWithoutReorderingPolicyState() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(captureSequence: 8)
        let identity = Self.identity(snapshot: snapshot)

        XCTAssertTrue(
            presenter.present(identity: identity, text: " cont", snapshot: snapshot)
        )
        XCTAssertTrue(
            presenter.present(identity: identity, text: " continuation", snapshot: snapshot)
        )
        XCTAssertEqual(display.presentations.map(\.text), [" cont", " continuation"])
    }

    @MainActor
    func testNonInlineContentAndNewlinesStaySilent() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let middle = Self.snapshot(textAfter: "existing suffix")
        let newline = Self.snapshot(captureSequence: 2)

        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: middle),
                text: " continuation",
                snapshot: middle
            )
        )
        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: newline),
                text: " first\nsecond",
                snapshot: newline
            )
        )
        XCTAssertTrue(display.presentations.isEmpty)
    }

    @MainActor
    func testParagraphEndCanPresentBeforeLaterParagraphsInTheNote() throws {
        let metrics = try Self.paragraphMetrics(text: "prefix", width: 220)
        let snapshot = Self.snapshot(
            caretBounds: CGRect(x: 86.95996, y: 284, width: 0, height: 16),
            textBefore: metrics.textBeforeCaret,
            textAfter: "\nlater paragraph",
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " completion",
                snapshot: snapshot
            )
        )
        XCTAssertEqual(display.paragraphPresentations.count, 1)
    }

    @MainActor
    func testDisplayFailureLeavesPresenterHidden() {
        let display = RecordingGhostTextDisplay(showResult: false)
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot()

        XCTAssertFalse(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " continuation",
                snapshot: snapshot
            )
        )
        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(display.dismissCount, 0)
    }

    @MainActor
    func testDismissForAcceptanceClearsGhostBeforeHostInsertion() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot()
        let identity = Self.identity(snapshot: snapshot)
        XCTAssertTrue(
            presenter.present(
                identity: identity,
                text: " completion",
                snapshot: snapshot
            )
        )

        presenter.dismissForAcceptance(identity: identity)

        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertNil(presenter.visibleText)
        XCTAssertTrue(presenter.visibleGlyphRegions.isEmpty)
        XCTAssertEqual(display.dismissCount, 1)
    }

    @MainActor
    func testDismissForAcceptanceIgnoresAnotherSuggestionIdentity() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot()
        let identity = Self.identity(snapshot: snapshot)
        XCTAssertTrue(
            presenter.present(
                identity: identity,
                text: " completion",
                snapshot: snapshot
            )
        )

        let otherIdentity = Self.identity(
            snapshot: snapshot,
            requestID: "883739A1-17DB-4BB3-A316-B8661367FB70"
        )
        presenter.dismissForAcceptance(identity: otherIdentity)

        XCTAssertEqual(presenter.visibleIdentity, identity)
        XCTAssertEqual(presenter.visibleText, " completion")
        XCTAssertEqual(display.dismissCount, 0)
    }

    @MainActor
    func testStaleContentCannotReanchorVisibleText() {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let current = Self.snapshot(textBefore: "Current", captureSequence: 4)
        let stale = Self.snapshot(
            textBefore: "Previous",
            captureSequence: 5
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: current),
                text: " continuation",
                snapshot: current
            )
        )
        XCTAssertFalse(presenter.reanchor(snapshot: stale))
        XCTAssertEqual(display.presentations.count, 1)
    }

    @MainActor
    func testAccessibilityExposesOnlyCurrentVisibleSuggestionAndClearsOnDismiss() throws {
        let panel = GhostTextPanel()
        defer { panel.dismiss() }
        let view = try XCTUnwrap(panel.contentView)
        XCTAssertFalse(view.isAccessibilityElement())
        XCTAssertNil(view.accessibilityValue())
        XCTAssertTrue(panel.showSingleLine(try Self.line(text: " first", direction: .leftToRight)))
        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityRole(), .staticText)
        XCTAssertEqual(view.accessibilityValue() as? String, " first")
        XCTAssertTrue(panel.showSingleLine(try Self.line(text: " revised", direction: .leftToRight)))
        XCTAssertEqual(view.accessibilityValue() as? String, " revised")
        panel.dismiss()
        XCTAssertFalse(view.isAccessibilityElement())
        XCTAssertNil(view.accessibilityValue())
    }

    @MainActor
    func testAccessibilityParagraphExcludesAuthoredPrefixAndRetiredRenderer() throws {
        let panel = GhostTextPanel()
        defer { panel.dismiss() }
        XCTAssertTrue(panel.showSingleLine(try Self.line(text: " retired", direction: .leftToRight)))
        let retired = try XCTUnwrap(panel.contentView)
        let metrics = try Self.paragraphMetrics(text: "Lista:", width: 220)
        let paragraph = try XCTUnwrap(ParagraphMirrorLayout.validated(
            surface: .web, metrics: metrics,
            completion: "\n- primer punto\n\n- segundo punto",
            caretBounds: CGRect(x: 86.95996, y: 284, width: 0, height: 16)
        ))
        XCTAssertTrue(panel.showParagraphMirror(paragraph))
        let current = try XCTUnwrap(panel.contentView)
        XCTAssertEqual(current.accessibilityValue() as? String, "\n- primer punto\n\n- segundo punto")
        XCTAssertFalse(retired.isAccessibilityElement())
        XCTAssertNil(retired.accessibilityValue())
        panel.orderOut(nil)
        XCTAssertFalse(current.isAccessibilityElement())
        XCTAssertNil(current.accessibilityValue())
    }

    @MainActor
    func testAccessibilityDoesNotExposeSuggestionWhenPanelCannotBecomeVisible() throws {
        let panel = GhostTextPanel(orderFrontAction: { _ in })
        XCTAssertFalse(panel.showSingleLine(try Self.line(text: " hidden", direction: .leftToRight)))
        let view = try XCTUnwrap(panel.contentView)
        XCTAssertFalse(view.isAccessibilityElement())
        XCTAssertNil(view.accessibilityValue())
    }

    @MainActor
    func testRejectedReplacementRemovesVisibleAndAccessibleOldSuggestion() throws {
        let panel = GhostTextPanel()
        defer { panel.dismiss() }
        let valid = try Self.line(text: " old", direction: .leftToRight)
        XCTAssertTrue(panel.showSingleLine(valid))
        let view = try XCTUnwrap(panel.contentView)
        let invalid = GhostTextSingleLinePresentation(
            text: "invalid\nline", frame: valid.frame, baselineY: valid.baselineY,
            font: valid.font, direction: valid.direction
        )
        XCTAssertFalse(panel.showSingleLine(invalid))
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(view.accessibilityValue())
    }

    @MainActor
    func testPanelIsNonActivatingNonAnimatedAndMouseTransparent() {
        let panel = GhostTextPanel(orderFrontAction: { _ in })

        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.animationBehavior, .none)
    }

    @MainActor
    func testPanelReportsFailureForBothRenderersWhenOrderingDoesNotMakeWindowVisible() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { _ in orderCount += 1 })
        let line = try Self.line(
            text: " continuation",
            direction: .leftToRight
        )
        let metrics = try Self.paragraphMetrics(text: "prefix", width: 220)
        let paragraph = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion that wraps onto another line",
                caretBounds: CGRect(
                    x: 86.95996,
                    y: 284,
                    width: 0,
                    height: 16
                )
            )
        )

        XCTAssertFalse(panel.showSingleLine(line))
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(orderCount, 1)

        XCTAssertFalse(panel.showParagraphMirror(paragraph))
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(orderCount, 2)
    }

    @MainActor
    func testPanelReportsSuccessWhenOrderingMakesWindowVisible() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { panel in
            orderCount += 1
            panel.orderFrontRegardless()
        })
        defer { panel.orderOut(nil) }
        let line = try Self.line(
            text: " continuation",
            direction: .leftToRight
        )

        XCTAssertTrue(panel.showSingleLine(line))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(orderCount, 1)
    }

    @MainActor
    func testPointerHitRegionsCoverRenderedParagraphLinesButNotTransparentPanelSpace() throws {
        let metrics = try Self.paragraphMetrics(text: "prefix", width: 180)
        let snapshot = Self.snapshot(
            caretBounds: CGRect(
                x: 86.95996,
                y: 284,
                width: 0,
                height: 16
            ),
            textBefore: metrics.textBeforeCaret,
            paragraphMetrics: metrics,
            fieldKind: .multiline
        )
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )

        XCTAssertTrue(
            presenter.present(
                identity: Self.identity(snapshot: snapshot),
                text: " completion that wraps onto another line",
                snapshot: snapshot
            )
        )
        let paragraph = try XCTUnwrap(display.paragraphPresentations.last)
        XCTAssertGreaterThan(paragraph.lineFragments.count, 1)
        XCTAssertTrue(
            paragraph.lineFragments
                .filter { $0.width > 0 && $0.height > 0 }
                .allSatisfy { presenter.isVisibleGlyph(at: CGPoint(x: $0.midX, y: $0.midY)) }
        )
        XCTAssertFalse(
            presenter.isVisibleGlyph(
                at: CGPoint(x: paragraph.frame.maxX - 1, y: paragraph.frame.minY + 1)
            )
        )
    }

    @MainActor
    func testSingleLineHitRegionStopsAtRenderedTextAndDismissClearsIt() throws {
        let display = RecordingGhostTextDisplay()
        let presenter = GhostTextPresenter(
            display: display,
            displayGeometries: { [Self.display] }
        )
        let snapshot = Self.snapshot(paragraphMetrics: nil)
        let identity = Self.identity(snapshot: snapshot)

        XCTAssertTrue(
            presenter.present(
                identity: identity,
                text: " completion",
                snapshot: snapshot
            )
        )
        let region = try XCTUnwrap(presenter.visibleGlyphRegions.first)
        XCTAssertTrue(presenter.isVisibleGlyph(at: CGPoint(x: region.midX, y: region.midY)))
        XCTAssertLessThan(region.maxX, try XCTUnwrap(display.presentations.last).frame.maxX)
        XCTAssertFalse(
            presenter.isVisibleGlyph(
                at: CGPoint(
                    x: try XCTUnwrap(display.presentations.last).frame.maxX - 1,
                    y: region.midY
                )
            )
        )

        XCTAssertTrue(presenter.dismiss(identity: identity))
        XCTAssertTrue(presenter.visibleGlyphRegions.isEmpty)
        XCTAssertFalse(presenter.isVisibleGlyph(at: CGPoint(x: region.midX, y: region.midY)))
    }

    @MainActor
    func testPanelDrawsExactlyOneClippedLineAtTheMeasuredBaseline() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { panel in
            orderCount += 1
            panel.orderFrontRegardless()
        })
        defer { panel.orderOut(nil) }
        let line = try Self.line(
            text: String(repeating: "a long completion ", count: 20),
            direction: .leftToRight
        )

        XCTAssertTrue(panel.showSingleLine(line))
        let lineView = try XCTUnwrap(panel.contentView as? GhostTextLineView)
        XCTAssertEqual(panel.frame, line.frame)
        XCTAssertEqual(lineView.text, line.text)
        XCTAssertEqual(lineView.direction, .leftToRight)
        XCTAssertEqual(lineView.baselineOffset, line.baselineY - line.frame.minY, accuracy: 0.01)
        XCTAssertEqual(lineView.lineCount, 1)
        XCTAssertTrue(lineView.clipsToBounds)
        XCTAssertEqual(orderCount, 1)
    }

    @MainActor
    func testPanelMasksOnlyTheExplicitHostPlaceholderBounds() throws {
        let panel = GhostTextPanel(orderFrontAction: { panel in
            panel.orderFrontRegardless()
        })
        defer { panel.orderOut(nil) }
        let font = try XCTUnwrap(NSFont(name: ".AppleSystemUIFont", size: 14))
        let frame = CGRect(x: 80, y: 100, width: 320, height: 20)
        let placeholderBounds = CGRect(x: 80, y: 101, width: 72, height: 18)
        let line = GhostTextSingleLinePresentation(
            text: " continuation",
            frame: frame,
            baselineY: 114,
            font: font,
            direction: .leftToRight,
            masksHostPlaceholder: true,
            hostPlaceholderBounds: placeholderBounds
        )

        XCTAssertTrue(panel.showSingleLine(line))
        let lineView = try XCTUnwrap(panel.contentView as? GhostTextLineView)

        XCTAssertEqual(
            lineView.placeholderMaskRect,
            placeholderBounds.offsetBy(dx: -frame.minX, dy: -frame.minY)
        )
        XCTAssertEqual(lineView.layer?.backgroundColor, NSColor.clear.cgColor)
    }

    @MainActor
    func testPanelUsesRTLDrawOriginAndOrdersOnlyAcrossVisibilityTransitions() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { panel in
            orderCount += 1
            panel.orderFrontRegardless()
        })
        defer { panel.orderOut(nil) }
        let first = try Self.line(text: " تستمر", direction: .rightToLeft)
        let updated = try Self.line(text: " تستمر بثبات", direction: .rightToLeft)

        XCTAssertTrue(panel.showSingleLine(first))
        XCTAssertTrue(panel.showSingleLine(updated))
        let lineView = try XCTUnwrap(panel.contentView as? GhostTextLineView)
        XCTAssertEqual(lineView.direction, .rightToLeft)
        XCTAssertGreaterThanOrEqual(lineView.drawOriginX, 0)
        XCTAssertLessThanOrEqual(lineView.drawOriginX, first.frame.width)
        XCTAssertEqual(orderCount, 1)

        panel.dismiss()
        XCTAssertTrue(panel.showSingleLine(first))
        XCTAssertEqual(orderCount, 2)
    }

    @MainActor
    func testExternallyOrderedOutPanelReordersBeforeReportingShown() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { panel in
            orderCount += 1
            panel.orderFrontRegardless()
        })
        defer { panel.orderOut(nil) }
        let line = try Self.line(
            text: " continuation",
            direction: .leftToRight
        )

        XCTAssertTrue(panel.showSingleLine(line))
        XCTAssertEqual(orderCount, 1)

        panel.orderOut(nil)

        XCTAssertTrue(panel.showSingleLine(line))
        XCTAssertEqual(orderCount, 2)
    }

    @MainActor
    func testPanelDrawsMeasuredParagraphMirrorAndOrdersOnlyOnce() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { panel in
            orderCount += 1
            panel.orderFrontRegardless()
        })
        defer { panel.orderOut(nil) }
        let metrics = try Self.paragraphMetrics(text: "Lista:", width: 220)
        let paragraph = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .web,
                metrics: metrics,
                completion: "\n- primer punto\n\n- segundo punto",
                caretBounds: CGRect(
                    x: 86.95996,
                    y: 284,
                    width: 0,
                    height: 16
                )
            )
        )

        XCTAssertTrue(panel.showParagraphMirror(paragraph))
        XCTAssertTrue(panel.showParagraphMirror(paragraph))
        let paragraphView = try XCTUnwrap(panel.contentView as? GhostTextParagraphView)
        XCTAssertEqual(panel.frame, paragraph.frame.integral)
        XCTAssertEqual(paragraphView.attributedText.string, paragraph.attributedText.string)
        XCTAssertLessThan(paragraph.textOrigin.y, -0.1)
        XCTAssertEqual(paragraphView.textOrigin, paragraph.textOrigin)
        XCTAssertEqual(paragraphView.lineFragmentCount, 4)
        XCTAssertEqual(
            paragraphView.attributedText.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor,
            .clear
        )
        XCTAssertEqual(
            paragraphView.attributedText.attribute(
                .foregroundColor,
                at: paragraph.completionRange.location,
                effectiveRange: nil
            ) as? NSColor,
            GhostTextColor.resolve(for: nil)
        )
        XCTAssertEqual(orderCount, 1)
    }

    @MainActor
    func testParagraphViewAppliesCaretCalibrationOnlyToTheInsertionLineSlice() throws {
        let metrics = try Self.paragraphMetrics(
            text: "Una interfaz funcio",
            width: 210
        )
        let paragraph = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "na de manera confiable mientras la sugerencia se envuelve",
                caretBounds: CGRect(
                    x: 189.2065,
                    y: 284,
                    width: 1,
                    height: 16
                )
            )
        )

        let paragraphView = GhostTextParagraphView(
            frame: CGRect(origin: .zero, size: paragraph.frame.size)
        )
        XCTAssertTrue(paragraphView.update(with: paragraph))
        XCTAssertEqual(
            paragraphView.completionLineSlices,
            paragraph.completionLineSlices
        )
        XCTAssertEqual(
            try XCTUnwrap(paragraphView.completionLineSlices.first)
                .horizontalDrawOffset,
            1.5,
            accuracy: 0.01
        )
        XCTAssertTrue(
            paragraphView.completionLineSlices.dropFirst().allSatisfy {
                $0.horizontalDrawOffset == 0
            }
        )
    }

    @MainActor
    func testParagraphViewRasterContainsVisibleCompletionAfterBoundedCaretDrift() throws {
        let metrics = try Self.paragraphMetrics(
            text: "draft En una interfaz confia",
            width: 260
        )
        let paragraph = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "ble, la sugerencia permanece junto al cursor mientras escribís.",
                caretBounds: CGRect(
                    x: 259.6465,
                    y: 284,
                    width: 1,
                    height: 16
                )
            )
        )

        let paragraphView = GhostTextParagraphView(
            frame: CGRect(origin: .zero, size: paragraph.frame.size)
        )
        XCTAssertTrue(paragraphView.update(with: paragraph))
        XCTAssertGreaterThan(try Self.visiblePixelCount(in: paragraphView), 0)
    }

    @MainActor
    func testParagraphViewRasterDrawsNoWrapUnicodeAndBidiCompletions() throws {
        let cases: [(
            prefix: String,
            completion: String,
            direction: CaretWritingDirection,
            caret: CGRect
        )] = [
            (
                "emoji 🚀 funcio",
                "na",
                .leftToRight,
                CGRect(x: 158.9966, y: 284, width: 1, height: 16)
            ),
            (
                "cafe\u{301}",
                " funciona",
                .leftToRight,
                CGRect(x: 72.55664, y: 284, width: 0, height: 16)
            ),
            (
                "مرحبا ",
                "باقتراح",
                .rightToLeft,
                CGRect(x: 314.417, y: 284, width: 0, height: 16)
            ),
        ]

        for fixture in cases {
            let metrics = try Self.paragraphMetrics(
                text: fixture.prefix,
                width: 320,
                direction: fixture.direction
            )
            let paragraph = try XCTUnwrap(
                ParagraphMirrorLayout.validated(
                    surface: .native,
                    metrics: metrics,
                    completion: fixture.completion,
                    caretBounds: fixture.caret
                ),
                fixture.prefix
            )

            let paragraphView = GhostTextParagraphView(
                frame: CGRect(origin: .zero, size: paragraph.frame.size)
            )
            XCTAssertTrue(
                paragraphView.update(with: paragraph),
                fixture.prefix
            )
            XCTAssertGreaterThan(
                try Self.visiblePixelCount(in: paragraphView),
                0,
                fixture.prefix
            )
        }
    }

    @MainActor
    func testPanelRejectsParagraphWhenNoSliceResolvesToDrawableGlyphs() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { _ in orderCount += 1 })
        let metrics = try Self.paragraphMetrics(text: "prefix", width: 220)
        let valid = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "🚀",
                caretBounds: CGRect(
                    x: 86.95996,
                    y: 284,
                    width: 0,
                    height: 16
                )
            )
        )
        let malformed = ParagraphMirrorLayoutResult(
            attributedText: valid.attributedText,
            completionRange: valid.completionRange,
            containerSize: valid.containerSize,
            frame: valid.frame,
            textOrigin: valid.textOrigin,
            lineFragments: valid.lineFragments,
            completionLineSlices: [
                ParagraphMirrorLineSlice(
                    characterRange: NSRange(
                        location: valid.completionRange.location,
                        length: 1
                    ),
                    horizontalDrawOffset: 0,
                    bounds: valid.frame
                ),
            ],
            anchor: valid.anchor
        )
        let originalFrame = panel.frame

        XCTAssertFalse(panel.showParagraphMirror(malformed))
        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertEqual(orderCount, 0)
    }

    @MainActor
    func testPanelRejectsInvalidFrameWithoutMovementOrOrdering() throws {
        var orderCount = 0
        let panel = GhostTextPanel(orderFrontAction: { _ in orderCount += 1 })
        let valid = try Self.line(text: " visible", direction: .leftToRight)
        let invalid = GhostTextSingleLinePresentation(
            text: valid.text,
            frame: CGRect(x: -10, y: 20, width: -1, height: 16),
            baselineY: valid.baselineY,
            font: valid.font,
            direction: valid.direction
        )
        let originalFrame = panel.frame

        XCTAssertFalse(panel.showSingleLine(invalid))
        XCTAssertEqual(panel.frame, originalFrame)
        XCTAssertEqual(orderCount, 0)
    }

    private static let display = DisplayGeometry(
        accessibilityFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
        appKitFrame: CGRect(x: 0, y: 0, width: 500, height: 400)
    )

    private static func snapshot(
        applicationBundleIdentifier: String = "com.apple.Notes",
        surface: WritingSurface = .native,
        caretBounds: CGRect? = CGRect(x: 120, y: 100, width: 1, height: 18),
        textBefore: String = "Hello",
        textAfter: String = "",
        inputFrame: CGRect? = CGRect(x: 40, y: 60, width: 360, height: 240),
        geometryQuality: GeometryQuality = .exact,
        geometrySource: CaretGeometrySource? = .zeroLengthRange,
        captureSequence: UInt64 = 1,
        textStyle: ActiveFieldTextStyle? = .init(
            fontName: ".AppleSystemUIFont",
            fontSize: 13
        ),
        paragraphMetrics: ActiveFieldParagraphMetrics? = nil,
        paragraphMetricsFailureReason: ActiveFieldParagraphMetricsFailureReason? = nil,
        fieldKind: ActiveFieldKind = .singleLine,
        masksHostPlaceholder: Bool = false,
        hostPlaceholderBounds: CGRect? = nil
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: applicationBundleIdentifier,
            surface: surface,
            elementIdentifier: "notes-field-1",
            focusGeneration: 1,
            textBefore: textBefore,
            selectedText: "",
            textAfter: textAfter,
            selectionRange: NSRange(location: textBefore.utf16.count, length: 0),
            caretBounds: caretBounds,
            inputFrame: inputFrame,
            geometryQuality: geometryQuality,
            geometrySource: geometrySource,
            captureSequence: captureSequence,
            textStyle: textStyle,
            paragraphMetrics: paragraphMetrics,
            paragraphMetricsFailureReason: paragraphMetricsFailureReason,
            fieldKind: fieldKind,
            masksHostPlaceholder: masksHostPlaceholder,
            hostPlaceholderBounds: hostPlaceholderBounds
        )
    }

    @MainActor
    private static func paragraphMetrics(
        text: String,
        width: CGFloat = 220,
        direction: CaretWritingDirection = .leftToRight
    ) throws -> ActiveFieldParagraphMetrics {
        let font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 13))
        let style = ActiveFieldTextStyle(
            fontName: font.fontName,
            fontSize: font.pointSize
        )
        return ActiveFieldParagraphMetrics(
            textBeforeCaret: text,
            origin: CGPoint(x: 40, y: 300),
            width: width,
            lineHeight: 16,
            writingDirection: direction,
            textStyle: style,
            prefixStyleRuns: [
                .init(
                    range: NSRange(location: 0, length: text.utf16.count),
                    style: style
                ),
            ],
            attributes: .plain
        )
    }

    private static func identity(
        snapshot: ActiveFieldSnapshot,
        requestID: String = "DA2F74CE-C1DA-4E2E-85C7-B6D3C4069B63"
    ) -> SuggestionRequestMessage.Identity {
        SuggestionRequestMessage.Identity(
            requestId: requestID,
            focusSequence: snapshot.focusGeneration,
            contentSignature: snapshot.contentSignature,
            timestampMs: 1_788_000_000_000
        )
    }

    @MainActor
    private static func line(
        text: String,
        direction: GhostTextWritingDirection
    ) throws -> GhostTextSingleLinePresentation {
        let font = try XCTUnwrap(NSFont(name: ".AppleSystemUIFont", size: 13))
        return GhostTextSingleLinePresentation(
            text: text,
            frame: CGRect(x: 120, y: 100, width: 200, height: 18),
            baselineY: 112,
            font: font,
            direction: direction
        )
    }

    @MainActor
    private static func visiblePixelCount(in view: NSView) throws -> Int {
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds)
        )
        view.cacheDisplay(in: view.bounds, to: bitmap)

        var count = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                count += 1
            }
        }
        return count
    }
}

@MainActor
private final class RecordingGhostTextDisplay: GhostTextDisplaying {
    private let showResult: Bool
    private(set) var presentations: [GhostTextSingleLinePresentation] = []
    private(set) var paragraphPresentations: [ParagraphMirrorLayoutResult] = []
    private(set) var dismissCount = 0

    init(showResult: Bool = true) {
        self.showResult = showResult
    }

    func showSingleLine(_ presentation: GhostTextSingleLinePresentation) -> Bool {
        presentations.append(presentation)
        return showResult
    }

    func showParagraphMirror(_ presentation: ParagraphMirrorLayoutResult) -> Bool {
        paragraphPresentations.append(presentation)
        return showResult
    }

    func dismiss() {
        dismissCount += 1
    }
}

private enum AcceptanceProbeResult: Equatable {
    case inserted
    case failed
}
