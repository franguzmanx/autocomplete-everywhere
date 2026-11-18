import ApplicationServices
import AppKit
import Foundation
import XCTest
@testable import AutocompleteHelper

final class ActiveFieldCaptureTests: XCTestCase {
    func testFocusedRangeTypographyUsesOnlyTheVerifiedInsertionCharacter() throws {
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let style = SystemAccessibilityReader.focusedRangeTextStyle(
            value: "Hi ñ", selection: NSRange(location: 4, length: 0),
            markerTextBefore: "Hi ñ", markerTextAfter: "",
            read: { range in
                XCTAssertEqual(range, NSRange(location: 3, length: 1))
                return NSAttributedString(string: "ñ", attributes: [.font: font])
            })
        XCTAssertEqual(style?.fontSize, 17)
        XCTAssertEqual(style?.fontName, font.fontName)
    }

    func testFocusedRangeTypographyRejectsDisagreementAndUnownedText() {
        let font = NSFont.systemFont(ofSize: 30, weight: .bold)
        var reads = 0
        let read: (NSRange) -> NSAttributedString? = { _ in
            reads += 1
            return NSAttributedString(string: "x", attributes: [.font: font])
        }
        XCTAssertNil(SystemAccessibilityReader.focusedRangeTextStyle(
            value: "Hi", selection: NSRange(location: 2, length: 0),
            markerTextBefore: "Other", markerTextAfter: "", read: read))
        XCTAssertNil(SystemAccessibilityReader.focusedRangeTextStyle(
            value: "", selection: NSRange(location: 0, length: 0),
            markerTextBefore: "", markerTextAfter: "", read: read))
        XCTAssertNil(SystemAccessibilityReader.focusedRangeTextStyle(
            value: "Hi", selection: NSRange(location: 0, length: 2),
            markerTextBefore: "", markerTextAfter: "", read: read))
        XCTAssertEqual(reads, 0)
        XCTAssertNil(SystemAccessibilityReader.focusedRangeTextStyle(
            value: "Hi", selection: NSRange(location: 2, length: 0),
            markerTextBefore: "Hi", markerTextAfter: "", read: read))
        XCTAssertEqual(reads, 1)
    }

    func testVerifiedTextNodeMeasuresSizeWithoutUsingCaretOrEditorHeight() throws {
        let text = "Can you help me understand this"
        let focused = try XCTUnwrap(FocusedEditableText(value: text, selection: NSRange(location: text.utf16.count, length: 0)))
        for size: CGFloat in [12, 16, 22] {
            let font = NSFont.systemFont(ofSize: size)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            let height = ceil(font.ascender - font.descender + font.leading)
            let style = try XCTUnwrap(SystemAccessibilityReader.measuredNodeTextStyle(
                focusedText: focused, nodeRole: "AXStaticText", nodeText: text, currentLineText: text,
                nodeBounds: CGRect(x: 50, y: 60, width: width, height: height),
                inputFrame: CGRect(x: 30, y: 30, width: 900, height: 400)))
            XCTAssertEqual(style.fontSize, size, accuracy: 0.5)
            XCTAssertTrue(style.isEstimated)
            XCTAssertFalse(NSFontManager.shared.traits(of: try XCTUnwrap(GhostTextTypography.font(for: style))).contains(.boldFontMask))
        }
    }

    func testTextNodeEstimateRejectsBlocksWrappedAndUnrelatedText() throws {
        let text = "Can you help me understand this"
        let focused = try XCTUnwrap(FocusedEditableText(value: text, selection: NSRange(location: text.utf16.count, length: 0)))
        let frame = CGRect(x: 30, y: 30, width: 900, height: 400)
        let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 16)]).width
        let box = CGRect(x: 50, y: 60, width: width, height: 20)
        XCTAssertNil(SystemAccessibilityReader.measuredNodeTextStyle(focusedText: focused,
            nodeRole: "AXTextArea", nodeText: text, currentLineText: text, nodeBounds: box, inputFrame: frame))
        XCTAssertNil(SystemAccessibilityReader.measuredNodeTextStyle(focusedText: focused,
            nodeRole: "AXStaticText", nodeText: "Other", currentLineText: text, nodeBounds: box, inputFrame: frame))
        XCTAssertNil(SystemAccessibilityReader.measuredNodeTextStyle(focusedText: focused,
            nodeRole: "AXStaticText", nodeText: text, currentLineText: "this", nodeBounds: box, inputFrame: frame))
        XCTAssertNil(SystemAccessibilityReader.measuredNodeTextStyle(focusedText: focused,
            nodeRole: "AXStaticText", nodeText: text, currentLineText: text,
            nodeBounds: CGRect(x: 50, y: 60, width: width, height: 68), inputFrame: frame))
    }

    func testWordWidthCannotIdentifyAnUnknownFont() throws {
        let word = "measured"
        let font = NSFont.systemFont(ofSize: 15)
        let width = (word as NSString).size(withAttributes: [.font: font]).width
        let sample = CGRect(x: 40, y: 100, width: width, height: 20)
        let caret = CGRect(x: 40 + width, y: 100, width: 0, height: 20)
        let field = CGRect(x: 30, y: 80, width: 400, height: 100)
        let result = SystemAccessibilityReader.webCalibratedTextStyle(nil,
            sampleText: word, sampleBounds: sample, currentLineBounds: sample,
            caretBounds: caret, fieldBounds: field)
        XCTAssertNil(result)
        XCTAssertNil(SystemAccessibilityReader.webCalibratedTextStyle(nil,
            sampleText: word, sampleBounds: sample, currentLineBounds: sample,
            caretBounds: CGRect(x: caret.minX, y: 80, width: 0, height: 68), fieldBounds: field))
    }

    func testCalibrationAcceptsCaretInsideLineWithoutEquatingTheirHeights() {
        let style = ActiveFieldTextStyle(fontName: "HelveticaNeue", fontSize: 15)
        let text = "measured"
        let width = (text as NSString).size(withAttributes: [.font: NSFont(name: style.fontName, size: 15)!]).width
        var reasons: [String] = []
        let result = SystemAccessibilityReader.webCalibratedTextStyle(style,
            sampleText: text, sampleBounds: CGRect(x: 40, y: 100, width: width, height: 24),
            currentLineBounds: CGRect(x: 40, y: 100, width: width, height: 24),
            caretBounds: CGRect(x: 40 + width, y: 103, width: 0, height: 18),
            fieldBounds: CGRect(x: 30, y: 90, width: 400, height: 60), diagnostic: { reasons.append($0) })
        XCTAssertEqual(result, style)
        XCTAssertEqual(reasons, ["typography_attributed_attributed_width_verified"])
        reasons.removeAll()
        _ = SystemAccessibilityReader.webCalibratedTextStyle(style, sampleText: text,
            sampleBounds: CGRect(x: 40, y: 100, width: width, height: 24), currentLineBounds: nil,
            caretBounds: nil, fieldBounds: nil, diagnostic: { reasons.append($0) })
        XCTAssertEqual(reasons, ["typography_attributed_line_missing"])
    }

    func testEmptyFieldCanReadOwnedParagraphTerminatorFont() {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key("AXFont"): ["AXFontName": "HelveticaNeue", "AXFontSize": 15] as NSDictionary
        ]
        XCTAssertEqual(SystemAccessibilityReader.emptyFieldTextStyle(
            from: NSAttributedString(string: "\n", attributes: attributes), fieldValue: "")?.fontSize, 15)
        XCTAssertNil(SystemAccessibilityReader.emptyFieldTextStyle(
            from: NSAttributedString(string: "Other message", attributes: attributes), fieldValue: ""))
        XCTAssertNil(SystemAccessibilityReader.emptyFieldTextStyle(
            from: NSAttributedString(string: "\n", attributes: attributes), fieldValue: "Draft"))
        XCTAssertNil(SystemAccessibilityReader.emptyFieldTextStyle(
            from: NSAttributedString(string: ""), fieldValue: ""))
    }

    func testInvalidWebGlyphDoesNotSuppressMeasuredLineCaret() {
        for glyph in [CGRect(x: 700, y: 500, width: 8, height: 18), CGRect(x: 178, y: 100, width: 8, height: 0)] {
            let reader = FakeAccessibilityReader(webContent: true, text: nil, selection: nil)
            reader.webContext = WebTextContext(
                editableIdentifier: "editor", role: "AXTextArea", textBefore: "Draft reply",
                frame: CGRect(x: 40, y: 60, width: 360, height: 240),
                caretCandidates: [
                    .init(rect: glyph, source: .followingGrapheme),
                    .init(rect: CGRect(x: 100, y: 100, width: 80, height: 18), source: .lineEnd),
                ],
                lineBounds: CGRect(x: 100, y: 100, width: 80, height: 18)
            )
            let snapshot = captured(reader)
            XCTAssertNotNil(snapshot?.caretBounds)
            XCTAssertEqual(snapshot?.geometrySource, .lineEnd)
        }
    }

    func testValidWebGlyphRetainsPriorityOverDisagreeingLineEdge() {
        let reader = FakeAccessibilityReader(webContent: true, text: nil, selection: nil)
        reader.webContext = WebTextContext(
            editableIdentifier: "editor", role: "AXTextArea", textBefore: "Draft reply",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 172, y: 100, width: 8, height: 18), source: .precedingGrapheme),
                .init(rect: CGRect(x: 100, y: 100, width: 160, height: 18), source: .lineEnd),
            ],
            lineBounds: CGRect(x: 100, y: 100, width: 160, height: 18)
        )
        let snapshot = captured(reader)
        XCTAssertNotNil(snapshot?.caretBounds)
        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
    }

    func testCurrentLineRejectsGlyphFromPreviousWrappedLine() {
        let caret = CaretGeometryCandidate(rect: CGRect(x: 90, y: 124, width: 0, height: 18), source: .zeroLengthRange)
        let oldGlyph = CaretGeometryCandidate(rect: CGRect(x: 320, y: 100, width: 8, height: 18), source: .precedingGrapheme)
        let line = CGRect(x: 40, y: 124, width: 50, height: 18)
        XCTAssertEqual(SystemAccessibilityReader.candidatesOnCurrentLine(
            [caret, oldGlyph], textBefore: "second", textAfter: "", lineBounds: line), [caret])
        // No independent line/caret agreement: preserve uncertainty.
        XCTAssertEqual(SystemAccessibilityReader.candidatesOnCurrentLine(
            [caret, oldGlyph], textBefore: "second", textAfter: "", lineBounds: nil), [caret, oldGlyph])
    }

    func testEmptyWebLineUsesItsMeasuredCaretInsteadOfThePrecedingContentGlyph() {
        let caret = CaretGeometryCandidate(rect: CGRect(x: 647, y: 856, width: 0, height: 19), source: .zeroLengthRange)
        let previous = CaretGeometryCandidate(rect: CGRect(x: 767, y: 856, width: 5, height: 19), source: .precedingGrapheme)
        for lineEnd in ["", "\n", "\r\n"] {
            XCTAssertEqual(SystemAccessibilityReader.candidatesOnCurrentLine(
                [caret, previous], textBefore: "", textAfter: lineEnd, lineBounds: caret.rect
            ), [caret])
        }
    }

    func testNonemptyOrUnknownWebLinePreservesConflictingEvidence() {
        let caret = CaretGeometryCandidate(rect: CGRect(x: 647, y: 856, width: 0, height: 19), source: .zeroLengthRange)
        let previous = CaretGeometryCandidate(rect: CGRect(x: 767, y: 856, width: 5, height: 19), source: .precedingGrapheme)
        for (before, after): (String?, String?) in [("a", ""), ("", "a"), ("", " "), (nil, ""), ("", nil)] {
            XCTAssertEqual(SystemAccessibilityReader.candidatesOnCurrentLine(
                [caret, previous], textBefore: before, textAfter: after, lineBounds: caret.rect
            ), [caret, previous])
        }
    }

    func testEmptyWebLineCannotInventCaretFromBlockOrUnmatchedGeometry() {
        let caret = CaretGeometryCandidate(rect: CGRect(x: 647, y: 856, width: 0, height: 19), source: .zeroLengthRange)
        let previous = CaretGeometryCandidate(rect: CGRect(x: 767, y: 856, width: 5, height: 19), source: .precedingGrapheme)
        for bounds in [nil, CGRect(x: 647, y: 856, width: 472, height: 23), caret.rect.offsetBy(dx: 30, dy: 0)] {
            XCTAssertEqual(SystemAccessibilityReader.candidatesOnCurrentLine(
                [caret, previous], textBefore: "", textAfter: "\n", lineBounds: bounds
            ), [caret, previous])
        }
        XCTAssertEqual(SystemAccessibilityReader.candidatesOnCurrentLine(
            [previous], textBefore: "", textAfter: "\n", lineBounds: caret.rect
        ), [previous])
    }

    func testSourceBodyRefreshesWithoutChangingTheReplyTargetIdentity() throws {
        let reader = FakeAccessibilityReader(text: "", selection: NSRange(location: 0, length: 0))
        reader.sources = [.init(id: "post", containerId: "group", relation: .sharedContainer, text: "Source one")]
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)
        guard case let .captured(empty) = capture.capture() else { return XCTFail("capture") }
        reader.text = "Reply"
        reader.selection = NSRange(location: 5, length: 0)
        guard case let .captured(typing) = capture.capture() else { return XCTFail("capture") }
        XCTAssertEqual(empty.fieldContext.sources, typing.fieldContext.sources)
        reader.sources = [.init(id: "post", containerId: "group", relation: .sharedContainer, text: "Source two")]
        guard case let .captured(revised) = capture.capture() else { return XCTFail("capture") }
        XCTAssertEqual(typing.textBefore, revised.textBefore)
        XCTAssertNotEqual(typing.fieldContext.sources, revised.fieldContext.sources)
        XCTAssertEqual(typing.contentSignature, revised.contentSignature)
        reader.sources = [.init(id: "another-post", containerId: "group", relation: .sharedContainer, text: "Source two")]
        guard case let .captured(newTarget) = capture.capture() else { return XCTFail("capture") }
        XCTAssertNotEqual(revised.contentSignature, newTarget.contentSignature)
    }

    func testWebSourcesRemainAvailableAfterTheComposerIsStarted() {
        let reader = FakeAccessibilityReader(webContent: true, text: nil, selection: nil)
        reader.sources = [.init(id: "post", containerId: "group", relation: .sharedContainer, text: "Visible source")]
        reader.webContext = WebTextContext(editableIdentifier: "composer", role: "AXTextArea", textBefore: "", frame: nil)
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)
        guard case let .captured(empty) = capture.capture() else { return XCTFail("capture") }
        reader.webContext = WebTextContext(editableIdentifier: "composer", role: "AXTextArea", textBefore: "My reply", frame: nil)
        guard case let .captured(started) = capture.capture() else { return XCTFail("capture") }
        XCTAssertEqual(started.fieldContext.sources, empty.fieldContext.sources)
        XCTAssertEqual(reader.sourceReadCount, 2)
        XCTAssertEqual(started.textBefore, "My reply")
    }

    func testUserExcludedAppIsRejectedBeforeReadingTextOrPreparingWebContext() throws {
        let reader = FakeAccessibilityReader(bundleIdentifier: "com.example.browser", webContent: true, role: "AXTextArea", text: "Excluded text", selection: NSRange(location: 0, length: 0))
        let capture = ActiveFieldCapture(reader: reader)
        let command = try XCTUnwrap(HelperCommandDecoder().decode(#"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":["com.example.browser"],"automaticSuggestions":true,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#))
        guard case let .configure(config) = command else { return XCTFail("Expected configuration") }
        capture.updateConfiguration(config)
        XCTAssertEqual(capture.capture(), .skipped(.unsupportedApplication))
        XCTAssertEqual(reader.stringValueReadCount, 0)
        XCTAssertEqual(reader.webAccessibilityPreparationCount, 0)
        XCTAssertEqual(reader.webContextReadCount, 0)
        XCTAssertEqual(reader.sourceReadCount, 0)
    }

    func testNativeCaptureReportsMissingValueSeparately() {
        let reader = FakeAccessibilityReader(text: nil, selection: NSRange(location: 0, length: 0))
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.valueMissing))
    }

    func testNativeCaptureReportsMissingRangeSeparately() {
        let reader = FakeAccessibilityReader(text: "Hello", selection: nil)
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.rangeMissing))
    }

    func testNativeCaptureReportsOutOfBoundsRangeSeparately() {
        let reader = FakeAccessibilityReader(
            text: "Hello",
            selection: NSRange(location: 20, length: 0)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.rangeOutOfBounds))
    }

    func testWebCaptureReportsMarkerReadFailureSeparately() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.browser",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.markerReadFailed))
    }

    func testWebAreaIsNotMisclassifiedAsAFocusedEditableField() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.browser",
            webContent: true,
            role: "AXWebArea",
            text: nil,
            selection: nil
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.unsupportedRole))
        XCTAssertEqual(reader.webAccessibilityPreparationCount, 0)
        XCTAssertEqual(reader.webContextReadCount, 0)
    }

    func testSemanticMetadataPrefersExplicitPlaceholderAndUsesSyntheticPlaceholderOnlyAsFallback() {
        XCTAssertEqual(
            SystemAccessibilityReader.semanticPlaceholder(
                accessibilityPlaceholder: "Subject",
                syntheticPlaceholder: "Chrome fallback"
            ),
            "Subject"
        )
        XCTAssertEqual(
            SystemAccessibilityReader.semanticPlaceholder(
                accessibilityPlaceholder: nil,
                syntheticPlaceholder: "Do anything"
            ),
            "Do anything"
        )
    }

    func testSemanticLabelUsesDescriptionBeforeTitleOrHelp() {
        XCTAssertEqual(
            SystemAccessibilityReader.semanticLabel(
                description: "Message Body",
                title: "Compose",
                help: "Write the email"
            ),
            "Message Body"
        )
    }

    func testRelatedFieldSelectionRejectsAnEntireSecureAdjacentContainer() {
        let fields = SystemAccessibilityReader.relatedFieldContexts(
            from: [
                RelatedFieldCandidate(
                    role: "AXTextArea",
                    subrole: nil,
                    label: "Message Body",
                    placeholder: nil,
                    identifier: nil,
                    text: "Hola Dana, te comparto la propuesta.",
                    frame: CGRect(x: 100, y: 160, width: 500, height: 220)
                ),
                RelatedFieldCandidate(
                    role: "AXTextField",
                    subrole: "AXSecureTextField",
                    label: "Password",
                    placeholder: nil,
                    identifier: nil,
                    text: "never-read-me",
                    frame: CGRect(x: 100, y: 430, width: 300, height: 32)
                ),
                RelatedFieldCandidate(
                    role: "AXTextField",
                    subrole: nil,
                    label: "Unrelated",
                    placeholder: nil,
                    identifier: nil,
                    text: "ignored",
                    frame: CGRect(x: 100, y: 470, width: 300, height: 32)
                ),
            ]
        )

        XCTAssertTrue(fields.isEmpty)
    }

    func testCapturesPlaceholderAsRawFieldContextWithoutTreatingItAsText() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: "AXTextField",
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "gmail-subject",
            role: "AXTextField",
            textBefore: "",
            textAfter: "",
            frame: CGRect(x: 40, y: 80, width: 320, height: 32),
            caretCandidates: [
                .init(
                    rect: CGRect(x: 48, y: 88, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
            ],
            placeholder: "Subject"
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.textBefore, "")
        XCTAssertEqual(snapshot?.textAfter, "")
        XCTAssertEqual(snapshot?.fieldContext.placeholder, "Subject")
        XCTAssertEqual(snapshot?.fieldContext.shape, .singleLine)
    }

    func testFocusedTextAreaCanBeItsOwnWebTextMarkerProvider() {
        XCTAssertTrue(
            SystemAccessibilityReader.hasUsableTextMarkerProvider(
                attributeNames: ["AXSelectedTextMarkerRange"],
                parameterizedAttributeNames: [
                    "AXTextMarkerRangeForUIElement",
                    "AXStringForTextMarkerRange",
                    "AXBoundsForTextMarkerRange",
                ]
            )
        )
    }

    func testWebMarkerReadBudgetUsesBootstrapTimeoutUntilFirstSuccessfulContext() {
        var budget = WebTextMarkerReadBudget()

        XCTAssertEqual(budget.timeout(for: pid_t(665)), 6)
        XCTAssertEqual(budget.timeout(for: pid_t(665)), 6)

        budget.recordSuccess(for: pid_t(665))

        XCTAssertEqual(budget.timeout(for: pid_t(665)), 0.5)
        XCTAssertEqual(budget.timeout(for: pid_t(777)), 6)
    }

    func testFocusedEditableTextUsesOnlyTheFocusedAXValueAndSelection() throws {
        let owned = try XCTUnwrap(FocusedEditableText(
            value: "hola mundo",
            selection: NSRange(location: 4, length: 1)
        ))

        XCTAssertEqual(owned.textBefore, "hola")
        XCTAssertEqual(owned.selectedText, " ")
        XCTAssertEqual(owned.textAfter, "mundo")
        XCTAssertEqual(owned.selectionLocation, 4)
        XCTAssertEqual(owned.selectionLength, 1)

        XCTAssertNil(FocusedEditableText(
            value: "hola",
            selection: NSRange(location: 400, length: 0)
        ))
    }

    func testOwnedLastParagraphCanAnchorWithoutContainingEarlierParagraphs() throws {
        let line = "hmmm no sale todavía"
        let value = "sí\n\na ver sale b\n\n" + line
        let focused = try XCTUnwrap(FocusedEditableText(value: value,
            selection: NSRange(location: value.utf16.count, length: 0)))
        let rect = CGRect(x: 100, y: 180, width: 160, height: 20)
        let editor = CGRect(x: 90, y: 90, width: 600, height: 150)
        XCTAssertEqual(SystemAccessibilityReader.markerNodeLineEdgeCandidate(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: line,
            currentLineText: line, nodeBounds: rect, inputFrame: editor)?.rect, rect)
        XCTAssertNotNil(SystemAccessibilityReader.measuredNodeTextStyle(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: line,
            currentLineText: line, nodeBounds: rect, inputFrame: editor))
        // A suffix within a paragraph is not proof of a complete text line.
        XCTAssertNil(SystemAccessibilityReader.markerNodeLineEdgeCandidate(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: "todavía",
            currentLineText: "todavía", nodeBounds: rect, inputFrame: editor))
        XCTAssertNil(SystemAccessibilityReader.markerNodeLineEdgeCandidate(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: line,
            currentLineText: "no sale todavía", nodeBounds: rect, inputFrame: editor))
    }

    func testOwnedWrappedVisualLineUsesItsNumericRangeAndMeasuredGlyphs() throws {
        let value = "Primera línea larga. Segunda línea ñ🙂"
        let line = "Segunda línea ñ🙂"
        let focused = try XCTUnwrap(FocusedEditableText(value: value, selection: NSRange(location: value.utf16.count, length: 0)))
        let start = value.utf16.count - line.utf16.count
        var reads: [NSRange] = []
        let bounds = SystemAccessibilityReader.ownedVisualLineBounds(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: value,
            lineTextBefore: line, lineTextAfter: "", inputFrame: CGRect(x: 0, y: 0, width: 400, height: 100),
            readBounds: { range in
                reads.append(range)
                if range.length == line.utf16.count { return CGRect(x: 10, y: 40, width: 150, height: 20) }
                if range.location == start { return CGRect(x: 10, y: 40, width: 10, height: 20) }
                return CGRect(x: 140, y: 40, width: 20, height: 20)
            })
        XCTAssertEqual(bounds, CGRect(x: 10, y: 40, width: 150, height: 20))
        XCTAssertEqual(reads.first, NSRange(location: start, length: line.utf16.count))
        XCTAssertEqual(reads.last, NSRange(location: value.utf16.count - 2, length: 2))
    }

    func testWrappedLastParagraphUsesNodeLocalRangesAfterEarlierParagraphs() throws {
        let node = "Primera línea larga. Segunda línea ñ🙂"
        let line = "Segunda línea ñ🙂"
        let value = "Texto anterior🙂\n\n" + node
        let focused = try XCTUnwrap(FocusedEditableText(value: value,
            selection: NSRange(location: value.utf16.count, length: 0)))
        let start = node.utf16.count - line.utf16.count
        var reads: [NSRange] = []
        let bounds = SystemAccessibilityReader.ownedVisualLineBounds(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: node,
            lineTextBefore: line, lineTextAfter: "", inputFrame: CGRect(x: 0, y: 0, width: 400, height: 160),
            readBounds: { range in
                reads.append(range)
                if range == NSRange(location: start, length: line.utf16.count) {
                    return CGRect(x: 10, y: 100, width: 150, height: 20)
                }
                if range == NSRange(location: start, length: 1) {
                    return CGRect(x: 10, y: 100, width: 10, height: 20)
                }
                if range == NSRange(location: node.utf16.count - 2, length: 2) {
                    return CGRect(x: 140, y: 100, width: 20, height: 20)
                }
                return nil
            })
        XCTAssertEqual(bounds, CGRect(x: 10, y: 100, width: 150, height: 20))
        XCTAssertEqual(reads.first, NSRange(location: start, length: line.utf16.count))
        XCTAssertEqual(reads.last, NSRange(location: node.utf16.count - 2, length: 2))
    }

    func testWrappedNodeCannotBorrowCoordinatesFromAnArbitrarySuffix() throws {
        let value = "First line. Second line"
        let focused = try XCTUnwrap(FocusedEditableText(value: value,
            selection: NSRange(location: value.utf16.count, length: 0)))
        var reads = 0
        XCTAssertNil(SystemAccessibilityReader.ownedVisualLineBounds(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: "Second line",
            lineTextBefore: "line", lineTextAfter: "", inputFrame: CGRect(x: 0, y: 0, width: 400, height: 100),
            readBounds: { _ in reads += 1; return CGRect(x: 10, y: 10, width: 40, height: 20) }))
        XCTAssertEqual(reads, 0)
    }

    func testOwnedVisualLineRejectsUnrelatedTextAndBlockBounds() throws {
        let value = "First line. Second line"
        let focused = try XCTUnwrap(FocusedEditableText(value: value, selection: NSRange(location: value.utf16.count, length: 0)))
        var reads = 0
        XCTAssertNil(SystemAccessibilityReader.ownedVisualLineBounds(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: "Other conversation",
            lineTextBefore: "Second line", lineTextAfter: "", inputFrame: CGRect(x: 0, y: 0, width: 400, height: 100),
            readBounds: { _ in reads += 1; return CGRect(x: 10, y: 10, width: 300, height: 60) }))
        XCTAssertEqual(reads, 0)
        XCTAssertNil(SystemAccessibilityReader.ownedVisualLineBounds(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: value,
            lineTextBefore: "Second line", lineTextAfter: "", inputFrame: CGRect(x: 0, y: 0, width: 400, height: 100),
            readBounds: { _ in CGRect(x: 10, y: 10, width: 300, height: 60) }))
    }

    func testMeasuredTextNodeInOneLineTallEditorRemainsAValidCaret() throws {
        let value = "A short reply"
        let focused = try XCTUnwrap(FocusedEditableText(value: value, selection: NSRange(location: value.utf16.count, length: 0)))
        let line = CGRect(x: 100, y: 200, width: 110, height: 22)
        let editor = CGRect(x: 100, y: 200, width: 700, height: 22)
        let candidate = SystemAccessibilityReader.markerNodeLineEdgeCandidate(
            focusedText: focused, nodeRole: "AXStaticText", nodeText: value, currentLineText: value,
            nodeBounds: line, inputFrame: editor
        )
        XCTAssertEqual(candidate, CaretGeometryCandidate(rect: line, source: .lineEnd))
    }

    func testEditorAndGroupBoundsNeverMasqueradeAsTextEvenWhenTheyFit() throws {
        let value = "A short reply"
        let focused = try XCTUnwrap(FocusedEditableText(value: value, selection: NSRange(location: value.utf16.count, length: 0)))
        for role: String? in ["AXTextArea", "AXGroup", nil] {
            XCTAssertNil(SystemAccessibilityReader.markerNodeLineEdgeCandidate(
                focusedText: focused, nodeRole: role, nodeText: value, currentLineText: value,
                nodeBounds: CGRect(x: 100, y: 200, width: 110, height: 22),
                inputFrame: CGRect(x: 100, y: 200, width: 700, height: 60)
            ))
        }
    }

    func testMarkerNodeFrameProvidesTerminalLineGeometryWhenRangeBoundsAreInvalid() throws {
        let focused = try XCTUnwrap(FocusedEditableText(
            value: "hola codex funciona ",
            selection: NSRange(location: 20, length: 0)
        ))

        let candidate = SystemAccessibilityReader.markerNodeLineEdgeCandidate(
            focusedText: focused,
            nodeRole: "AXStaticText",
            nodeText: "hola codex funciona ",
            currentLineText: "hola codex funciona ",
            nodeBounds: CGRect(x: 571, y: 984, width: 175, height: 22),
            inputFrame: CGRect(x: 571, y: 982, width: 926, height: 58)
        )

        XCTAssertEqual(
            candidate,
            CaretGeometryCandidate(
                rect: CGRect(x: 571, y: 984, width: 175, height: 22),
                source: .lineEnd
            )
        )
    }

    func testMarkerNodeFrameCannotPoseAsOneLineWhenMarkerTextShowsSoftWrap() throws {
        let value = "a long value that wraps onto a second visual line"
        let focused = try XCTUnwrap(FocusedEditableText(
            value: value,
            selection: NSRange(location: value.utf16.count, length: 0)
        ))

        XCTAssertNil(SystemAccessibilityReader.markerNodeLineEdgeCandidate(
            focusedText: focused,
            nodeRole: "AXStaticText",
            nodeText: "a long value that wraps onto a second visual line",
            currentLineText: "second visual line",
            nodeBounds: CGRect(x: 571, y: 984, width: 400, height: 44),
            inputFrame: CGRect(x: 571, y: 982, width: 926, height: 58)
        ))
    }

    func testInvalidMarkerLinePrefersTheExactSelectedMarkerNodeFrame() {
        let measuredNode = CaretGeometryCandidate(
            rect: CGRect(x: 571, y: 984, width: 175, height: 22),
            source: .lineEnd
        )

        let candidate = SystemAccessibilityReader.terminalLineEdgeCandidate(
            lineBounds: CGRect(x: 566, y: 1044, width: 37, height: 37),
            lineTextBefore: "hola codex funciona ",
            lineTextAfter: "",
            markerNodeCandidate: measuredNode
        )

        XCTAssertEqual(candidate, measuredNode)
    }

    func testDetachedParagraphCannotDiscardAValidMeasuredWebLine() throws {
        let reader = FakeAccessibilityReader(webContent: true, text: nil, selection: nil)
        reader.webContext = WebTextContext(
            editableIdentifier: "fixture-editor", role: "AXTextArea", textBefore: "A short reply",
            frame: CGRect(x: 100, y: 200, width: 700, height: 22),
            caretCandidates: [.init(rect: CGRect(x: 100, y: 200, width: 110, height: 22), source: .lineEnd)],
            lineBounds: CGRect(x: 100, y: 200, width: 110, height: 22),
            paragraphBounds: CGRect(x: 90, y: 245, width: 50, height: 22),
            caretTextStyle: ActiveFieldTextStyle(fontName: "HelveticaNeue", fontSize: 15)
        )
        let snapshot = try XCTUnwrap(captured(reader))
        XCTAssertNotNil(snapshot.caretBounds)
        XCTAssertNotNil(snapshot.paragraphMetrics)
        XCTAssertNil(snapshot.paragraphMetricsFailureReason)
    }

    func testDetachedGlyphCannotSetHeightForAValidMeasuredWebLine() throws {
        let reader = FakeAccessibilityReader(webContent: true, text: nil, selection: nil)
        reader.webContext = WebTextContext(
            editableIdentifier: "fixture-editor", role: "AXTextArea", textBefore: "A short reply",
            frame: CGRect(x: 100, y: 200, width: 700, height: 22),
            caretCandidates: [
                .init(rect: CGRect(x: 90, y: 260, width: 37, height: 37), source: .followingGrapheme),
                .init(rect: CGRect(x: 100, y: 200, width: 110, height: 22), source: .lineEnd),
            ],
            lineBounds: CGRect(x: 100, y: 200, width: 110, height: 22),
            caretTextStyle: ActiveFieldTextStyle(fontName: "HelveticaNeue", fontSize: 15)
        )
        let snapshot = try XCTUnwrap(captured(reader))
        XCTAssertNotNil(snapshot.caretBounds)
        XCTAssertEqual(snapshot.geometrySource, .lineEnd)
        XCTAssertEqual(snapshot.caretBounds?.minX, 210)
        XCTAssertEqual(snapshot.caretBounds?.height, 22)
        XCTAssertNotNil(snapshot.paragraphMetrics)
    }

    func testContainedWrongEdgeCannotHideValidMeasuredTerminalNode() {
        let node = CaretGeometryCandidate(rect: CGRect(x: 100, y: 200, width: 110, height: 22), source: .lineEnd)
        XCTAssertEqual(SystemAccessibilityReader.terminalLineEdgeCandidate(
            lineBounds: CGRect(x: 100, y: 200, width: 250, height: 22),
            lineTextBefore: "a reply with enough text", lineTextAfter: "",
            markerNodeCandidate: node
        ), node)
    }

    func testSelectedTerminalCandidateAlsoBecomesTheAuthoritativeLineBounds() {
        let candidate = CaretGeometryCandidate(
            rect: CGRect(x: 571, y: 984, width: 175, height: 22),
            source: .lineEnd
        )

        XCTAssertEqual(
            SystemAccessibilityReader.effectiveTerminalLineBounds(
                reportedLineBounds: CGRect(x: 566, y: 1044, width: 37, height: 37),
                selectedCandidate: candidate
            ),
            candidate.rect
        )
    }

    func testPlaceholderMarkersCannotEraseAuthoredFieldText() throws {
        // A stale marker range can look exactly like an empty placeholder,
        // while the authoritative field value and selection have advanced.
        for selection in [NSRange(location: 5, length: 0), NSRange(location: 0, length: 5), NSRange(location: 0, length: 0)] {
            let focusedText = try XCTUnwrap(FocusedEditableText(value: "Draft reply", selection: selection))
            XCTAssertFalse(SystemAccessibilityReader.isSyntheticWebPlaceholder(
                focusedText: focusedText,
                textBefore: "",
                selectedText: "",
                textAfter: "Write a reply",
                textBeforeFullLength: 0,
                currentLineText: "",
                zeroLengthBounds: CGRect(x: 50, y: 100, width: 900, height: 27),
                lineBounds: CGRect(x: 50, y: 100, width: 900, height: 27),
                elementFrame: CGRect(x: 50, y: 100, width: 900, height: 27)
            ))
        }
    }

    func testSyntheticPlaceholderIsDetectedFromEmptyLineAndInvalidCharacterGeometry() {
        XCTAssertTrue(
            SystemAccessibilityReader.isSyntheticWebPlaceholder(
                focusedText: FocusedEditableText(value: "placeholder-like value", selection: NSRange(location: 0, length: 0))!,
                textBefore: "",
                selectedText: "",
                textAfter: "placeholder-like value",
                textBeforeFullLength: 0,
                currentLineText: "",
                zeroLengthBounds: CGRect(x: 50, y: 100, width: 900, height: 27),
                lineBounds: CGRect(x: 50, y: 100, width: 900, height: 27),
                elementFrame: CGRect(x: 50, y: 100, width: 900, height: 27)
            )
        )
    }

    func testCodexEmptyComposerIsDetectedWhenNextMarkerDoesNotAdvance() {
        XCTAssertTrue(
            SystemAccessibilityReader.isSyntheticWebPlaceholder(
                focusedText: FocusedEditableText(value: String(repeating: "x", count: 12), selection: NSRange(location: 0, length: 0))!,
                textBefore: "",
                selectedText: "",
                textAfter: String(repeating: "x", count: 12),
                textBeforeFullLength: 0,
                currentLineText: "",
                zeroLengthBounds: CGRect(x: 571, y: 982, width: 926, height: 58),
                lineBounds: CGRect(x: 571, y: 982, width: 926, height: 58),
                elementFrame: CGRect(x: 571, y: 982, width: 926, height: 58)
            )
        )
    }

    func testCodexEmptyComposerIsDetectedWhenItsEmptyLineIsShorterThanTheEditor() {
        XCTAssertTrue(
            SystemAccessibilityReader.isSyntheticWebPlaceholder(
                focusedText: FocusedEditableText(value: String(repeating: "x", count: 12), selection: NSRange(location: 0, length: 0))!,
                textBefore: "",
                selectedText: "",
                textAfter: String(repeating: "x", count: 12),
                textBeforeFullLength: 0,
                currentLineText: "",
                zeroLengthBounds: CGRect(x: 394, y: 982, width: 474, height: 27),
                lineBounds: CGRect(x: 394, y: 982, width: 474, height: 27),
                elementFrame: CGRect(x: 394, y: 982, width: 474, height: 58)
            )
        )
    }

    func testRealTrailingTextIsNotMistakenForAPlaceholder() {
        XCTAssertFalse(
            SystemAccessibilityReader.isSyntheticWebPlaceholder(
                focusedText: FocusedEditableText(value: "real content", selection: NSRange(location: 0, length: 0))!,
                textBefore: "",
                selectedText: "",
                textAfter: "real content",
                textBeforeFullLength: 0,
                currentLineText: "real content",
                zeroLengthBounds: CGRect(x: 50, y: 100, width: 0, height: 18),
                lineBounds: CGRect(x: 50, y: 100, width: 88, height: 18),
                elementFrame: CGRect(x: 40, y: 80, width: 320, height: 40)
            )
        )
    }

    func testEmptyFieldStyleIsBoundToTheActualMarkerText() {
        let text = NSAttributedString(string: "P", attributes: [
            NSAttributedString.Key("AXFont"): ["AXFontName": "HelveticaNeue", "AXFontSize": 14] as NSDictionary
        ])
        XCTAssertEqual(SystemAccessibilityReader.markerTextStyle(from: text, expectedText: "Placeholder"),
                       ActiveFieldTextStyle(fontName: "HelveticaNeue", fontSize: 14))
        XCTAssertNil(SystemAccessibilityReader.markerTextStyle(from: text, expectedText: "Different node"))
        XCTAssertNil(SystemAccessibilityReader.markerTextStyle(from: text, expectedText: ""))
    }

    func testInsertionStyleReadsOnlyVerifiedLastCharacter() {
        let font = NSFont.systemFont(ofSize: 16, weight: .regular)
        let attributed = NSMutableAttributedString(string: "missing then x")
        attributed.addAttribute(.font, value: font, range: NSRange(location: attributed.length - 1, length: 1))
        XCTAssertNil(SystemAccessibilityReader.textStyleRuns(from: attributed))
        let style = SystemAccessibilityReader.insertionTextStyle(from: attributed, expectedText: attributed.string)
        XCTAssertEqual(style?.fontSize, 16)
        XCTAssertEqual(style?.fontName, font.fontName)
        XCTAssertNil(SystemAccessibilityReader.insertionTextStyle(from: attributed, expectedText: "other"))
    }

    func testSizeOnlyAccessibilityFontUsesTheSystemTypefaceAtTheMeasuredSize() {
        let attributed = NSAttributedString(
            string: "p",
            attributes: [
                NSAttributedString.Key("AXFont"): ["AXFontSize": 14] as NSDictionary,
            ]
        )

        XCTAssertEqual(
            SystemAccessibilityReader.textStyleRuns(from: attributed)?.first?.style,
            ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 14)
        )
    }

    func testWebTypographyCalibrationAppliesTheRenderedWordScaleMissingFromAXFontSize() throws {
        let reported = ActiveFieldTextStyle(
            fontName: ".AppleSystemUIFont",
            fontSize: 14
        )

        let calibrated = try XCTUnwrap(
            SystemAccessibilityReader.webCalibratedTextStyle(
                reported,
                sampleText: "porque",
                sampleBounds: CGRect(x: 40, y: 100, width: 65, height: 24),
                currentLineBounds: CGRect(x: 40, y: 100, width: 140, height: 24),
                caretBounds: CGRect(x: 105, y: 100, width: 0, height: 24),
                fieldBounds: CGRect(x: 20, y: 80, width: 300, height: 80)
            )
        )

        XCTAssertEqual(calibrated.fontName, ".AppleSystemUIFont")
        XCTAssertEqual(calibrated.fontSize, 19.9, accuracy: 0.15)
    }

    func testWebTypographyRejectsUncorroboratedSampleGeometry() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 14)
        let line = CGRect(x: 40, y: 100, width: 140, height: 24)
        let caret = CGRect(x: 105, y: 100, width: 0, height: 24)
        let field = CGRect(x: 20, y: 80, width: 300, height: 80)
        let valid = CGRect(x: 40, y: 100, width: 65, height: 24)
        let cases: [(CGRect?, CGRect?, CGRect?, CGRect?)] = [
            (nil, line, caret, field),
            (.zero, line, caret, field),
            (CGRect(x: 40, y: 100, width: 65, height: 48), line, caret, field),
            (CGRect(x: 40, y: 124, width: 65, height: 24), line, caret, field),
            (CGRect(x: 400, y: 100, width: 65, height: 24), line, caret, field),
            (CGRect(x: 20, y: 100, width: 65, height: 24), line, caret, field),
            (CGRect(x: 40, y: 100, width: CGFloat.infinity, height: 24), line, caret, field),
            (valid, nil, caret, field),
            (valid, CGRect(x: 40, y: 100, width: 140, height: 48), caret, field),
            (valid, line, nil, field),
            (valid, line, caret, nil),
        ]
        for (sample, currentLine, currentCaret, currentField) in cases {
            XCTAssertEqual(SystemAccessibilityReader.webCalibratedTextStyle(
                style, sampleText: "porque", sampleBounds: sample,
                currentLineBounds: currentLine, caretBounds: currentCaret, fieldBounds: currentField
            ), style)
        }
    }

    func testWebTypographyPreservesValidZoomAtRTLAndNegativeDisplayOrigins() throws {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 14)
        let sample = "العربية"
        let width = (sample as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width * 1.5
        let calibrated = try XCTUnwrap(SystemAccessibilityReader.webCalibratedTextStyle(
            style, sampleText: sample,
            sampleBounds: CGRect(x: -300, y: -200, width: width, height: 24),
            currentLineBounds: CGRect(x: -400, y: -200, width: 250, height: 24),
            caretBounds: CGRect(x: -300, y: -200, width: 0, height: 24),
            fieldBounds: CGRect(x: -450, y: -220, width: 400, height: 80)
        ))
        XCTAssertEqual(calibrated.fontSize, 21, accuracy: 0.01)
    }

    func testAccessibilityForegroundColorIsCapturedWithTheFontStyle() throws {
        let foreground = try XCTUnwrap(
            CGColor(
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: [0.13, 0.24, 0.35, 1]
            )
        )
        let attributed = NSAttributedString(
            string: "p",
            attributes: [
                NSAttributedString.Key("AXFont"): ["AXFontSize": 14] as NSDictionary,
                NSAttributedString.Key("AXForegroundColor"): foreground,
            ]
        )

        let style = try XCTUnwrap(
            SystemAccessibilityReader.textStyleRuns(from: attributed)?.first?.style
        )

        XCTAssertEqual(
            style.foregroundColor,
            ActiveFieldTextColor(red: 0.13, green: 0.24, blue: 0.35, alpha: 1)
        )
    }










    func testSystemReaderUsesPlainDefaultsForMissingParagraphStyleAndRejectsNativeLists() {
        let font: NSDictionary = [
            "AXFontName": ".AppleSystemUIFont",
            "AXFontSize": 13,
        ]
        let missingStyle = NSAttributedString(
            string: "plain",
            attributes: [NSAttributedString.Key("AXFont"): font]
        )
        XCTAssertEqual(
            SystemAccessibilityReader.paragraphAttributes(from: missingStyle),
            .plain
        )

        let style = NSMutableParagraphStyle()
        style.headIndent = 18
        let nativeList = NSAttributedString(
            string: "item",
            attributes: [
                .paragraphStyle: style,
                NSAttributedString.Key("AXListItemPrefix"): "•",
                NSAttributedString.Key("AXListItemLevel"): 0,
            ]
        )
        XCTAssertNil(
            SystemAccessibilityReader.paragraphAttributes(from: nativeList)
        )
    }

    func testSystemReaderRejectsWrongTypedListMetadataByRawPresence() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let wrongTypedPrefix = NSAttributedString(
            string: "item",
            attributes: [
                .paragraphStyle: paragraph,
                NSAttributedString.Key("AXListItemPrefix"): NSNumber(value: 1),
            ]
        )
        let wrongTypedLevel = NSAttributedString(
            string: "item",
            attributes: [
                .paragraphStyle: paragraph,
                NSAttributedString.Key("AXListItemLevel"): "zero",
            ]
        )

        XCTAssertNil(
            SystemAccessibilityReader.paragraphAttributes(from: wrongTypedPrefix)
        )
        XCTAssertNil(
            SystemAccessibilityReader.paragraphAttributes(from: wrongTypedLevel)
        )
    }

    func testSystemReaderRejectsMixedExplicitParagraphStyles() {
        let first = NSMutableParagraphStyle()
        first.tailIndent = -12
        let second = NSMutableParagraphStyle()
        second.tailIndent = -24
        let attributed = NSMutableAttributedString(
            string: "first second",
            attributes: [.paragraphStyle: first]
        )
        attributed.addAttribute(
            .paragraphStyle,
            value: second,
            range: NSRange(location: 6, length: 6)
        )

        XCTAssertNil(
            SystemAccessibilityReader.paragraphAttributes(from: attributed)
        )
    }

    func testFiniteCaretOutsideInputFrameIsUnavailable() {
        let reader = FakeAccessibilityReader(text: "note", selection: NSRange(location: 4, length: 0), bounds: CGRect(x: 900, y: 700, width: 0, height: 18), inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240))
        let snapshot = captured(reader)
        XCTAssertNil(snapshot?.caretBounds)
        XCTAssertEqual(snapshot?.geometryQuality, .unavailable)
        XCTAssertNil(snapshot?.geometrySource)
    }






    func testPillOutlierCannotDonateItsXToPrecedingGraphemeGeometry() {
        let reader = FakeAccessibilityReader(text: "note", selection: NSRange(location: 4, length: 0), bounds: CGRect(x: 340, y: 700, width: 0, height: 18), boundsByRange: [NSRange(location: 3, length: 1): CGRect(x: 112, y: 100, width: 8, height: 18)], inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240))
        let snapshot = captured(reader)
        XCTAssertEqual(snapshot?.caretBounds, CGRect(x: 120, y: 682, width: 0, height: 18))
        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
        XCTAssertEqual(snapshot?.geometryQuality, .derived)
    }

    func testFollowingGraphemeProvidesGeometryAtFieldStartForUnicode() {
        for text in ["👋🏽 note", "éclair", "日本語", "שלום"] {
            let first = text.index(after: text.startIndex)
            let utf16Length = NSRange(text.startIndex..<first, in: text).length
            let reader = FakeAccessibilityReader(text: text, selection: NSRange(location: 0, length: 0), bounds: nil, boundsByRange: [NSRange(location: 0, length: utf16Length): CGRect(x: 72, y: 100, width: 20, height: 18)], inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240))
            let snapshot = captured(reader)
            XCTAssertEqual(snapshot?.caretBounds?.minX, text == "שלום" ? 92 : 72, text)
            XCTAssertEqual(snapshot?.geometrySource, .followingGrapheme, text)
        }
    }

    func testPrecedingCompoundEmojiUsesItsCompleteUTF16Range() {
        let text = "go 👋🏽"
        let emojiRange = NSRange(location: 3, length: 4)
        let reader = FakeAccessibilityReader(
            text: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            bounds: CGRect(x: 900, y: 700, width: 0, height: 18),
            boundsByRange: [emojiRange: CGRect(x: 112, y: 100, width: 20, height: 18)],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        let snapshot = captured(reader)
        XCTAssertTrue(reader.requestedRanges.contains(emojiRange))
        XCTAssertEqual(snapshot?.caretBounds?.minX, 132)
        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
    }

    func testPrecedingCandidateUsesNearestStrongDirectionBeforeCaret() {
        let reader = FakeAccessibilityReader(
            text: "abc العربية",
            selection: NSRange(location: 3, length: 0),
            bounds: nil,
            boundsByRange: [
                NSRange(location: 2, length: 1): CGRect(x: 100, y: 100, width: 20, height: 18),
                NSRange(location: 3, length: 1): CGRect(x: 120, y: 100, width: 8, height: 18),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.caretBounds?.minX, 120)
        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
    }

    func testFollowingCandidateUsesNearestStrongDirectionAtParagraphStart() {
        let reader = FakeAccessibilityReader(
            text: "العربية ABC",
            selection: NSRange(location: 0, length: 0),
            bounds: nil,
            boundsByRange: [
                NSRange(location: 0, length: 1): CGRect(x: 100, y: 100, width: 20, height: 18),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.caretBounds?.minX, 120)
        XCTAssertEqual(snapshot?.geometrySource, .followingGrapheme)
    }

    func testAdjacentStrongDirectionAfterNeutralSpaceWinsAtBidiRunStart() {
        let reader = FakeAccessibilityReader(
            text: "abc العربية",
            selection: NSRange(location: 4, length: 0),
            bounds: nil,
            boundsByRange: [
                NSRange(location: 4, length: 1): CGRect(x: 100, y: 100, width: 20, height: 18),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.caretBounds?.minX, 120)
        XCTAssertEqual(snapshot?.geometrySource, .followingGrapheme)
        XCTAssertEqual(snapshot?.geometryQuality, .derived)
    }

    func testNearestStrongDirectionsSeparatedByNeutralCharactersMustAgree() {
        let reader = FakeAccessibilityReader(
            text: "abc  العربية",
            selection: NSRange(location: 4, length: 0),
            bounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            boundsByRange: [
                NSRange(location: 3, length: 1): CGRect(x: 112, y: 100, width: 8, height: 18),
                NSRange(location: 4, length: 1): CGRect(x: 120, y: 100, width: 8, height: 18),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertNil(snapshot?.caretBounds)
        XCTAssertEqual(snapshot?.geometryQuality, .unavailable)
        XCTAssertNil(snapshot?.geometrySource)
    }

    func testConflictingStrongDirectionsAtRunBoundaryAreUnavailable() {
        let reader = FakeAccessibilityReader(
            text: "abcالعربية",
            selection: NSRange(location: 3, length: 0),
            bounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            boundsByRange: [
                NSRange(location: 2, length: 1): CGRect(x: 120, y: 100, width: 20, height: 18),
                NSRange(location: 3, length: 1): CGRect(x: 100, y: 100, width: 20, height: 18),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertNil(snapshot?.caretBounds)
        XCTAssertEqual(snapshot?.geometryQuality, .unavailable)
        XCTAssertNil(snapshot?.geometrySource)
    }


    func testCapturesTextEditWithTheSameUnicodeAndGeometryContract() {
        let text = "Hello 👋🏽 café 日本語 שלום"
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.apple.TextEdit",
            text: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            bounds: CGRect(x: 160, y: 120, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.applicationBundleIdentifier, "com.apple.TextEdit")
        XCTAssertEqual(snapshot?.textBefore, text)
        XCTAssertEqual(snapshot?.geometryQuality, .exact)
    }







    func testUnsupportedRoleIsBlockedBeforeReadingTextOrBounds() {
        let reader = FakeAccessibilityReader(
            role: kAXButtonRole as String,
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )

        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(
            CaptureConfiguration.enabled
        )
        XCTAssertEqual(capture.capture(), .skipped(.unsupportedRole))
        XCTAssertEqual(reader.stringValueReadCount, 0)
        XCTAssertEqual(reader.boundsReadCount, 0)
    }

    func testCapturesUnicodeContextUsingAccessibilityUTF16Ranges() {
        let text = "Hi 👋🏽 café 日本語 שלום"
        let selected = "café 日本語"
        let snapshot = captured(FakeAccessibilityReader(text: text, selection: (text as NSString).range(of: selected)))
        XCTAssertEqual(snapshot?.textBefore, "Hi 👋🏽 ")
        XCTAssertEqual(snapshot?.selectedText, selected)
        XCTAssertEqual(snapshot?.textAfter, " שלום")
    }

    func testCapturesStyleAndConvertsFieldAndParagraphGeometry() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let reader = FakeAccessibilityReader(text: "older\ncurrent", selection: NSRange(location: 13, length: 0), bounds: CGRect(x: 128, y: 180, width: 0, height: 16), boundsByRange: [NSRange(location: 12, length: 1): CGRect(x: 120, y: 180, width: 8, height: 16), NSRange(location: 6, length: 1): CGRect(x: 72, y: 180, width: 8, height: 16)], textStyle: style, inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220))
        let snapshot = captured(reader)
        XCTAssertEqual(snapshot?.textStyle, style)
        XCTAssertEqual(snapshot?.inputFrame, CGRect(x: 40, y: 500, width: 360, height: 220))
        XCTAssertEqual(snapshot?.paragraphStartBounds, CGRect(x: 72, y: 604, width: 8, height: 16))
    }

    func testKeepsParagraphMetricsWhenTheScrollableFieldExtendsPastTheDisplay() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let reader = FakeAccessibilityReader(
            text: "current",
            selection: NSRange(location: 7, length: 0),
            bounds: CGRect(x: 128, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 6, length: 1): CGRect(x: 120, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1): CGRect(x: 72, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 7), style: style),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 900)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.inputFrame, CGRect(x: 40, y: -180, width: 360, height: 900))
        XCTAssertNotNil(snapshot?.paragraphMetrics)
        XCTAssertNil(snapshot?.paragraphMetricsFailureReason)
    }

    func testCapturesOnlyCompleteUniformMeasuredParagraphMetrics() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let attributes = ActiveFieldParagraphAttributes(
            firstLineHeadIndent: 12,
            headIndent: 18,
            tailIndent: 0,
            lineSpacing: 0,
            paragraphSpacingBefore: 0,
            paragraphSpacingAfter: 0,
            tabStops: [28]
        )
        let reader = FakeAccessibilityReader(
            text: "older\ncurrent",
            selection: NSRange(location: 13, length: 0),
            bounds: CGRect(x: 128, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 12, length: 1): CGRect(x: 120, y: 180, width: 8, height: 16),
                NSRange(location: 6, length: 1): CGRect(x: 72, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 7), style: style),
            ],
            paragraphAttributes: attributes,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        let metrics = captured(reader)?.paragraphMetrics

        XCTAssertEqual(metrics?.textBeforeCaret, "current")
        XCTAssertEqual(metrics?.origin, CGPoint(x: 60, y: 620))
        XCTAssertEqual(metrics?.width, 340)
        XCTAssertEqual(metrics?.lineHeight, 16)
        XCTAssertEqual(metrics?.writingDirection, .leftToRight)
        XCTAssertEqual(metrics?.textStyle, style)
        XCTAssertEqual(metrics?.attributes, attributes)
    }

    func testWrappedNativeParagraphUsesMeasuredCaretLineFillInsteadOfAccumulatedPrefixWidth() {
        let text = "A sufficiently long Notes paragraph that already wrapped"
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let reader = FakeAccessibilityReader(
            text: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            bounds: CGRect(x: 150, y: 118, width: 0, height: 18),
            boundsByRange: [
                NSRange(location: text.utf16.count - 1, length: 1):
                    CGRect(x: 142, y: 118, width: 8, height: 18),
                NSRange(location: 0, length: 1):
                    CGRect(x: 72, y: 100, width: 8, height: 18),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: text.utf16.count), style: style),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let metrics = captured(reader)?.paragraphMetrics

        XCTAssertEqual(metrics?.textBeforeCaret, "")
        XCTAssertEqual(metrics?.origin, CGPoint(x: 72, y: 682))
        XCTAssertEqual(metrics?.width, 328)
        XCTAssertEqual(metrics?.insertionLineHeadIndent, 78)
        XCTAssertEqual(metrics?.textStyle, style)
        XCTAssertEqual(metrics?.typographyIsEstimated, false)
    }

    func testNativeRightToLeftParagraphUsesMeasuredCaretLineFillInsteadOfBidiReflow() {
        let text = "השלב הבא הוא "
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let reader = FakeAccessibilityReader(
            text: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            bounds: CGRect(x: 900, y: 700, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: text.utf16.count - 1, length: 1):
                    CGRect(x: 172, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1):
                    CGRect(x: 320, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: fullRange, style: style),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        let snapshot = captured(reader)
        let metrics = snapshot?.paragraphMetrics

        XCTAssertNil(snapshot?.paragraphMetricsFailureReason)
        XCTAssertEqual(snapshot?.geometryQuality, .derived)
        XCTAssertEqual(snapshot?.geometryStructure?.direction, .rightToLeft)
        XCTAssertEqual(metrics?.writingDirection, .rightToLeft)
        XCTAssertEqual(metrics?.textBeforeCaret, "")
        XCTAssertEqual(metrics?.origin, CGPoint(x: 40, y: 620))
        XCTAssertEqual(metrics?.width, 288)
        XCTAssertEqual(metrics?.insertionLineHeadIndent, 156)
        XCTAssertEqual(metrics?.textStyle, style)
        XCTAssertEqual(metrics?.typographyIsEstimated, false)
    }

    func testNativeDerivedCaretUsesMeasuredLineFillIndependentOfWritingDirection() {
        let text = "current "
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let reader = FakeAccessibilityReader(
            text: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            bounds: CGRect(x: 900, y: 700, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: text.utf16.count - 1, length: 1):
                    CGRect(x: 120, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1):
                    CGRect(x: 72, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(
                    range: NSRange(location: 0, length: text.utf16.count),
                    style: style
                ),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        let snapshot = captured(reader)
        let metrics = snapshot?.paragraphMetrics

        XCTAssertEqual(snapshot?.geometryQuality, .derived)
        XCTAssertEqual(metrics?.writingDirection, .leftToRight)
        XCTAssertEqual(metrics?.textBeforeCaret, "")
        XCTAssertEqual(metrics?.origin, CGPoint(x: 72, y: 620))
        XCTAssertEqual(metrics?.width, 328)
        XCTAssertEqual(metrics?.insertionLineHeadIndent, 56)
        XCTAssertEqual(metrics?.textStyle, style)
    }

    func testMixedStyleParagraphStillProducesMirrorMetrics() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let mixed = ActiveFieldTextStyle(fontName: "Menlo-Regular", fontSize: 13)
        let mixedReader = FakeAccessibilityReader(
            text: "mixed style",
            selection: NSRange(location: 11, length: 0),
            bounds: CGRect(x: 140, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 10, length: 1): CGRect(x: 132, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1): CGRect(x: 72, y: 180, width: 8, height: 16),
            ],
            textStyle: mixed,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 6), style: style),
                .init(range: NSRange(location: 6, length: 5), style: mixed),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        let metrics = captured(mixedReader)?.paragraphMetrics

        XCTAssertEqual(metrics?.textStyle, mixed)
        XCTAssertEqual(metrics?.prefixStyleRuns, [
            .init(range: NSRange(location: 0, length: 6), style: style),
            .init(range: NSRange(location: 6, length: 5), style: mixed),
        ])
    }

    func testUnavailableParagraphMetricsExposeOnlyTheirStructuralFailureReason() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        // The paragraph start sits left of the field frame: contradictory
        // geometry stays silent instead of falling back to a line fill.
        let reader = FakeAccessibilityReader(
            text: "current",
            selection: NSRange(location: 7, length: 0),
            bounds: CGRect(x: 128, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 6, length: 1): CGRect(x: 120, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1): CGRect(x: 20, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 7), style: style),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        let snapshot = captured(reader)

        XCTAssertNil(snapshot?.paragraphMetrics)
        XCTAssertEqual(snapshot?.paragraphMetricsFailureReason, .boundsInvalid)
    }

    func testListOrTruncatedParagraphDoesNotProduceMirrorMetrics() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)

        var nativeList = ActiveFieldParagraphAttributes.plain
        nativeList.listMarker = "•"
        nativeList.listLevel = 0
        let listReader = FakeAccessibilityReader(
            text: "list item",
            selection: NSRange(location: 9, length: 0),
            bounds: CGRect(x: 140, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 8, length: 1): CGRect(x: 132, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1): CGRect(x: 72, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 9), style: style),
            ],
            paragraphAttributes: nativeList,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )
        XCTAssertNil(captured(listReader)?.paragraphMetrics)

        let longText = String(repeating: "a", count: 2_001)
        let longReader = FakeAccessibilityReader(
            text: longText,
            selection: NSRange(location: 2_001, length: 0),
            bounds: CGRect(x: 128, y: 180, width: 0, height: 16),
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 2_001), style: style),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )
        XCTAssertNil(captured(longReader)?.paragraphMetrics)
    }

    func testContradictoryMeasuredLineHeightsDoNotProduceMirrorMetrics() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let reader = FakeAccessibilityReader(
            text: "current",
            selection: NSRange(location: 7, length: 0),
            bounds: CGRect(x: 128, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 6, length: 1): CGRect(x: 120, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1): CGRect(x: 72, y: 172, width: 8, height: 24),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 7), style: style),
            ],
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        XCTAssertNil(captured(reader)?.paragraphMetrics)
    }

    func testFocusGenerationAndCaptureSequenceAreMonotonic() {
        let reader = FakeAccessibilityReader(text: "note", selection: NSRange(location: 4, length: 0))
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(
            CaptureConfiguration.enabled
        )
        guard case let .captured(first) = capture.capture(), case let .captured(second) = capture.capture() else { return XCTFail("Expected captures") }
        reader.element = AccessibilityElement(identifier: "notes-field-2")
        guard case let .captured(third) = capture.capture() else { return XCTFail("Expected capture") }
        XCTAssertEqual([first.focusGeneration, second.focusGeneration, third.focusGeneration], [1, 1, 2])
        XCTAssertEqual([first.captureSequence, second.captureSequence, third.captureSequence], [1, 2, 3])
    }

    func testCachesWebCapabilityForTheFocusedElementOnly() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.browser",
            webContent: true,
            text: "note",
            selection: NSRange(location: 4, length: 0)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        _ = capture.capture()
        _ = capture.capture()
        XCTAssertEqual(reader.webCapabilityReadCount, 1)

        reader.element = AccessibilityElement(identifier: "notes-field-2")
        _ = capture.capture()
        XCTAssertEqual(reader.webCapabilityReadCount, 2)
    }

    func testReprobesANegativeWebCapabilityForTheSameLazyElement() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.browser",
            webContent: false,
            text: "draft",
            selection: NSRange(location: 5, length: 0)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        guard case let .captured(first) = capture.capture() else {
            return XCTFail("Expected native capture")
        }
        XCTAssertEqual(first.surface, .native)

        reader.webContent = true
        reader.webContext = WebTextContext(
            editableIdentifier: "lazy-editor",
            role: kAXTextAreaRole as String,
            textBefore: "draft",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(
                    rect: CGRect(x: 100, y: 100, width: 9, height: 18),
                    source: .precedingGrapheme
                ),
            ]
        )

        guard case let .captured(second) = capture.capture() else {
            return XCTFail("Expected web capture after the lazy bridge appears")
        }
        XCTAssertEqual(second.surface, .web)
        XCTAssertEqual(reader.webCapabilityReadCount, 2)
    }

    func testClassifiesAStaleSelectionAgainstNewlyPublishedValueWithoutContent() {
        let reader = FakeAccessibilityReader(
            text: "line\nPrueba",
            selection: NSRange(location: 5, length: 0)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(
            snapshot?.publicationStructure,
            ActiveFieldPublicationStructure(
                selectionPosition: .middle,
                selectionCollapsed: true,
                textBeforeTerminal: .newline,
                textAfterIsEmpty: false,
                valueTerminal: .letter
            )
        )
    }

    func testFinalTypedGlyphDerivesCaretWhenZeroLengthBoundsDisappear() {
        let reader = FakeAccessibilityReader(
            text: "\nA",
            selection: NSRange(location: 2, length: 0),
            bounds: nil,
            boundsByRange: [
                NSRange(location: 1, length: 1): CGRect(
                    x: 120,
                    y: 100,
                    width: 9,
                    height: 18
                ),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.geometryQuality, .derived)
        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
        XCTAssertEqual(snapshot?.caretBounds?.minX, 129)
        XCTAssertEqual(
            snapshot?.geometryStructure,
            ActiveFieldGeometryStructure(
                inputFrameAvailable: true,
                direction: .leftToRight,
                zeroLengthBounds: .missing,
                precedingGlyphBounds: .available,
                followingGlyphBounds: .missing,
                displayMatched: true,
                resolverOutcome: .resolved,
                paragraphStartAvailable: true
            )
        )
    }

    func testFinalTypedUnicodeGlyphWinsOverStaleSameLineZeroRange() {
        let cases: [(text: String, glyphRange: NSRange, glyph: CGRect, expectedX: CGFloat)] = [
            ("\nA", NSRange(location: 1, length: 1), CGRect(x: 120, y: 100, width: 9, height: 18), 129),
            ("\nA👋🏽", NSRange(location: 2, length: 4), CGRect(x: 120, y: 100, width: 20, height: 18), 140),
            ("\n日", NSRange(location: 1, length: 1), CGRect(x: 120, y: 100, width: 18, height: 18), 138),
            ("\nא", NSRange(location: 1, length: 1), CGRect(x: 120, y: 100, width: 14, height: 18), 120),
        ]

        for item in cases {
            let caretRange = NSRange(location: item.text.utf16.count, length: 0)
            let reader = FakeAccessibilityReader(
                text: item.text,
                selection: caretRange,
                bounds: nil,
                boundsByRange: [
                    caretRange: CGRect(x: 220, y: 100, width: 0, height: 18),
                    item.glyphRange: item.glyph,
                ],
                inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
            )

            let snapshot = captured(reader)

            XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme, item.text)
            XCTAssertEqual(snapshot?.geometryQuality, .derived, item.text)
            XCTAssertEqual(snapshot?.caretBounds?.minX, item.expectedX, item.text)
        }
    }

    func testFinalTypedGlyphIgnoresConflictingZeroRangeAcrossSoftWrap() {
        let text = "\nA"
        let caretRange = NSRange(location: text.utf16.count, length: 0)
        let reader = FakeAccessibilityReader(
            text: text,
            selection: caretRange,
            bounds: nil,
            boundsByRange: [
                caretRange: CGRect(x: 48, y: 118, width: 0, height: 18),
                NSRange(location: 1, length: 1): CGRect(
                    x: 380,
                    y: 100,
                    width: 8,
                    height: 18
                ),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.caretBounds?.minX, 388)
        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
        XCTAssertEqual(snapshot?.geometryQuality, .derived)
        XCTAssertEqual(snapshot?.geometryStructure?.resolverOutcome, .resolved)
    }

    func testMiddleCaretUsesConsensusOfAdjacentUnicodeGlyphEdges() {
        let cases: [(
            text: String,
            selection: Int,
            precedingRange: NSRange,
            precedingBounds: CGRect,
            followingRange: NSRange,
            followingBounds: CGRect,
            expectedX: CGFloat
        )] = [
            (
                "AB",
                1,
                NSRange(location: 0, length: 1),
                CGRect(x: 100, y: 100, width: 10, height: 18),
                NSRange(location: 1, length: 1),
                CGRect(x: 110, y: 100, width: 10, height: 18),
                110
            ),
            (
                "A👋🏽B",
                5,
                NSRange(location: 1, length: 4),
                CGRect(x: 100, y: 100, width: 20, height: 18),
                NSRange(location: 5, length: 1),
                CGRect(x: 120, y: 100, width: 10, height: 18),
                120
            ),
            (
                "日本",
                1,
                NSRange(location: 0, length: 1),
                CGRect(x: 100, y: 100, width: 18, height: 18),
                NSRange(location: 1, length: 1),
                CGRect(x: 118, y: 100, width: 18, height: 18),
                118
            ),
            (
                "אב",
                1,
                NSRange(location: 0, length: 1),
                CGRect(x: 120, y: 100, width: 14, height: 18),
                NSRange(location: 1, length: 1),
                CGRect(x: 106, y: 100, width: 14, height: 18),
                120
            ),
        ]

        for item in cases {
            let caretRange = NSRange(location: item.selection, length: 0)
            let reader = FakeAccessibilityReader(
                text: item.text,
                selection: caretRange,
                bounds: nil,
                boundsByRange: [
                    caretRange: CGRect(x: 220, y: 100, width: 0, height: 18),
                    item.precedingRange: item.precedingBounds,
                    item.followingRange: item.followingBounds,
                ],
                inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
            )

            let snapshot = captured(reader)

            XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme, item.text)
            XCTAssertEqual(snapshot?.geometryQuality, .derived, item.text)
            XCTAssertEqual(snapshot?.caretBounds?.minX, item.expectedX, item.text)
        }
    }

    func testMiddleCaretAdjacentGlyphsAcrossSoftWrapRemainUnavailable() {
        let reader = FakeAccessibilityReader(
            text: "AB",
            selection: NSRange(location: 1, length: 0),
            bounds: nil,
            boundsByRange: [
                NSRange(location: 1, length: 0): CGRect(
                    x: 48,
                    y: 118,
                    width: 0,
                    height: 18
                ),
                NSRange(location: 0, length: 1): CGRect(
                    x: 380,
                    y: 100,
                    width: 8,
                    height: 18
                ),
                NSRange(location: 1, length: 1): CGRect(
                    x: 48,
                    y: 118,
                    width: 8,
                    height: 18
                ),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertNil(snapshot?.caretBounds)
        XCTAssertEqual(
            snapshot?.geometryStructure?.resolverOutcome,
            .failed(.conflictingCandidates)
        )
    }

    func testMiddleCaretAtMixedBidiBoundaryRemainsUnavailable() {
        let reader = FakeAccessibilityReader(
            text: "Aא",
            selection: NSRange(location: 1, length: 0),
            bounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            boundsByRange: [
                NSRange(location: 0, length: 1): CGRect(
                    x: 100,
                    y: 100,
                    width: 20,
                    height: 18
                ),
                NSRange(location: 1, length: 1): CGRect(
                    x: 120,
                    y: 100,
                    width: 20,
                    height: 18
                ),
            ],
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )

        let snapshot = captured(reader)

        XCTAssertNil(snapshot?.caretBounds)
        XCTAssertEqual(snapshot?.geometryStructure?.direction, .ambiguous)
        XCTAssertEqual(
            snapshot?.geometryStructure?.resolverOutcome,
            .failed(.noCandidates)
        )
    }

    func testBoundsContextWithoutSplittingGraphemes() {
        let before = String(repeating: "👋🏽", count: 2_001)
        let selected = String(repeating: "😀", count: 1_001)
        let after = String(repeating: "界", count: 2_001)
        let text = before + selected + after
        let snapshot = captured(FakeAccessibilityReader(text: text, selection: (text as NSString).range(of: selected)))
        XCTAssertLessThanOrEqual(snapshot?.textBefore.utf16.count ?? .max, 8_000)
        XCTAssertLessThanOrEqual(snapshot?.selectedText.utf16.count ?? .max, 2_000)
        XCTAssertLessThanOrEqual(snapshot?.textAfter.utf16.count ?? .max, 2_000)
    }

    func testSerializesConcurrentAccessibilityCaptures() {
        let reader = ConcurrentProbeReader()
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(
            CaptureConfiguration.enabled
        )
        DispatchQueue.concurrentPerform(iterations: 2) { _ in _ = capture.capture() }
        XCTAssertEqual(reader.maximumConcurrentReads, 1)
    }


    // MARK: - Capability-based eligibility

    func testCapturesUnknownNativeAndWebEditorsByAccessibilityCapability() {
        let native = FakeAccessibilityReader(
            bundleIdentifier: "com.example.Editor",
            text: "Draft",
            selection: NSRange(location: 5, length: 0),
            bounds: CGRect(x: 180, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        let web = FakeAccessibilityReader(
            bundleIdentifier: "org.mozilla.firefox",
            webContent: true,
            text: "must never be read through AXValue",
            selection: NSRange(location: 0, length: 0)
        )
        web.webContext = WebTextContext(
            editableIdentifier: "7:body",
            role: "AXTextArea",
            textBefore: "Draft",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 100, y: 100, width: 80, height: 18), source: .lineEnd),
            ],
            lineBounds: CGRect(x: 100, y: 100, width: 80, height: 18)
        )

        XCTAssertEqual(captured(native)?.surface, .native)
        let webSnapshot = captured(web)
        XCTAssertEqual(webSnapshot?.surface, .web)
        XCTAssertEqual(webSnapshot?.textBefore, "Draft")
        XCTAssertEqual(web.stringValueReadCount, 0)
        XCTAssertEqual(web.boundsReadCount, 0)
    }

    func testDisabledConfigurationNeverReadsTheFocusedElement() {
        let reader = FakeAccessibilityReader(
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.disabled)

        XCTAssertEqual(capture.capture(), .skipped(.unsupportedApplication))
        XCTAssertEqual(reader.focusReadCount, 0)
        XCTAssertEqual(reader.stringValueReadCount, 0)
    }

    func testSecureFieldsAreBlockedBeforeReadingText() {
        let secure = FakeAccessibilityReader(
            subrole: "AXSecureTextField",
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )
        let capture = ActiveFieldCapture(reader: secure)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.secureField))
        XCTAssertEqual(secure.stringValueReadCount, 0)
        XCTAssertEqual(secure.sourceReadCount, 0)
        XCTAssertEqual(secure.boundsReadCount, 0)

        let webPassword = FakeAccessibilityReader(
            bundleIdentifier: "com.apple.Safari",
            webContent: true,
            role: kAXTextFieldRole as String,
            subrole: kAXSecureTextFieldSubrole as String,
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )
        webPassword.webContext = WebTextContext(
            editableIdentifier: "9:password",
            role: kAXTextFieldRole as String,
            subrole: kAXSecureTextFieldSubrole as String,
            textBefore: "must never be read",
            frame: CGRect(x: 40, y: 60, width: 360, height: 32)
        )
        let webCapture = ActiveFieldCapture(reader: webPassword)
        webCapture.updateConfiguration(.enabled)
        XCTAssertEqual(webCapture.capture(), .skipped(.secureField))
        XCTAssertEqual(webPassword.webContextReadCount, 0)
    }

    func testOwnFrontmostProcessIsBlockedBeforeFocusOrBootstrapReads() {
        let reader = FakeAccessibilityReader(text: "Library entry", selection: NSRange(location: 0, length: 0))
        reader.frontmostPID = 4_242
        reader.focusedElementUnavailable = true
        let capture = ActiveFieldCapture(reader: reader, excludedProcessIdentifier: 4_242)
        capture.updateConfiguration(.enabled)
        XCTAssertEqual(capture.capture(), .skipped(.unsupportedApplication))
        XCTAssertEqual(reader.focusReadCount, 0)
        XCTAssertEqual(reader.frontmostWebAccessibilityPreparationCount, 0)
        XCTAssertEqual(reader.sourceReadCount, 0)
        XCTAssertEqual(reader.stringValueReadCount, 0)
    }

    func testOwnProcessIsBlockedBeforeReadingText() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.autocompletion.desktop",
            webContent: true,
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )
        reader.processIdentifier = 4_242
        let capture = ActiveFieldCapture(reader: reader, excludedProcessIdentifier: 4_242)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.unsupportedApplication))
        XCTAssertEqual(reader.webContextReadCount, 0)
        XCTAssertEqual(reader.stringValueReadCount, 0)
    }

    func testNativeSingleLineFieldsAreCapturedByCapability() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.Editor",
            webContent: false,
            role: kAXTextFieldRole as String,
            text: "Project",
            selection: NSRange(location: 7, length: 0),
            bounds: CGRect(x: 90, y: 80, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 320, height: 32)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        guard case let .captured(snapshot) = capture.capture() else {
            return XCTFail("Expected native single-line capture")
        }

        XCTAssertEqual(snapshot.textBefore, "Project")
        XCTAssertEqual(snapshot.fieldKind, .singleLine)
        XCTAssertEqual(reader.stringValueReadCount, 1)
    }

    func testNativeSearchFieldsAreBlockedBeforeReadingText() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.Editor",
            webContent: false,
            role: kAXTextFieldRole as String,
            subrole: "AXSearchField",
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        XCTAssertEqual(capture.capture(), .skipped(.unsupportedRole))
        XCTAssertEqual(reader.stringValueReadCount, 0)
    }

    func testWebSearchAndComboWidgetsAreBlockedBeforeReadingContext() {
        let search = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextFieldRole as String,
            subrole: "AXSearchField",
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )
        let combo = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXComboBoxRole as String,
            text: "must never be read",
            selection: NSRange(location: 0, length: 0)
        )
        for reader in [search, combo] {
            let capture = ActiveFieldCapture(reader: reader)
            capture.updateConfiguration(.enabled)
            XCTAssertEqual(capture.capture(), .skipped(.unsupportedRole))
            XCTAssertEqual(reader.webContextReadCount, 0)
            XCTAssertEqual(reader.stringValueReadCount, 0)
        }
    }

    func testTransientFocusReadFailureKeepsTheFocusGeneration() {
        let reader = FakeAccessibilityReader(
            text: "note",
            selection: NSRange(location: 4, length: 0)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        guard case let .captured(first) = capture.capture() else {
            return XCTFail("Expected first capture")
        }
        reader.focusedElementUnavailable = true
        XCTAssertEqual(capture.capture(), .skipped(.accessibilityUnavailable))
        reader.focusedElementUnavailable = false
        guard case let .captured(third) = capture.capture() else {
            return XCTFail("Expected recovered capture")
        }

        XCTAssertEqual(first.focusGeneration, third.focusGeneration)
        XCTAssertEqual(third.captureSequence, 3)
    }

    func testMissingFocusWarmsTheFrontmostWebTreeAndRetriesOnce() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.electron",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: "must never be read through AXValue",
            selection: NSRange(location: 0, length: 0)
        )
        reader.focusedElementFailuresRemaining = 1
        reader.webContext = WebTextContext(
            editableIdentifier: "680:composer",
            role: kAXTextAreaRole as String,
            textBefore: "En una interfaz confiable",
            frame: CGRect(x: 40, y: 60, width: 360, height: 120),
            caretCandidates: [
                .init(
                    rect: CGRect(x: 180, y: 100, width: 0, height: 18),
                    source: .zeroLengthRange
                ),
            ],
            lineBounds: CGRect(x: 40, y: 100, width: 140, height: 18)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        guard case let .captured(snapshot) = capture.capture() else {
            return XCTFail("Expected capture after warming the lazy web accessibility tree")
        }

        XCTAssertEqual(snapshot.elementIdentifier, "680:composer")
        XCTAssertEqual(reader.frontmostWebAccessibilityPreparationCount, 1)
        XCTAssertEqual(reader.focusReadCount, 2)
    }

    // MARK: - Web content through text markers

    func testWebCaptureUsesMarkerContextAndKeepsIdentityAcrossScrolling() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: "must never be read through AXValue",
            selection: NSRange(location: 0, length: 0)
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:body",
            role: kAXTextAreaRole as String,
            textBefore: "Hola mundo",
            textAfter: "",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 100, y: 100, width: 120, height: 18), source: .lineEnd),
            ],
            lineBounds: CGRect(x: 100, y: 100, width: 120, height: 18)
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)

        guard case let .captured(first) = capture.capture() else {
            return XCTFail("Expected web capture")
        }
        XCTAssertEqual(first.elementIdentifier, "665:body")
        XCTAssertEqual(first.surface, .web)
        XCTAssertEqual(first.fieldKind, .multiline)
        XCTAssertEqual(first.textBefore, "Hola mundo")
        XCTAssertEqual(first.selectionRange, NSRange(location: 10, length: 0))
        XCTAssertEqual(first.caretBounds, CGRect(x: 220, y: 682, width: 0, height: 18))
        XCTAssertEqual(first.geometrySource, .lineEnd)
        XCTAssertEqual(first.geometryQuality, .derived)
        XCTAssertEqual(first.geometryStructure?.lineEdgeBounds, .available)
        XCTAssertEqual(reader.stringValueReadCount, 0)
        XCTAssertEqual(reader.boundsReadCount, 0)

        // The field scrolls: frame and line move, identity and focus stay.
        reader.webContext = WebTextContext(
            editableIdentifier: "665:body",
            role: kAXTextAreaRole as String,
            textBefore: "Hola mundo",
            frame: CGRect(x: 40, y: 20, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 100, y: 60, width: 120, height: 18), source: .lineEnd),
            ],
            lineBounds: CGRect(x: 100, y: 60, width: 120, height: 18)
        )
        guard case let .captured(second) = capture.capture() else {
            return XCTFail("Expected scrolled capture")
        }
        XCTAssertEqual(second.elementIdentifier, first.elementIdentifier)
        XCTAssertEqual(second.focusGeneration, first.focusGeneration)
        XCTAssertEqual(second.contentSignature, first.contentSignature)
        XCTAssertEqual(second.caretBounds?.minY, 722)
    }

    func testWebCapturePreparesHostAccessibilityBeforeReadingMarkerGeometry() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextFieldRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:subject",
            role: kAXTextFieldRole as String,
            textBefore: "Draft",
            frame: CGRect(x: 40, y: 60, width: 360, height: 32),
            caretCandidates: [
                .init(rect: CGRect(x: 60, y: 66, width: 40, height: 18), source: .lineEnd),
            ]
        )

        _ = captured(reader)

        XCTAssertEqual(reader.webAccessibilityPreparationCount, 1)
        XCTAssertEqual(reader.webContextReadCount, 1)
    }

    func testWebCaptureChangesFocusGenerationBetweenTitleAndBodyFields() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextFieldRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:subject",
            role: kAXTextFieldRole as String,
            textBefore: "Subject",
            frame: CGRect(x: 40, y: 60, width: 360, height: 32),
            caretCandidates: [
                .init(rect: CGRect(x: 60, y: 66, width: 60, height: 18), source: .lineEnd),
            ]
        )
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)
        guard case let .captured(subject) = capture.capture() else {
            return XCTFail("Expected subject capture")
        }

        reader.role = kAXTextAreaRole as String
        reader.webContext = WebTextContext(
            editableIdentifier: "665:body",
            role: kAXTextAreaRole as String,
            textBefore: "Body",
            frame: CGRect(x: 40, y: 110, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 60, y: 120, width: 40, height: 18), source: .lineEnd),
            ]
        )
        guard case let .captured(body) = capture.capture() else {
            return XCTFail("Expected body capture")
        }

        XCTAssertEqual(subject.fieldKind, .singleLine)
        XCTAssertEqual(body.fieldKind, .multiline)
        XCTAssertNotEqual(subject.elementIdentifier, body.elementIdentifier)
        XCTAssertEqual(subject.focusGeneration + 1, body.focusGeneration)
    }

    func testWebLineGeometryDoesNotInventMissingTypography() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:body",
            role: kAXTextAreaRole as String,
            textBefore: "first line of the paragraph\nsecond",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 60, y: 100, width: 160, height: 18), source: .lineEnd),
            ],
            lineBounds: CGRect(x: 60, y: 100, width: 160, height: 18),
            paragraphBounds: CGRect(x: 60, y: 82, width: 250, height: 36),
            paragraphTextBefore: "second"
        )

        let snapshot = captured(reader)
        XCTAssertNil(snapshot?.paragraphMetrics)
        XCTAssertEqual(snapshot?.paragraphMetricsFailureReason, .styleRunsUnavailable)
        XCTAssertNotNil(snapshot?.caretBounds)
        XCTAssertNil(snapshot?.textStyle)
    }

    func testWebRightToLeftLineFillUsesTheMeasuredNearEdgeWhenTheRunIsLeftAligned() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "org.example.WebHost",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil,
            displays: [
                .init(
                    accessibilityFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                    appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
                ),
            ]
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "rtl-body",
            role: kAXTextAreaRole as String,
            textBefore: "سنتابع غدًا ",
            frame: CGRect(x: 442, y: 355, width: 882, height: 117),
            caretCandidates: [
                .init(
                    rect: CGRect(x: 457, y: 423, width: 8, height: 19),
                    source: .precedingGrapheme
                ),
            ],
            lineBounds: CGRect(x: 457, y: 423, width: 75, height: 19),
            paragraphBounds: CGRect(x: 457, y: 423, width: 75, height: 19),
            paragraphTextBefore: "سنتابع غدًا ",
            caretTextStyle: ActiveFieldTextStyle(fontName: "HelveticaNeue", fontSize: 15)
        )

        let snapshot = captured(reader)
        let metrics = snapshot?.paragraphMetrics

        XCTAssertNil(snapshot?.paragraphMetricsFailureReason)
        XCTAssertEqual(snapshot?.geometryStructure?.direction, .rightToLeft)
        XCTAssertEqual(metrics?.writingDirection, .rightToLeft)
        XCTAssertEqual(metrics?.origin.x, 457)
        XCTAssertEqual(metrics?.width, 852)
        XCTAssertEqual(metrics?.insertionLineHeadIndent, 852)
    }

    func testWebMeasuredStyleUsesCaretAnchoredLineFillInsteadOfReconstructingHostPrefix() {
        let style = ActiveFieldTextStyle(
            fontName: ".WebKitUnresolvableSystemAlias",
            fontSize: 17
        )
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.apple.Safari",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "42:textarea",
            role: kAXTextAreaRole as String,
            textBefore: "prefix",
            frame: CGRect(x: 40, y: 80, width: 360, height: 220),
            caretCandidates: [
                .init(rect: CGRect(x: 100, y: 180, width: 9, height: 18), source: .precedingGrapheme),
            ],
            lineBounds: CGRect(x: 53, y: 180, width: 56, height: 18),
            paragraphBounds: CGRect(x: 53, y: 180, width: 56, height: 18),
            paragraphTextBefore: "prefix",
            paragraphStyleRuns: [
                .init(range: NSRange(location: 0, length: 6), style: style),
            ],
            paragraphAttributes: .plain
        )

        let snapshot = captured(reader)
        let metrics = snapshot?.paragraphMetrics

        XCTAssertEqual(snapshot?.caretBounds?.minX, 109)
        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
        XCTAssertEqual(metrics?.textBeforeCaret, "")
        XCTAssertEqual(metrics?.prefixStyleRuns, [])
        XCTAssertEqual(metrics?.origin.x, 53)
        XCTAssertEqual(metrics?.width, 334)
        XCTAssertEqual(metrics?.insertionLineHeadIndent, 56)
        XCTAssertEqual(metrics?.textStyle, style)
        XCTAssertEqual(metrics?.typographyIsEstimated, false)
        XCTAssertEqual(snapshot?.textStyle, style)
    }

    func testWebEmptyLineUsesTheLineStartEdge() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:body",
            role: kAXTextAreaRole as String,
            textBefore: "line\n",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 60, y: 120, width: 0, height: 18), source: .lineStart),
            ],
            lineBounds: CGRect(x: 60, y: 120, width: 0, height: 18),
            paragraphTextBefore: "",
            caretTextStyle: ActiveFieldTextStyle(fontName: "HelveticaNeue", fontSize: 15)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.caretBounds, CGRect(x: 60, y: 662, width: 0, height: 18))
        XCTAssertEqual(snapshot?.geometrySource, .lineStart)
        XCTAssertEqual(snapshot?.paragraphMetrics?.insertionLineHeadIndent, 0)
        XCTAssertEqual(snapshot?.paragraphMetrics?.origin.x, 60)
        XCTAssertEqual(snapshot?.masksHostPlaceholder, false)
    }

    func testWebEmptyFieldIsMaskedOnlyWhenTrulyEmpty() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextFieldRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:subject",
            role: kAXTextFieldRole as String,
            textBefore: "",
            frame: CGRect(x: 40, y: 60, width: 360, height: 32),
            caretCandidates: [
                .init(rect: CGRect(x: 48, y: 66, width: 0, height: 18), source: .lineStart),
            ]
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.masksHostPlaceholder, true)
        XCTAssertEqual(snapshot?.publicationStructure?.selectionPosition, .start)
        XCTAssertEqual(snapshot?.publicationStructure?.textAfterIsEmpty, true)
    }

    func testWebEmptyFieldMasksPlaceholderWhenHostOmitsPlaceholderMetadata() {
        let measuredStyle = ActiveFieldTextStyle(
            fontName: ".AppleSystemUIFont",
            fontSize: 14
        )
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.openai.codex",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "777:composer",
            role: kAXTextAreaRole as String,
            textBefore: "",
            frame: CGRect(x: 40, y: 60, width: 360, height: 120),
            caretCandidates: [
                .init(rect: CGRect(x: 48, y: 66, width: 0, height: 18), source: .lineStart),
            ],
            caretTextStyle: measuredStyle
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.masksHostPlaceholder, true)
        XCTAssertEqual(snapshot?.textStyle, measuredStyle)
        XCTAssertEqual(snapshot?.paragraphMetrics?.textStyle, measuredStyle)
    }

    func testWebSyntheticPlaceholderCarriesAnExplicitMaskInsteadOfTheEditorBlock() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.openai.codex",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil,
            displays: [
                .init(
                    accessibilityFrame: CGRect(x: 0, y: 0, width: 1512, height: 1200),
                    appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 1200)
                ),
            ]
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "777:composer",
            role: kAXTextAreaRole as String,
            textBefore: "",
            frame: CGRect(x: 571, y: 982, width: 926, height: 58),
            caretCandidates: [
                .init(rect: CGRect(x: 571, y: 1002, width: 0, height: 18), source: .lineStart),
            ],
            lineBounds: CGRect(x: 571, y: 1002, width: 0, height: 18),
            paragraphTextBefore: "",
            caretTextStyle: .init(fontName: ".AppleSystemUIFont", fontSize: 14),
            hostPlaceholderBounds: CGRect(x: 571, y: 1002, width: 72, height: 18)
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.caretBounds?.height, 18)
        XCTAssertEqual(snapshot?.textStyle?.fontSize, 14)
        XCTAssertEqual(snapshot?.hostPlaceholderBounds?.width, 72)
        XCTAssertNotEqual(snapshot?.hostPlaceholderBounds?.width, 926)
    }

    func testWebLineEdgesRemainDiagnosticWithoutCompetingWithValidGlyphCandidates() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.apple.Safari",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "42:textarea",
            role: kAXTextAreaRole as String,
            textBefore: "abc",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 100, y: 100, width: 9, height: 18), source: .precedingGrapheme),
                .init(rect: CGRect(x: 60, y: 96, width: 200, height: 26), source: .lineEnd),
            ]
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.geometrySource, .precedingGrapheme)
        XCTAssertEqual(snapshot?.caretBounds?.minX, 109)
        XCTAssertEqual(snapshot?.geometryStructure?.lineEdgeBounds, .available)
    }

    func testWebAmbiguousBidiBoundaryStaysUnavailable() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:body",
            role: kAXTextAreaRole as String,
            textBefore: "abc",
            textAfter: "אב",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 60, y: 100, width: 80, height: 18), source: .lineEnd),
            ]
        )

        let snapshot = captured(reader)

        XCTAssertNil(snapshot?.caretBounds)
        XCTAssertEqual(snapshot?.geometryStructure?.direction, .ambiguous)
        XCTAssertEqual(snapshot?.paragraphMetricsFailureReason, .directionUnavailable)
    }

    func testWebNonCollapsedSelectionCapturesTextWithoutGeometry() {
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.google.Chrome",
            webContent: true,
            role: kAXTextAreaRole as String,
            text: nil,
            selection: nil
        )
        reader.webContext = WebTextContext(
            editableIdentifier: "665:body",
            role: kAXTextAreaRole as String,
            textBefore: "Hola ",
            selectedText: "mundo",
            textAfter: "!",
            frame: CGRect(x: 40, y: 60, width: 360, height: 240),
            caretCandidates: [
                .init(rect: CGRect(x: 60, y: 100, width: 80, height: 18), source: .lineEnd),
            ]
        )

        let snapshot = captured(reader)

        XCTAssertEqual(snapshot?.selectedText, "mundo")
        XCTAssertEqual(snapshot?.selectionRange, NSRange(location: 5, length: 5))
        XCTAssertNil(snapshot?.caretBounds)
        XCTAssertEqual(snapshot?.publicationStructure?.selectionCollapsed, false)
    }

    // MARK: - Native line fill

    func testNativeParagraphWithoutTypographyFallsBackToMeasuredLineFill() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        let reader = FakeAccessibilityReader(
            bundleIdentifier: "com.example.Editor",
            text: "current",
            selection: NSRange(location: 7, length: 0),
            bounds: CGRect(x: 128, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 6, length: 1): CGRect(x: 120, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1): CGRect(x: 72, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: nil,
            paragraphAttributes: .plain,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        let snapshot = captured(reader)
        let metrics = snapshot?.paragraphMetrics

        XCTAssertNil(snapshot?.paragraphMetricsFailureReason)
        XCTAssertEqual(metrics?.textBeforeCaret, "")
        XCTAssertEqual(metrics?.origin, CGPoint(x: 72, y: 620))
        XCTAssertEqual(metrics?.width, 328)
        XCTAssertEqual(metrics?.insertionLineHeadIndent, 56)
        XCTAssertEqual(metrics?.textStyle, style)
        XCTAssertEqual(metrics?.typographyIsEstimated, false)
    }

    func testNativeListParagraphsStaySilentInsteadOfLineFilling() {
        let style = ActiveFieldTextStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
        var nativeList = ActiveFieldParagraphAttributes.plain
        nativeList.listMarker = "•"
        nativeList.listLevel = 0
        let reader = FakeAccessibilityReader(
            text: "list item",
            selection: NSRange(location: 9, length: 0),
            bounds: CGRect(x: 140, y: 180, width: 0, height: 16),
            boundsByRange: [
                NSRange(location: 8, length: 1): CGRect(x: 132, y: 180, width: 8, height: 16),
                NSRange(location: 0, length: 1): CGRect(x: 72, y: 180, width: 8, height: 16),
            ],
            textStyle: style,
            paragraphTextStyleRuns: [
                .init(range: NSRange(location: 0, length: 9), style: style),
            ],
            paragraphAttributes: nativeList,
            inputFrame: CGRect(x: 40, y: 80, width: 360, height: 220)
        )

        let snapshot = captured(reader)

        XCTAssertNil(snapshot?.paragraphMetrics)
        XCTAssertEqual(snapshot?.paragraphMetricsFailureReason, .listUnsupported)
    }

    private func captured(_ reader: FakeAccessibilityReader) -> ActiveFieldSnapshot? {
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)
        guard case let .captured(snapshot) = capture.capture() else { XCTFail("Expected capture"); return nil }
        return snapshot
    }
}

private final class ConcurrentProbeReader: AccessibilityReading, @unchecked Sendable {
    private let lock = NSLock(); private var activeReads = 0; private(set) var maximumConcurrentReads = 0
    func focusedElement() -> AccessibilityElement? { lock.withLock { activeReads += 1; maximumConcurrentReads = max(maximumConcurrentReads, activeReads) }; Thread.sleep(forTimeInterval: 0.02); lock.withLock { activeReads -= 1 }; return AccessibilityElement(identifier: "notes-field") }
    func applicationBundleIdentifier(for element: AccessibilityElement) -> String? { "com.apple.Notes" }
    func role(for element: AccessibilityElement) -> String? { "AXTextArea" }
    func subrole(for element: AccessibilityElement) -> String? { nil }
    func stringValue(for element: AccessibilityElement) -> String? { "note" }
    func selectedTextRange(for element: AccessibilityElement) -> NSRange? { NSRange(location: 4, length: 0) }
    func bounds(for range: NSRange, in element: AccessibilityElement) -> CGRect? { nil }
}

private final class FakeAccessibilityReader: AccessibilityReading {
    var sources: [FieldSource] = []
    var sourceReadCount = 0
    func sourceContexts(for element: AccessibilityElement) -> [FieldSource] { sourceReadCount += 1; return sources }
    var element = AccessibilityElement(identifier: "notes-field-1")
    var focusedElementUnavailable = false
    var focusedElementFailuresRemaining = 0
    var processIdentifier: Int32?
    var frontmostPID: Int32?
    func frontmostProcessIdentifier() -> Int32? { frontmostPID }
    var webContext: WebTextContext?
    var bundleIdentifier: String?; var webContent: Bool; var role: String?; var subrole: String?; var text: String?; var selection: NSRange?; var bounds: CGRect?
    var boundsByRange: [NSRange: CGRect]; var textStyle: ActiveFieldTextStyle?; var paragraphTextStyleRuns: [ActiveFieldTextStyleRun]?; var paragraphAttributes: ActiveFieldParagraphAttributes?; var inputFrame: CGRect?; var displays: [DisplayGeometry]
    private(set) var focusReadCount = 0; private(set) var stringValueReadCount = 0; private(set) var boundsReadCount = 0; private(set) var webCapabilityReadCount = 0; private(set) var webContextReadCount = 0; private(set) var webAccessibilityPreparationCount = 0; private(set) var frontmostWebAccessibilityPreparationCount = 0
    private(set) var requestedRanges: [NSRange] = []
    init(bundleIdentifier: String? = "com.apple.Notes", webContent: Bool = false, role: String? = "AXTextArea", subrole: String? = nil, text: String?, selection: NSRange?, bounds: CGRect? = CGRect(x: 10, y: 20, width: 1, height: 18), boundsByRange: [NSRange: CGRect] = [:], textStyle: ActiveFieldTextStyle? = nil, paragraphTextStyleRuns: [ActiveFieldTextStyleRun]? = nil, paragraphAttributes: ActiveFieldParagraphAttributes? = nil, inputFrame: CGRect? = nil, displays: [DisplayGeometry] = [.init(accessibilityFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))]) { self.bundleIdentifier = bundleIdentifier; self.webContent = webContent; self.role = role; self.subrole = subrole; self.text = text; self.selection = selection; self.bounds = bounds; self.boundsByRange = boundsByRange; self.textStyle = textStyle; self.paragraphTextStyleRuns = paragraphTextStyleRuns; self.paragraphAttributes = paragraphAttributes; self.inputFrame = inputFrame; self.displays = displays }
    func focusedElement() -> AccessibilityElement? {
        focusReadCount += 1
        if focusedElementUnavailable { return nil }
        if focusedElementFailuresRemaining > 0 {
            focusedElementFailuresRemaining -= 1
            return nil
        }
        return element
    }
    func prepareFrontmostWebContent() { frontmostWebAccessibilityPreparationCount += 1 }
    func applicationBundleIdentifier(for element: AccessibilityElement) -> String? { bundleIdentifier }
    func processIdentifier(for element: AccessibilityElement) -> Int32? { processIdentifier }
    func isWebContentElement(_ element: AccessibilityElement) -> Bool {
        webCapabilityReadCount += 1
        return webContent
    }
    func prepareWebContent(for element: AccessibilityElement) -> AccessibilityElement { webAccessibilityPreparationCount += 1; return element }
    func webTextContext(for element: AccessibilityElement) -> WebTextContext? { webContextReadCount += 1; return webContext }
    func role(for element: AccessibilityElement) -> String? { role }
    func subrole(for element: AccessibilityElement) -> String? { subrole }
    func stringValue(for element: AccessibilityElement) -> String? { stringValueReadCount += 1; return text }
    func selectedTextRange(for element: AccessibilityElement) -> NSRange? { selection }
    func bounds(for range: NSRange, in element: AccessibilityElement) -> CGRect? { boundsReadCount += 1; requestedRanges.append(range); return boundsByRange[range] ?? bounds }
    func frame(for element: AccessibilityElement) -> CGRect? { inputFrame }
    func textStyle(for range: NSRange, in element: AccessibilityElement) -> ActiveFieldTextStyle? { textStyle }
    func textStyleRuns(for range: NSRange, in element: AccessibilityElement) -> [ActiveFieldTextStyleRun]? { paragraphTextStyleRuns }
    func paragraphAttributes(for range: NSRange, in element: AccessibilityElement) -> ActiveFieldParagraphAttributes? { paragraphAttributes }
    func displayGeometries() -> [DisplayGeometry] { displays }
}
