import AppKit
import XCTest
@testable import AutocompleteHelper

final class ParagraphMirrorLayoutTests: XCTestCase {
    @MainActor
    func testMixedStylePrefixKeepsItsFontRunsAndUsesCaretStyleForCompletion() throws {
        let regular = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 13))
        let bold = try XCTUnwrap(NSFont(name: "Menlo-Bold", size: 13))
        var metrics = try Self.metrics(text: "prefix", width: 220)
        metrics.textStyle = .init(fontName: bold.fontName, fontSize: bold.pointSize)
        metrics.prefixStyleRuns = [
            .init(
                range: NSRange(location: 0, length: 3),
                style: .init(fontName: regular.fontName, fontSize: regular.pointSize)
            ),
            .init(
                range: NSRange(location: 3, length: 3),
                style: .init(fontName: bold.fontName, fontSize: bold.pointSize)
            ),
        ]

        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: CGRect(x: 86.95996, y: 284, width: 0, height: 16)
            )
        )

        XCTAssertEqual(
            (result.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName,
            regular.fontName
        )
        XCTAssertEqual(
            (result.attributedText.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.fontName,
            bold.fontName
        )
        XCTAssertEqual(
            (result.attributedText.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)?.fontName,
            bold.fontName
        )
    }

    @MainActor
    func testPartialWordCompletionUsesTheRealPrefixForWrapping() throws {
        let metrics = try Self.metrics(
            text: "Una interfaz funcio",
            width: 210,
            lineHeight: 18
        )
        let caret = CGRect(x: 187.7065, y: 282, width: 1, height: 18)

        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "na de manera confiable",
                caretBounds: caret
            )
        )

        XCTAssertEqual(
            result.attributedText.string,
            "Una interfaz funciona de manera confiable"
        )
        XCTAssertEqual(
            result.completionRange,
            NSRange(
                location: "Una interfaz funcio".utf16.count,
                length: "na de manera confiable".utf16.count
            )
        )
        XCTAssertEqual(result.anchor, caret)
        XCTAssertEqual(
            try XCTUnwrap(result.lineFragments.first).minX,
            caret.maxX,
            accuracy: 1
        )
    }

    @MainActor
    func testBoundedCaretDriftCalibratesOnlyTheInsertionLine() throws {
        let metrics = try Self.metrics(
            text: "Una interfaz funcio",
            width: 210,
            lineHeight: 18
        )
        let exactCaretMinX: CGFloat = 187.7065
        let exact = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "na de manera confiable mientras la sugerencia se envuelve",
                caretBounds: CGRect(
                    x: exactCaretMinX,
                    y: 282,
                    width: 1,
                    height: 18
                )
            )
        )

        for drift in [CGFloat(1.25), CGFloat(-1.75)] {
            let caret = CGRect(
                x: exactCaretMinX + drift,
                y: 282,
                width: 1,
                height: 18
            )
            let result = try XCTUnwrap(
                ParagraphMirrorLayout.validated(
                    surface: .native,
                    metrics: metrics,
                    completion: "na de manera confiable mientras la sugerencia se envuelve",
                    caretBounds: caret
                ),
                "drift \(drift)"
            )

            XCTAssertGreaterThan(result.lineFragments.count, 1, "drift \(drift)")
            XCTAssertEqual(
                try XCTUnwrap(result.lineFragments.first).minX,
                caret.maxX,
                accuracy: 0.1,
                "drift \(drift)"
            )
            XCTAssertEqual(
                result.lineFragments[1].minX,
                metrics.origin.x,
                accuracy: 0.1,
                "continuation line must keep the measured paragraph origin"
            )
            XCTAssertEqual(
                result.completionLineSlices.map(\.characterRange),
                exact.completionLineSlices.map(\.characterRange),
                "calibration must not change which characters wrap to each line"
            )
            XCTAssertEqual(
                result.lineFragments.map(\.width),
                exact.lineFragments.map(\.width),
                "calibration must not change measured glyph advances"
            )
            XCTAssertEqual(
                try XCTUnwrap(result.completionLineSlices.first)
                    .horizontalDrawOffset,
                drift,
                accuracy: 0.01
            )
            XCTAssertTrue(
                result.completionLineSlices.dropFirst().allSatisfy {
                    $0.horizontalDrawOffset == 0
                },
                "only the insertion-line slice may move"
            )
            XCTAssertNil(
                result.attributedText.attribute(
                    .kern,
                    at: result.completionRange.location - 1,
                    effectiveRange: nil
                ),
                "caret calibration must not change TextKit shaping or wrapping"
            )
        }
    }

    @MainActor
    func testHostCaretDriftBeyondLegacyBoundAnchorsWithoutEscapingTheParagraph() throws {
        let metrics = try Self.metrics(
            text: "Una interfaz funcio",
            width: 210,
            lineHeight: 18
        )
        let caret = CGRect(
            x: 187.7065 + 6,
            y: 282,
            width: 1,
            height: 18
        )

        let evaluation = ParagraphMirrorLayout.evaluate(
                surface: .native,
                metrics: metrics,
                completion: "na de manera confiable y se envuelve sin desbordarse",
                caretBounds: caret
        )
        let result = try XCTUnwrap(
            evaluation.presentation,
            "failure: \(String(describing: evaluation.failureReason))"
        )

        XCTAssertEqual(
            try XCTUnwrap(result.lineFragments.first).minX,
            caret.maxX,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(result.lineFragments.count, 1)
        XCTAssertTrue(
            result.lineFragments.allSatisfy {
                $0.minX >= metrics.origin.x - 0.5
                    && $0.maxX <= metrics.origin.x + metrics.width + 0.5
            }
        )
    }

    @MainActor
    func testLongNativePrefixCalibratesSmallUnreportedTrackingButShortPrefixStillRejectsIt() throws {
        let prefix = String(repeating: "a", count: 104)
        let completion = " continuation"
        let font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 13))
        let measuredPrefixWidth = (prefix as NSString).size(
            withAttributes: [.font: font]
        ).width
        let longMetrics = try Self.metrics(text: prefix, width: 1_200)
        let trackingDrift: CGFloat = 8.1
        let longCaret = Self.caret(
            longMetrics,
            x: longMetrics.origin.x + measuredPrefixWidth + trackingDrift
        )

        let calibrated = ParagraphMirrorLayout.evaluate(
            surface: .native,
            metrics: longMetrics,
            completion: completion,
            caretBounds: longCaret
        )
        let result = try XCTUnwrap(
            calibrated.presentation,
            "failure: \(String(describing: calibrated.failureReason))"
        )

        XCTAssertEqual(
            try XCTUnwrap(result.lineFragments.first).minX,
            longCaret.maxX,
            accuracy: 0.5
        )
        XCTAssertNotNil(
            result.attributedText.attribute(
                .kern,
                at: result.completionRange.location,
                effectiveRange: nil
            ),
            "the measured per-glyph drift must calibrate hidden host tracking"
        )

        let shortMetrics = try Self.metrics(text: "aaaa", width: 1_200)
        let shortWidth = ("aaaa" as NSString).size(
            withAttributes: [.font: font]
        ).width
        let rejected = ParagraphMirrorLayout.evaluate(
            surface: .native,
            metrics: shortMetrics,
            completion: completion,
            caretBounds: Self.caret(
                shortMetrics,
                x: shortMetrics.origin.x + shortWidth + trackingDrift
            )
        )
        XCTAssertNil(rejected.presentation)
        XCTAssertEqual(rejected.failureReason, .horizontalDrift)
    }

    @MainActor
    func testBoundedCaretCalibrationPreservesUnicodeAndBidiPrefixes() throws {
        let cases: [(
            prefix: String,
            completion: String,
            direction: CaretWritingDirection,
            exactCaretX: CGFloat
        )] = [
            ("emoji 🚀 funcio", "na sin cortar el grapheme", .leftToRight, 157.7466),
            ("cafe\u{301} funcio", "na con acento combinado", .leftToRight, 125.0933),
            ("日本語", "の候補が正しく折り返される", .leftToRight, 78),
            ("مرحبا ", "باقتراح يلتف من اليمين", .rightToLeft, 313.167),
        ]

        for fixture in cases {
            let metrics = try Self.metrics(
                text: fixture.prefix,
                width: 320,
                direction: fixture.direction,
                lineHeight: 18
            )
            let caret = CGRect(
                x: fixture.exactCaretX + 1.25,
                y: 282,
                width: fixture.direction == .leftToRight ? 1 : 0,
                height: 18
            )
            let result = try XCTUnwrap(
                ParagraphMirrorLayout.validated(
                    surface: .native,
                    metrics: metrics,
                    completion: fixture.completion,
                    caretBounds: caret
                ),
                fixture.prefix
            )

            let insertionFragment = try XCTUnwrap(
                result.lineFragments.first,
                fixture.prefix
            )
            switch fixture.direction {
            case .leftToRight:
                XCTAssertEqual(
                    insertionFragment.minX,
                    caret.maxX,
                    accuracy: 0.1,
                    fixture.prefix
                )
            case .rightToLeft:
                XCTAssertEqual(
                    insertionFragment.maxX,
                    caret.minX,
                    accuracy: 0.1,
                    fixture.prefix
                )
            }
        }
    }

    @MainActor
    func testRTLCalibrationAcceptsSubEmAXTextKitDrift() throws {
        let metrics = try Self.metrics(
            text: "مرحبا ",
            width: 320,
            direction: .rightToLeft,
            lineHeight: 18
        )
        // A live Notes capture measured -8.127 pt between the AX caret and
        // TextKit's insertion boundary. That is still less than half of the
        // measured line height, so the renderer can align it unambiguously.
        let caret = CGRect(
            x: 313.167 - 8.127,
            y: 282,
            width: 0,
            height: 18
        )

        let evaluation = ParagraphMirrorLayout.evaluate(
            surface: .native,
            metrics: metrics,
            completion: " باقتراح موثوق",
            caretBounds: caret
        )
        let result = try XCTUnwrap(
            evaluation.presentation,
            "failure: \(String(describing: evaluation.failureReason))"
        )

        XCTAssertEqual(
            try XCTUnwrap(result.lineFragments.first).maxX,
            caret.minX,
            accuracy: 1
        )
        XCTAssertLessThanOrEqual(
            abs(try XCTUnwrap(result.completionLineSlices.first).horizontalDrawOffset),
            8,
            "the accepted layout must remain drawable by the shared panel"
        )
    }

    @MainActor
    func testBoundaryCalibrationDoesNotSplitComposedOrConnectedText() throws {
        let cases: [(
            prefix: String,
            completion: String,
            direction: CaretWritingDirection,
            exactCaretX: CGFloat
        )] = [
            ("emoji 🚀", " funciona", .leftToRight, 103.95996),
            ("cafe\u{301}", " funciona", .leftToRight, 71.30664),
        ]

        for fixture in cases {
            let metrics = try Self.metrics(
                text: fixture.prefix,
                width: 320,
                direction: fixture.direction,
                lineHeight: 18
            )
            let result = try XCTUnwrap(
                ParagraphMirrorLayout.validated(
                    surface: .native,
                    metrics: metrics,
                    completion: fixture.completion,
                    caretBounds: CGRect(
                        x: fixture.exactCaretX + 1.25,
                        y: 282,
                        width: 0,
                        height: 18
                    )
                ),
                fixture.prefix
            )

            XCTAssertEqual(
                result.attributedText.string,
                fixture.prefix + fixture.completion,
                fixture.prefix
            )
            XCTAssertNil(
                result.attributedText.attribute(
                    .kern,
                    at: result.completionRange.location - 1,
                    effectiveRange: nil
                ),
                fixture.prefix
            )
            XCTAssertEqual(
                try XCTUnwrap(result.completionLineSlices.first)
                    .characterRange.location,
                result.completionRange.location,
                fixture.prefix
            )
        }

        let connectedRTL = try Self.metrics(
            text: "العربية",
            width: 320,
            direction: .rightToLeft,
            lineHeight: 18
        )
        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: connectedRTL,
                completion: "تستمر",
                caretBounds: CGRect(
                    x: 205.3911 + 1.25,
                    y: 282,
                    width: 0,
                    height: 18
                )
            ),
            "joining that reshapes the host prefix must fail closed"
        )
    }

    @MainActor
    func testPrefixIsTransparentAndOnlyCompletionProducesHitFragments() throws {
        let result = try Self.fullPrefixResult()
        let prefixRange = NSRange(
            location: 0,
            length: result.completionRange.location
        )

        XCTAssertEqual(
            result.attributedText.attribute(
                .foregroundColor,
                at: prefixRange.location,
                effectiveRange: nil
            ) as? NSColor,
            .clear
        )
        XCTAssertEqual(
            result.attributedText.attribute(
                .foregroundColor,
                at: result.completionRange.location,
                effectiveRange: nil
            ) as? NSColor,
            GhostTextColor.resolve(for: nil)
        )
        XCTAssertTrue(
            result.lineFragments.allSatisfy { $0.width > 0 && $0.height > 0 }
        )
    }

    @MainActor
    func testCompletionColorFollowsTheHostTextAcrossLightAndDarkSurfaces() throws {
        var metrics = try Self.metrics(text: "prefix", width: 220)
        metrics.textStyle = ActiveFieldTextStyle(
            fontName: metrics.textStyle.fontName,
            fontSize: metrics.textStyle.fontSize,
            foregroundColor: ActiveFieldTextColor(
                red: 0.13,
                green: 0.24,
                blue: 0.35,
                alpha: 1
            )
        )
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .web,
                metrics: metrics,
                completion: " completion",
                caretBounds: Self.caret(metrics, x: 86.95996)
            )
        )
        let color = try XCTUnwrap(try XCTUnwrap(
            result.attributedText.attribute(
                .foregroundColor,
                at: result.completionRange.location,
                effectiveRange: nil
            ) as? NSColor
        ).usingColorSpace(.sRGB))

        XCTAssertEqual(color.redComponent, 0.13, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0.24, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0.35, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 0.30, accuracy: 0.001)
    }

    @MainActor
    func testFullPrefixWrappingPreservesSpacesUnicodeAndBidi() throws {
        let cases: [(
            prefix: String,
            completion: String,
            direction: CaretWritingDirection,
            insertionX: CGFloat
        )] = [
            ("dos  ", "espacios conservan el ajuste", .leftToRight, 79.1333),
            ("emoji 🚀 funcio", "na sin cortar el grapheme", .leftToRight, 158.7466),
            ("cafe\u{301} funcio", "na con acento combinado", .leftToRight, 126.0933),
            ("日本語", "の候補が正しく折り返される", .leftToRight, 79),
            ("مرحبا ", "باقتراح يلتف من اليمين", .rightToLeft, 313.167),
        ]

        for fixture in cases {
            let metrics = try Self.metrics(
                text: fixture.prefix,
                width: 320,
                direction: fixture.direction,
                lineHeight: 18
            )
            let caret = CGRect(
                x: fixture.direction == .leftToRight
                    ? fixture.insertionX - 1
                    : fixture.insertionX,
                y: 282,
                width: 1,
                height: 18
            )
            let result = try XCTUnwrap(
                ParagraphMirrorLayout.validated(
                    surface: .native,
                    metrics: metrics,
                    completion: fixture.completion,
                    caretBounds: caret
                ),
                fixture.prefix
            )

            XCTAssertEqual(
                result.attributedText.string,
                fixture.prefix + fixture.completion,
                fixture.prefix
            )
            XCTAssertEqual(
                result.completionRange,
                NSRange(
                    location: fixture.prefix.utf16.count,
                    length: fixture.completion.utf16.count
                ),
                fixture.prefix
            )
            XCTAssertEqual(result.anchor, caret, fixture.prefix)
            XCTAssertTrue(
                result.lineFragments.allSatisfy {
                    $0.width > 0
                        && $0.height > 0
                        && $0.minX >= metrics.origin.x - 0.5
                        && $0.maxX <= metrics.origin.x + metrics.width + 0.5
                },
                fixture.prefix
            )
            let insertionEdge = try XCTUnwrap(
                result.lineFragments.first,
                fixture.prefix
            )
            switch fixture.direction {
            case .leftToRight:
                XCTAssertEqual(
                    insertionEdge.minX,
                    caret.maxX,
                    accuracy: 1,
                    fixture.prefix
                )
            case .rightToLeft:
                XCTAssertEqual(
                    insertionEdge.maxX,
                    caret.minX,
                    accuracy: 1,
                    fixture.prefix
                )
            }
        }
    }

    @MainActor
    func testContradictoryHorizontalCaretGeometryFailsClosed() throws {
        let metrics = try Self.metrics(text: "prefix", width: 220)

        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: CGRect(x: 120, y: 284, width: 0, height: 16)
            )
        )
    }

    @MainActor
    func testCaretDisplacedByExactlyOneLineFailsClosed() throws {
        let metrics = try Self.metrics(text: "prefix", width: 220)

        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: CGRect(
                    x: 86.95996,
                    y: 268,
                    width: 0,
                    height: 16
                )
            )
        )
    }

    @MainActor
    func testMixedBidiCompletionsUseTextKitVisualRunBounds() throws {
        let cases: [(
            prefix: String,
            completion: String,
            direction: CaretWritingDirection,
            caret: CGRect,
            expectedMinX: CGFloat,
            expectedMaxX: CGFloat
        )] = [
            (
                "مرحبا ",
                "reliable completion",
                .rightToLeft,
                CGRect(x: 313.167, y: 282, width: 1, height: 18),
                164.4604,
                313.167
            ),
            (
                "Hello ",
                "اقتراح موثوق",
                .leftToRight,
                CGRect(x: 85.95996, y: 282, width: 1, height: 18),
                86.95996,
                180.6006
            ),
        ]

        for fixture in cases {
            let metrics = try Self.metrics(
                text: fixture.prefix,
                width: 320,
                direction: fixture.direction,
                lineHeight: 18
            )
            let result = try XCTUnwrap(
                ParagraphMirrorLayout.validated(
                    surface: .native,
                    metrics: metrics,
                    completion: fixture.completion,
                    caretBounds: fixture.caret
                ),
                fixture.prefix
            )

            XCTAssertEqual(result.anchor, fixture.caret, fixture.prefix)
            XCTAssertEqual(result.lineFragments.count, 1, fixture.prefix)
            let fragment = try XCTUnwrap(
                result.lineFragments.first,
                fixture.prefix
            )
            XCTAssertEqual(
                fragment.minX,
                fixture.expectedMinX,
                accuracy: 0.1,
                fixture.prefix
            )
            XCTAssertEqual(
                fragment.maxX,
                fixture.expectedMaxX,
                accuracy: 0.1,
                fixture.prefix
            )
        }
    }

    @MainActor
    func testLongProseWrapsFromTheRealCaretIntoMeasuredFragments() throws {
        let metrics = try Self.metrics(text: "En una interfaz confiable, ", width: 180)
        let caret = CGRect(
            x: 126.0933,
            y: 268,
            width: 0,
            height: 16
        )
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "la sugerencia permanece junto al cursor mientras escribís.",
                caretBounds: caret
            )
        )

        XCTAssertGreaterThan(result.lineFragments.count, 1)
        XCTAssertEqual(result.lineFragments[0].minX, caret.minX, accuracy: 0.5)
        XCTAssertEqual(result.lineFragments[0].maxY, 284, accuracy: 1)
        XCTAssertEqual(result.lineFragments[1].minX, 40, accuracy: 0.5)
        XCTAssertTrue(result.lineFragments.allSatisfy { $0.maxX <= 220.5 })
        XCTAssertEqual(
            result.completionRange,
            NSRange(
                location: metrics.textBeforeCaret.utf16.count,
                length: "la sugerencia permanece junto al cursor mientras escribís."
                    .utf16.count
            )
        )
    }

    @MainActor
    func testPrivateWebKitFontStillWrapsLongSafariCompletion() throws {
        let metrics = try Self.metrics(
            text: "En una interfaz confiable, ",
            width: 180,
            fontName: ".WebKitUnresolvableSystemAlias",
            fontSize: 17,
            lineHeight: 24.65
        )
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .web,
                metrics: metrics,
                completion: "la sugerencia permanece junto al cursor mientras escribís.",
                caretBounds: Self.wrappedSafariCaret
            )
        )

        XCTAssertGreaterThan(result.lineFragments.count, 1)
        XCTAssertTrue(result.lineFragments.allSatisfy { $0.maxX <= 220.5 })
    }

    @MainActor
    func testSafariUsesCSSCenteredBaselineInsideTheCapturedLineBox() throws {
        let metrics = try Self.metrics(
            text: "En una interfaz confiable, ",
            width: 180,
            fontName: ".WebKitUnresolvableSystemAlias",
            fontSize: 17,
            lineHeight: 24.65
        )
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .web,
                metrics: metrics,
                completion: "la sugerencia se mantiene alineada",
                caretBounds: Self.wrappedSafariCaret
            )
        )

        XCTAssertLessThan(result.textOrigin.y, -0.5)
    }

    @MainActor
    func testSafariOpticalBaselineCorrectionUsesOnePhysicalPixel() throws {
        let metrics = try Self.metrics(
            text: "En una interfaz confiable, ",
            width: 180,
            fontName: ".WebKitUnresolvableSystemAlias",
            fontSize: 17,
            lineHeight: 24.65
        )
        let caret = Self.wrappedSafariCaret
        let standard = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .web,
                backingScaleFactor: 1,
                metrics: metrics,
                completion: "la sugerencia se mantiene alineada",
                caretBounds: caret
            )
        )
        let retina = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .web,
                backingScaleFactor: 2,
                metrics: metrics,
                completion: "la sugerencia se mantiene alineada",
                caretBounds: caret
            )
        )

        XCTAssertEqual(
            standard.textOrigin.y,
            retina.textOrigin.y - 0.5,
            accuracy: 0.01
        )
    }

    @MainActor
    func testCaretOffsetDoesNotIndentSubsequentParagraphs() throws {
        var metrics = try Self.metrics(
            text: "", width: 300
        )
        metrics.prefixStyleRuns = []
        metrics.insertionLineHeadIndent = 80
        let result = try XCTUnwrap(ParagraphMirrorLayout.validated(
            surface: .native, metrics: metrics,
            completion: "first\nsecond\n\nthird",
            caretBounds: Self.caret(metrics, x: 120)
        ))
        let visible = result.lineFragments.filter { $0.width > 0 }
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(visible[0].minX, 120, accuracy: 0.5)
        XCTAssertEqual(visible[1].minX, 40, accuracy: 0.5)
        XCTAssertEqual(visible[2].minX, 40, accuracy: 0.5)
    }

    @MainActor
    func testExplicitNewlinesAndBlankLinesRemainDistinctFragments() throws {
        let metrics = try Self.metrics(text: "Lista:", width: 220)
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "\n- primer punto\n\n- segundo punto",
                caretBounds: Self.caret(metrics, x: 86.95996)
            )
        )

        XCTAssertEqual(result.lineFragments.count, 4)
        XCTAssertEqual(
            result.lineFragments.map { Int($0.midY.rounded()) },
            [292, 276, 260, 244]
        )
    }

    @MainActor
    func testWrappedLinesUseCapturedIndentAttributes() throws {
        var attributes = ActiveFieldParagraphAttributes.plain
        attributes.headIndent = 18
        let metrics = try Self.metrics(
            text: "• punto existente ",
            width: 180,
            attributes: attributes
        )
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "con una explicación extensa que envuelve",
                caretBounds: Self.caret(metrics, x: 180.8799)
            )
        )

        XCTAssertEqual(
            try XCTUnwrap(result.lineFragments.first).minX,
            180.8799,
            accuracy: 0.5
        )
        XCTAssertEqual(
            try XCTUnwrap(result.lineFragments.dropFirst().first).minX,
            58,
            accuracy: 0.5
        )
    }

    @MainActor
    func testUnicodeCompletionsRemainAnchoredForBothDirections() throws {
        let fixtures: [(String, String, CaretWritingDirection, CGFloat)] = [
            ("emoji 🚀", " continúa", .leftToRight, 103.95996),
            ("café", " continúa", .leftToRight, 71.30664),
            ("日本語", " 続きます", .leftToRight, 79),
            ("العربية", " تستمر", .rightToLeft, 205.3911),
        ]

        for (text, completion, direction, caretX) in fixtures {
            let metrics = try Self.metrics(
                text: text,
                width: 220,
                direction: direction
            )
            let caret = Self.caret(metrics, x: caretX)
            let result = try XCTUnwrap(
                ParagraphMirrorLayout.validated(
                    surface: .native,
                    metrics: metrics,
                    completion: completion,
                    caretBounds: caret
                )
            )

            XCTAssertEqual(result.attributedText.string, text + completion)
            XCTAssertEqual(result.completionRange.location, text.utf16.count)
            XCTAssertFalse(result.lineFragments.isEmpty)
            XCTAssertEqual(result.anchor.minX, caretX, accuracy: 0.02, text)
            XCTAssertTrue(
                result.lineFragments.allSatisfy {
                    $0.minX >= metrics.origin.x - 0.5
                        && $0.maxX <= metrics.origin.x + metrics.width + 0.5
                },
                text
            )
        }
    }

    @MainActor
    func testOnlyTheCompletionIsVisible() throws {
        let metrics = try Self.metrics(text: "prefix", width: 220)
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: Self.caret(metrics, x: 86.95996)
            )
        )

        XCTAssertEqual(result.attributedText.string, "prefix completion")
        XCTAssertEqual(result.completionRange.location, "prefix".utf16.count)
        XCTAssertEqual(
            result.attributedText.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor,
            .clear
        )
        XCTAssertEqual(
            result.attributedText.attribute(
                .foregroundColor,
                at: result.completionRange.location,
                effectiveRange: nil
            ) as? NSColor,
            GhostTextColor.resolve(for: nil)
        )
    }

    @MainActor
    func testActivationRequiresCaretInsideMeasuredWidthAndMatchingLineHeight() throws {
        let metrics = try Self.metrics(text: "prefix", width: 220)

        XCTAssertNotNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: Self.caret(metrics, x: 86.95996)
            )
        )
        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: Self.caret(metrics, x: 300)
            )
        )
        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: CGRect(x: 88, y: 284, width: 0, height: 20)
            )
        )
        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: " completion",
                caretBounds: CGRect(x: 88, y: 284, width: -1, height: 16)
            )
        )
    }

    @MainActor
    func testPartialWordCompletionAnchorsAtTheRealCaretBeforeWrapping() throws {
        let metrics = try Self.metrics(text: "Texto previo funcio", width: 160)
        let caret = CGRect(x: 86.95996, y: 268, width: 0, height: 16)
        let result = try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "na y una continuación extensa",
                caretBounds: caret
            )
        )

        XCTAssertEqual(
            result.completionRange.location,
            "Texto previo funcio".utf16.count
        )
        XCTAssertEqual(
            try XCTUnwrap(result.lineFragments.first).minX,
            caret.minX,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(result.lineFragments.count, 1)
    }

    @MainActor
    func testMissingOrContradictoryMetricsStayUnavailable() throws {
        var invalid = try Self.metrics(text: "prefix", width: 220)
        invalid.width = 0
        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: invalid,
                completion: " completion",
                caretBounds: Self.caret(invalid, x: 88)
            )
        )

        invalid = try Self.metrics(text: "prefix", width: 220)
        invalid.lineHeight = .nan
        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: invalid,
                completion: " completion",
                caretBounds: CGRect(x: 88, y: 284, width: 0, height: 16)
            )
        )
    }

    @MainActor
    func testDirectListMetadataCannotBypassLayoutValidation() throws {
        var markerAttributes = ActiveFieldParagraphAttributes.plain
        markerAttributes.listMarker = "•"
        let markerMetrics = try Self.metrics(
            text: "item",
            width: 220,
            attributes: markerAttributes
        )
        var levelAttributes = ActiveFieldParagraphAttributes.plain
        levelAttributes.listLevel = 0
        let levelMetrics = try Self.metrics(
            text: "item",
            width: 220,
            attributes: levelAttributes
        )

        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: markerMetrics,
                completion: " continuation",
                caretBounds: Self.caret(markerMetrics)
            )
        )
        XCTAssertNil(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: levelMetrics,
                completion: " continuation",
                caretBounds: Self.caret(levelMetrics)
            )
        )
    }

    private static func caret(
        _ metrics: ActiveFieldParagraphMetrics,
        x: CGFloat? = nil
    ) -> CGRect {
        CGRect(
            x: x ?? metrics.origin.x,
            y: metrics.origin.y - metrics.lineHeight,
            width: 0,
            height: metrics.lineHeight
        )
    }

    @MainActor
    private static func fullPrefixResult() throws -> ParagraphMirrorLayoutResult {
        let metrics = try Self.metrics(
            text: "Una interfaz funcio",
            width: 210,
            lineHeight: 18
        )
        return try XCTUnwrap(
            ParagraphMirrorLayout.validated(
                surface: .native,
                metrics: metrics,
                completion: "na de manera confiable",
                caretBounds: CGRect(
                    x: 187.7065,
                    y: 282,
                    width: 1,
                    height: 18
                )
            )
        )
    }

    private static let wrappedSafariCaret = CGRect(
        x: 118.7412,
        y: 250.7,
        width: 0,
        height: 24.65
    )

    @MainActor
    private static func metrics(
        text: String,
        width: CGFloat,
        direction: CaretWritingDirection = .leftToRight,
        attributes: ActiveFieldParagraphAttributes = .plain,
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        lineHeight: CGFloat = 16
    ) throws -> ActiveFieldParagraphMetrics {
        let font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 13))
        let style = ActiveFieldTextStyle(
            fontName: fontName ?? font.fontName,
            fontSize: fontSize ?? font.pointSize
        )
        return ActiveFieldParagraphMetrics(
            textBeforeCaret: text,
            origin: CGPoint(x: 40, y: 300),
            width: width,
            lineHeight: lineHeight,
            writingDirection: direction,
            textStyle: style,
            prefixStyleRuns: [
                .init(
                    range: NSRange(location: 0, length: text.utf16.count),
                    style: style
                ),
            ],
            attributes: attributes
        )
    }
}
