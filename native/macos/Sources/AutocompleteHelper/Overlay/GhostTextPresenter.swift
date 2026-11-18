import AppKit
import CoreText
import Foundation

@MainActor
protocol GhostTextDisplaying: AnyObject {
    @discardableResult
    func showSingleLine(_ presentation: GhostTextSingleLinePresentation) -> Bool
    @discardableResult
    func showParagraphMirror(_ presentation: ParagraphMirrorLayoutResult) -> Bool
    func dismiss()
}

enum GhostTextPresenterRejectionReason: String, Equatable, Sendable {
    case staleCapture = "stale_capture"
    case paragraphEmptyCompletion = "paragraph_empty_completion"
    case paragraphFocusChanged = "paragraph_focus_changed"
    case paragraphCaptureUnavailable = "paragraph_capture_unavailable"
    case paragraphSelectionActive = "paragraph_selection_active"
    case paragraphNotAtEnd = "paragraph_not_at_end"
    case paragraphGeometryUnavailable = "paragraph_geometry_unavailable"
    case paragraphCaretUnavailable = "paragraph_caret_unavailable"
    case paragraphFieldUnavailable = "paragraph_field_unavailable"
    case paragraphCaretInvalid = "paragraph_caret_invalid"
    case paragraphFieldInvalid = "paragraph_field_invalid"
    case paragraphCaretOutsideField = "paragraph_caret_outside_field"
    case paragraphDisplayUnavailable = "paragraph_display_unavailable"
    case paragraphMetricsUnavailable = "paragraph_metrics_unavailable"
    case paragraphPrefixMismatch = "paragraph_prefix_mismatch"
    case paragraphLayout = "paragraph_layout"
    case paragraphOutsideVisibleField = "paragraph_outside_visible_field"
    case singleLineLayout = "single_line_layout"
    case displayRejected = "display_rejected"
}

struct GhostTypographyMeasurement: Sendable {
    let empty: Bool
    let estimated: Bool
    let fontSize: Double
    let caretHeight: Double
    let inputHeight: Double
    let paragraph: Bool
}

@MainActor
final class GhostTextPresenter {
    typealias DisplayGeometryProvider = @MainActor () -> [DisplayGeometry]

    private let typographyDiagnostic: ((SuggestionRequestMessage.Identity, GhostTypographyMeasurement) -> Void)?
    private let display: any GhostTextDisplaying
    private let displayGeometries: DisplayGeometryProvider
    private let overflowDiagnostic: ((SuggestionRequestMessage.Identity, GhostTextOverflow) -> Void)?

    private(set) var visibleIdentity: SuggestionRequestMessage.Identity?
    private(set) var visibleText: String?
    private(set) var visibleGlyphRegions: [CGRect] = []
    private(set) var lastRejectionReason: GhostTextPresenterRejectionReason?
    private(set) var lastParagraphLayoutFailureReason: ParagraphMirrorLayoutFailureReason?
    private(set) var lastHorizontalDrawOffset: CGFloat?
    private var visibleContentSignature: String?
    private var visibleSnapshot: ActiveFieldSnapshot?
    private var visibleParagraphMetrics: ActiveFieldParagraphMetrics?
    private var visibleCaret: CGRect?
    private var visibleBackingScaleFactor: CGFloat = 1
    private var latestCaptureSequence: UInt64 = 0

    init(
        display: any GhostTextDisplaying,
        displayGeometries: @escaping DisplayGeometryProvider = {
            SystemAccessibilityReader().displayGeometries()
        },
        overflowDiagnostic: ((SuggestionRequestMessage.Identity, GhostTextOverflow) -> Void)? = nil,
        typographyDiagnostic: ((SuggestionRequestMessage.Identity, GhostTypographyMeasurement) -> Void)? = nil
    ) {
        self.display = display
        self.displayGeometries = displayGeometries
        self.overflowDiagnostic = overflowDiagnostic
        self.typographyDiagnostic = typographyDiagnostic
    }

    func refreshAppearance() {
        guard let identity = visibleIdentity, let text = visibleText, let snapshot = visibleSnapshot else { return }
        _ = present(identity: identity, text: text, snapshot: snapshot, allowsFitting: false)
    }

    @discardableResult
    func present(
        identity: SuggestionRequestMessage.Identity,
        text: String,
        snapshot: ActiveFieldSnapshot,
        protectedText: [String] = [],
        allowsFitting: Bool = true
    ) -> Bool {
        guard snapshot.captureSequence >= latestCaptureSequence else {
            lastRejectionReason = .staleCapture
            lastParagraphLayoutFailureReason = nil
            return false
        }
        latestCaptureSequence = snapshot.captureSequence
        lastHorizontalDrawOffset = nil
        var displayedText = text
        let displays = displayGeometries()
        let didPresent: Bool
        let hitRegions: [CGRect]
        let horizontalDrawOffset: CGFloat?
        var renderedFontSize: CGFloat = 0
        var renderedEstimated = false
        var presentedMetrics: ActiveFieldParagraphMetrics?
        var presentedCaret: CGRect?
        var backingScaleFactor: CGFloat = 1
        if snapshot.hostPlaceholderBounds != nil {
            guard let singleLine = Self.singleLinePresentation(
                text: text,
                identity: identity,
                snapshot: snapshot,
                displays: displays, protectedText: protectedText, allowsFitting: allowsFitting
            ) else {
                lastRejectionReason = .singleLineLayout
                lastParagraphLayoutFailureReason = nil
                dismissCurrentPresentation(identity: identity)
                return false
            }
            displayedText = singleLine.text
            renderedFontSize = singleLine.font.pointSize
            renderedEstimated = snapshot.textStyle?.isEstimated ?? snapshot.paragraphMetrics?.typographyIsEstimated ?? true
            didPresent = display.showSingleLine(singleLine)
            hitRegions = Self.singleLineHitRegions(singleLine)
            horizontalDrawOffset = 0
            presentedCaret = snapshot.caretBounds
        } else {
            switch snapshot.fieldKind {
            case .multiline:
                let evaluation = Self.paragraphMirrorPresentation(
                    text: text,
                    identity: identity,
                    snapshot: snapshot,
                    displays: displays,
                    protectedText: protectedText,
                    allowsFitting: allowsFitting
                )
                if let overflow = evaluation.overflow { overflowDiagnostic?(identity, overflow) }
                guard let paragraph = evaluation.presentation else {
                    lastRejectionReason = evaluation.rejectionReason
                    lastParagraphLayoutFailureReason = evaluation.layoutFailureReason
                    dismissCurrentPresentation(identity: identity)
                    return false
                }
                displayedText = paragraph.attributedText.attributedSubstring(from: paragraph.completionRange).string
                renderedFontSize = (paragraph.attributedText.attribute(.font, at: paragraph.completionRange.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
                renderedEstimated = evaluation.metrics?.typographyIsEstimated ?? true
                didPresent = display.showParagraphMirror(paragraph)
                hitRegions = paragraph.lineFragments.filter {
                    $0.width > 0 && $0.height > 0
                }
                horizontalDrawOffset = paragraph.completionLineSlices.first?.horizontalDrawOffset
                presentedMetrics = evaluation.metrics
                presentedCaret = paragraph.anchor
                backingScaleFactor = evaluation.backingScaleFactor
            case .singleLine:
                guard let singleLine = Self.singleLinePresentation(
                    text: text,
                    identity: identity,
                    snapshot: snapshot,
                    displays: displays, protectedText: protectedText, allowsFitting: allowsFitting
                ) else {
                    lastRejectionReason = .singleLineLayout
                    lastParagraphLayoutFailureReason = nil
                    dismissCurrentPresentation(identity: identity)
                    return false
                }
                displayedText = singleLine.text
                renderedFontSize = singleLine.font.pointSize
                renderedEstimated = snapshot.textStyle?.isEstimated ?? snapshot.paragraphMetrics?.typographyIsEstimated ?? true
                didPresent = display.showSingleLine(singleLine)
                hitRegions = Self.singleLineHitRegions(singleLine)
                horizontalDrawOffset = 0
                presentedCaret = snapshot.caretBounds
            }
        }
        guard didPresent else {
            lastRejectionReason = .displayRejected
            lastParagraphLayoutFailureReason = nil
            dismissCurrentPresentation(identity: identity)
            return false
        }

        typographyDiagnostic?(identity, .init(
            empty: snapshot.textBefore.isEmpty && snapshot.selectedText.isEmpty && snapshot.textAfter.isEmpty,
            estimated: renderedEstimated, fontSize: Double(renderedFontSize),
            caretHeight: Double(snapshot.caretBounds?.height ?? 0),
            inputHeight: Double(snapshot.inputFrame?.height ?? 0), paragraph: presentedMetrics != nil
        ))
        lastRejectionReason = nil
        lastParagraphLayoutFailureReason = nil
        lastHorizontalDrawOffset = horizontalDrawOffset
        visibleIdentity = identity
        visibleText = displayedText
        visibleGlyphRegions = hitRegions
        visibleContentSignature = snapshot.contentSignature
        visibleSnapshot = snapshot
        visibleParagraphMetrics = presentedMetrics
        visibleCaret = presentedCaret
        visibleBackingScaleFactor = backingScaleFactor
        return true
    }

    /// Keeps the ghost on screen while the user types its beginning. The
    /// paragraph string does not change when a completion prefix is typed,
    /// so the aligned layout does not move: only the visible split does. The
    /// returned snapshot is the host state this prediction implies; the
    /// caller must corroborate it against the next authoritative capture.
    func advance(
        identity: SuggestionRequestMessage.Identity,
        typed: String,
        remaining: String
    ) -> ActiveFieldSnapshot? {
        guard visibleIdentity == identity,
              let base = visibleSnapshot,
              let caret = visibleCaret,
              !typed.isEmpty,
              !remaining.isEmpty,
              let visibleText,
              visibleText.hasPrefix(typed),
              String(visibleText.dropFirst(typed.count)) == remaining
        else { return nil }

        let predicted: ActiveFieldSnapshot
        switch base.fieldKind {
        case .multiline:
            guard let metrics = visibleParagraphMetrics,
                  base.paragraphMetrics != nil,
                  let predictedCaret = ParagraphMirrorLayout.predictedCaret(
                      backingScaleFactor: visibleBackingScaleFactor,
                      metrics: metrics,
                      completion: visibleText,
                      caretBounds: caret,
                      typedUTF16Length: typed.utf16.count
                  ),
                  let advancedMetrics = Self.advancedMetrics(
                      metrics,
                      typed: typed,
                      predictedCaret: predictedCaret
                  )
            else { return nil }
            predicted = base.advanced(
                byTyping: typed,
                caretBounds: predictedCaret,
                paragraphMetrics: advancedMetrics
            )
        case .singleLine:
            guard let style = base.textStyle,
                  let font = GhostTextTypography.font(for: style),
                  let direction = Self.writingDirection(
                      textBefore: base.textBefore,
                      suggestion: visibleText
                  )
            else { return nil }
            let width = Self.typographicWidth(of: typed, font: font, direction: direction)
            let dx = direction == .leftToRight ? width : -width
            predicted = base.advanced(
                byTyping: typed,
                caretBounds: caret.offsetBy(dx: dx, dy: 0),
                paragraphMetrics: nil
            )
        }
        return present(identity: identity, text: remaining, snapshot: predicted, allowsFitting: false)
            ? predicted
            : nil
    }

    private static func advancedMetrics(
        _ metrics: ActiveFieldParagraphMetrics,
        typed: String,
        predictedCaret: CGRect
    ) -> ActiveFieldParagraphMetrics? {
        var advanced = metrics
        if metrics.textBeforeCaret.isEmpty, metrics.prefixStyleRuns.isEmpty {
            // Line fill: the completion is laid out alone and the caret is
            // expressed as a first-line indent from the paragraph edge.
            let indent: CGFloat
            switch metrics.writingDirection {
            case .leftToRight:
                indent = predictedCaret.maxX - metrics.origin.x
            case .rightToLeft:
                indent = metrics.origin.x + metrics.width - predictedCaret.minX
            }
            guard indent.isFinite, indent >= 0, indent <= metrics.width else { return nil }
            advanced.insertionLineHeadIndent = indent
            advanced.origin.y = predictedCaret.maxY
            return advanced
        }
        guard let last = metrics.prefixStyleRuns.last else { return nil }
        advanced.textBeforeCaret += typed
        advanced.prefixStyleRuns[advanced.prefixStyleRuns.count - 1] = ActiveFieldTextStyleRun(
            range: NSRange(
                location: last.range.location,
                length: last.range.length + typed.utf16.count
            ),
            style: last.style
        )
        return advanced
    }

    private static func typographicWidth(
        of text: String,
        font: NSFont,
        direction: GhostTextWritingDirection
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = switch direction {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func dismissCurrentPresentation(
        identity: SuggestionRequestMessage.Identity
    ) {
        guard visibleIdentity == identity else { return }
        _ = dismiss(identity: identity)
    }

    private struct ParagraphPresentationEvaluation {
        let presentation: ParagraphMirrorLayoutResult?
        let rejectionReason: GhostTextPresenterRejectionReason?
        let layoutFailureReason: ParagraphMirrorLayoutFailureReason?
        var metrics: ActiveFieldParagraphMetrics? = nil
        var backingScaleFactor: CGFloat = 1
        var overflow: GhostTextOverflow? = nil
    }

    private static func paragraphMirrorPresentation(
        text: String,
        identity: SuggestionRequestMessage.Identity,
        snapshot: ActiveFieldSnapshot,
        displays: [DisplayGeometry],
        protectedText: [String] = [],
        allowsFitting: Bool = false
    ) -> ParagraphPresentationEvaluation {
        func rejected(_ reason: GhostTextPresenterRejectionReason) -> ParagraphPresentationEvaluation {
            .init(presentation: nil, rejectionReason: reason, layoutFailureReason: nil)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return rejected(.paragraphEmptyCompletion) }
        guard snapshot.focusGeneration == identity.focusSequence else { return rejected(.paragraphFocusChanged) }
        guard snapshot.captureSequence > 0 else { return rejected(.paragraphCaptureUnavailable) }
        guard snapshot.selectedText.isEmpty, snapshot.selectionRange.length == 0 else { return rejected(.paragraphSelectionActive) }
        guard isAtParagraphEnd(snapshot.textAfter) else { return rejected(.paragraphNotAtEnd) }
        guard snapshot.geometryQuality != .unavailable, snapshot.geometrySource != nil else { return rejected(.paragraphGeometryUnavailable) }
        guard let caret = snapshot.caretBounds else { return rejected(.paragraphCaretUnavailable) }
        guard let inputFrame = snapshot.inputFrame else { return rejected(.paragraphFieldUnavailable) }
        guard isValidCaret(caret) else { return rejected(.paragraphCaretInvalid) }
        guard isValidArea(inputFrame) else { return rejected(.paragraphFieldInvalid) }
        guard fullyContains(inputFrame, caret) else { return rejected(.paragraphCaretOutsideField) }
        guard let concreteDisplay = displays.first(where: {
            isValidArea($0.appKitFrame) && fullyContains($0.appKitFrame, caret)
        }) else { return rejected(.paragraphDisplayUnavailable) }
        let presentationCaret = caret
        let metrics = snapshot.paragraphMetrics
            ?? bootstrapParagraphMetrics(
                snapshot: snapshot,
                suggestion: text,
                caret: presentationCaret,
                inputFrame: inputFrame
            )
        guard let metrics else { return rejected(.paragraphMetricsUnavailable) }
        guard snapshot.textBefore.hasSuffix(metrics.textBeforeCaret) else { return rejected(.paragraphPrefixMismatch) }
        let layout = ParagraphMirrorLayout.evaluate(
                  surface: snapshot.surface,
                  backingScaleFactor: concreteDisplay.backingScaleFactor,
                  metrics: metrics,
                  completion: text,
                  caretBounds: presentationCaret,
                  masksHostPlaceholder:
                      snapshot.masksHostPlaceholder
                          || (snapshot.paragraphMetrics == nil && !snapshot.surface.isWebContent)
              )
        guard let rawResult = layout.presentation else {
            return ParagraphPresentationEvaluation(
                presentation: nil,
                rejectionReason: .paragraphLayout,
                layoutFailureReason: layout.failureReason
            )
        }

        let visibleField = inputFrame.intersection(concreteDisplay.appKitFrame)
        guard isValidArea(visibleField) else {
            return ParagraphPresentationEvaluation(
                presentation: nil,
                rejectionReason: .paragraphOutsideVisibleField,
                layoutFailureReason: nil
            )
        }
        // Never clip a rendered glyph or leave an invisible accepted suffix.
        // On the first presentation only, choose a complete prefix from the
        // measured line bounds, then lay that exact candidate out again.
        if !fullyContains(visibleField, rawResult.frame)
            || !rawResult.lineFragments.allSatisfy({ fullyContains(visibleField, $0) }) {
            var overflow = GhostTextOverflow(frame: rawResult.frame, visibleField: visibleField,
                caret: caret, lineHeight: metrics.lineHeight, completionLines: rawResult.completionLineSlices.count)
            if allowsFitting, overflow.left == .none, overflow.right == .none, overflow.top == .none {
                overflow.fitting = .noVisibleLine
                let visibleSlices = rawResult.completionLineSlices.prefix { fullyContains(visibleField, $0.bounds) }
                if !visibleSlices.isEmpty { overflow.fitting = .noSafeBoundary }
                let linePrefix = visibleSlices.last.flatMap { last in
                    VisibleSuggestionPrefix.select(text,
                        maximumUTF16Count: NSMaxRange(last.characterRange) - rawResult.completionRange.location,
                        protectedText: protectedText)
                }
                // Word wrapping can leave only whitespace on the insertion line.
                // Ask Core Text for a cluster-sized candidate in the measured
                // remaining width, then verify it with the same paragraph layout.
                let remainingWidth = metrics.writingDirection == .leftToRight
                    ? min(visibleField.maxX, metrics.origin.x + metrics.width) - caret.maxX
                    : caret.minX - max(visibleField.minX, metrics.origin.x)
                let clusterPrefix: String? = linePrefix == nil && remainingWidth > 0
                    ? VisibleSuggestionPrefix.select(text,
                        maximumUTF16Count: CTTypesetterSuggestClusterBreak(
                            CTTypesetterCreateWithAttributedString(rawResult.attributedText.attributedSubstring(from: rawResult.completionRange)),
                            0, Double(remainingWidth)), protectedText: protectedText)
                    : nil
                if let prefix = linePrefix ?? clusterPrefix, prefix != text {
                    var fitted = paragraphMirrorPresentation(text: prefix, identity: identity, snapshot: snapshot,
                        displays: displays, protectedText: protectedText, allowsFitting: false)
                    overflow.fitting = fitted.presentation == nil ? .relayoutRejected : .fitted
                    fitted.overflow = overflow
                    return fitted
                }
            }
            return ParagraphPresentationEvaluation(presentation: nil,
                rejectionReason: .paragraphOutsideVisibleField, layoutFailureReason: nil, overflow: overflow)
        }
        return ParagraphPresentationEvaluation(
            presentation: rawResult,
            rejectionReason: nil,
            layoutFailureReason: nil,
            metrics: metrics,
            backingScaleFactor: concreteDisplay.backingScaleFactor
        )
    }

    private static func isAtParagraphEnd(_ textAfter: String) -> Bool {
        textAfter.isEmpty || textAfter.first?.isNewline == true
    }

    private static func bootstrapParagraphMetrics(
        snapshot: ActiveFieldSnapshot,
        suggestion: String,
        caret: CGRect,
        inputFrame: CGRect
    ) -> ActiveFieldParagraphMetrics? {
        guard canBootstrapEmptyField(snapshot),
              let direction = writingDirection(
                  textBefore: snapshot.textBefore,
                  suggestion: suggestion
              )
        else { return nil }
        guard let style = GhostTextTypography.style(for: snapshot),
              let font = GhostTextTypography.font(for: style) else { return nil }
        let originX: CGFloat
        let width: CGFloat
        let caretDirection: CaretWritingDirection
        switch direction {
        case .leftToRight:
            originX = caret.maxX
            width = inputFrame.maxX - originX
            caretDirection = .leftToRight
        case .rightToLeft:
            originX = inputFrame.minX
            width = caret.minX - originX
            caretDirection = .rightToLeft
        }
        guard width.isFinite, width > 0 else { return nil }
        return ActiveFieldParagraphMetrics(
            textBeforeCaret: "",
            origin: CGPoint(x: originX, y: caret.maxY),
            width: width,
            lineHeight: ceil(font.ascender - font.descender + font.leading),
            writingDirection: caretDirection,
            textStyle: style,
            prefixStyleRuns: [],
            attributes: .plain,
            typographyIsEstimated: snapshot.textStyle?.isEstimated ?? true
        )
    }

    private static func canBootstrapEmptyField(
        _ snapshot: ActiveFieldSnapshot
    ) -> Bool {
        snapshot.textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isAtParagraphEnd(snapshot.textAfter)
            && snapshot.paragraphMetricsFailureReason == .empty
            && snapshot.geometryQuality == .exact
            && snapshot.geometrySource == .zeroLengthRange
    }

    @discardableResult
    func reanchor(snapshot: ActiveFieldSnapshot) -> Bool {
        guard let visibleIdentity,
              let visibleText,
              visibleContentSignature == snapshot.contentSignature
        else { return false }
        return present(
            identity: visibleIdentity,
            text: visibleText,
            snapshot: snapshot,
            allowsFitting: false
        )
    }

    @discardableResult
    func dismiss(identity: SuggestionRequestMessage.Identity? = nil) -> Bool {
        if let identity, identity != visibleIdentity {
            return false
        }
        guard visibleIdentity != nil else {
            return false
        }
        clearVisibleState()
        display.dismiss()
        return true
    }

    @discardableResult
    func dismissForGeometryChange() -> Bool {
        return dismiss()
    }

    func isVisibleGlyph(at point: CGPoint) -> Bool {
        visibleGlyphRegions.contains(where: { $0.contains(point) })
    }

    /// Removes the ghost before the host is edited so that the completion is
    /// never visible twice. Insertion itself happens off the main thread.
    func dismissForAcceptance(identity: SuggestionRequestMessage.Identity) {
        if visibleIdentity == identity {
            clearVisibleState()
            display.dismiss()
        }
    }

    private func clearVisibleState() {
        visibleIdentity = nil
        visibleText = nil
        visibleGlyphRegions = []
        visibleContentSignature = nil
        visibleSnapshot = nil
        visibleParagraphMetrics = nil
        visibleCaret = nil
    }

    private static func singleLineHitRegions(
        _ presentation: GhostTextSingleLinePresentation
    ) -> [CGRect] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = switch presentation.direction {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
        let attributed = NSAttributedString(
            string: presentation.text,
            attributes: [
                .font: presentation.font,
                .paragraphStyle: paragraph,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let typographicWidth = CGFloat(
            CTLineGetTypographicBounds(line, nil, nil, nil)
        )
        let drawOriginX = switch presentation.direction {
        case .leftToRight: CGFloat.zero
        case .rightToLeft: max(0, presentation.frame.width - typographicWidth)
        }
        let imageBounds = CTLineGetImageBounds(line, nil)
        guard !imageBounds.isNull,
              !imageBounds.isInfinite,
              imageBounds.width > 0,
              imageBounds.height > 0
        else { return [] }
        let globalBounds = CGRect(
            x: presentation.frame.minX + drawOriginX + imageBounds.minX,
            y: presentation.baselineY + imageBounds.minY,
            width: imageBounds.width,
            height: imageBounds.height
        )
        let clipped = globalBounds.intersection(presentation.frame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return []
        }
        return [clipped]
    }

    private static func singleLinePresentation(
        text: String,
        identity: SuggestionRequestMessage.Identity,
        snapshot: ActiveFieldSnapshot,
        displays: [DisplayGeometry],
        protectedText: [String] = [],
        allowsFitting: Bool = false
    ) -> GhostTextSingleLinePresentation? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.contains(where: { $0.isNewline }),
              snapshot.focusGeneration == identity.focusSequence,
              snapshot.captureSequence > 0,
              snapshot.selectedText.isEmpty,
              snapshot.selectionRange.length == 0,
              snapshot.textAfter.isEmpty,
              snapshot.geometryQuality != .unavailable,
              snapshot.geometrySource != nil,
              let caret = snapshot.caretBounds,
              let inputFrame = snapshot.inputFrame,
              isValidCaret(caret),
              isValidArea(inputFrame),
              fullyContains(inputFrame, caret),
              let concreteDisplay = displays.first(where: {
                  isValidArea($0.appKitFrame)
                      && fullyContains($0.appKitFrame, caret)
              }),
              let font = GhostTextTypography.font(
                  for: GhostTextTypography.style(for: snapshot)
              ),
              let direction = writingDirection(
                  textBefore: snapshot.textBefore,
                  suggestion: text
              )
        else { return nil }

        let visibleField = inputFrame.intersection(concreteDisplay.appKitFrame)
        guard isValidArea(visibleField) else { return nil }

        let minX: CGFloat
        let maxX: CGFloat
        switch direction {
        case .leftToRight:
            minX = caret.maxX
            maxX = visibleField.maxX
        case .rightToLeft:
            minX = visibleField.minX
            maxX = caret.minX
        }
        let localAnchor = switch direction {
        case .leftToRight: minX - visibleField.minX
        case .rightToLeft: maxX - visibleField.minX
        }
        guard localAnchor.isFinite,
              localAnchor >= 0,
              localAnchor <= visibleField.width,
              maxX > minX
        else { return nil }

        if allowsFitting {
            let paragraph = NSMutableParagraphStyle()
            paragraph.baseWritingDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
            let attributed = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let count = CTTypesetterSuggestLineBreak(typesetter, 0, Double(maxX - minX))
            if count < text.utf16.count {
                let wordPrefix = VisibleSuggestionPrefix.select(text, maximumUTF16Count: count,
                    protectedText: protectedText)
                var candidate = wordPrefix ?? VisibleSuggestionPrefix.select(text,
                    maximumUTF16Count: CTTypesetterSuggestClusterBreak(typesetter, 0, Double(maxX - minX)),
                    protectedText: protectedText)
                // Cutting a contextual script can reshape its terminal glyph.
                // Validate the actual candidate; if needed, shorten to the next
                // legal boundary rather than trusting the original run's width.
                while let prefix = candidate {
                    if let presentation = singleLinePresentation(text: prefix, identity: identity, snapshot: snapshot,
                        displays: displays, protectedText: protectedText, allowsFitting: false) {
                        return presentation
                    }
                    candidate = VisibleSuggestionPrefix.select(text, maximumUTF16Count: prefix.utf16.count - 1,
                        protectedText: protectedText)
                }
                return nil
            }
        }

        let baselineY = caret.midY - ((font.ascender + font.descender) / 2)
        guard let verticalBounds = lineVerticalBounds(
            text: text,
            font: font,
            direction: direction,
            baselineY: baselineY,
            caret: caret,
            availableWidth: maxX - minX
        ) else { return nil }
        let glyphFrame = CGRect(
            x: minX,
            y: verticalBounds.minY,
            width: maxX - minX,
            height: verticalBounds.height
        )
        let hostPlaceholderBounds = snapshot.hostPlaceholderBounds.map {
            $0.intersection(visibleField)
        }.flatMap { bounds in
            !bounds.isNull && bounds.width > 0 && bounds.height > 0 ? bounds : nil
        }
        let frame = hostPlaceholderBounds.map { glyphFrame.union($0) } ?? glyphFrame
        guard isValidArea(frame), fullyContains(visibleField, frame) else {
            return nil
        }
        return GhostTextSingleLinePresentation(
            text: text,
            frame: frame,
            baselineY: baselineY,
            font: font,
            direction: direction,
            foregroundColor: GhostTextColor.resolve(for: snapshot.textStyle),
            masksHostPlaceholder: snapshot.masksHostPlaceholder,
            hostPlaceholderBounds: hostPlaceholderBounds
        )
    }

    private static func lineVerticalBounds(
        text: String,
        font: NSFont,
        direction: GhostTextWritingDirection,
        baselineY: CGFloat,
        caret: CGRect,
        availableWidth: CGFloat
    ) -> CGRect? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = switch direction {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let typographicWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard typographicWidth.isFinite, typographicWidth > 0,
              typographicWidth <= availableWidth
        else { return nil }
        let imageBounds = CTLineGetImageBounds(line, nil)
        let drawOriginX: CGFloat = direction == .rightToLeft
            ? availableWidth - typographicWidth : 0
        guard !imageBounds.isNull, !imageBounds.isInfinite,
              imageBounds.minX + drawOriginX >= 0,
              imageBounds.maxX + drawOriginX <= availableWidth
        else { return nil }
        let imageMinY = imageBounds.isNull ? baselineY : baselineY + imageBounds.minY
        let imageMaxY = imageBounds.isNull ? baselineY : baselineY + imageBounds.maxY
        let minY = floor(min(caret.minY, baselineY + font.descender, imageMinY))
        let maxY = ceil(max(caret.maxY, baselineY + font.ascender, imageMaxY))
        guard minY.isFinite, maxY.isFinite, maxY > minY else { return nil }
        return CGRect(x: 0, y: minY, width: 1, height: maxY - minY)
    }

    private static func writingDirection(
        textBefore: String,
        suggestion: String
    ) -> GhostTextWritingDirection? {
        let paragraphStart = textBefore.lastIndex(where: { $0.isNewline }).map {
            textBefore.index(after: $0)
        } ?? textBefore.startIndex
        for scalar in textBefore[paragraphStart...].unicodeScalars.reversed() {
            if let direction = strongDirection(scalar) { return direction }
        }
        for scalar in suggestion.unicodeScalars {
            if let direction = strongDirection(scalar) { return direction }
        }
        return nil
    }

    private static func strongDirection(
        _ scalar: Unicode.Scalar
    ) -> GhostTextWritingDirection? {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFC:
            return .rightToLeft
        default:
            return CharacterSet.letters.contains(scalar) ? .leftToRight : nil
        }
    }

    private static func isValidCaret(_ rect: CGRect) -> Bool {
        hasFiniteComponents(rect) && rect.size.width >= 0 && rect.size.height > 0
    }

    private static func isValidArea(_ rect: CGRect) -> Bool {
        hasFiniteComponents(rect) && rect.size.width > 0 && rect.size.height > 0
    }

    private static func hasFiniteComponents(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }

    private static func fullyContains(_ frame: CGRect, _ rect: CGRect) -> Bool {
        rect.minX >= frame.minX && rect.maxX <= frame.maxX
            && rect.minY >= frame.minY && rect.maxY <= frame.maxY
    }
}

extension ActiveFieldSnapshot {
    /// The host state implied by typing `typed` at the caret: the content and
    /// caret move, every identity field stays.
    func advanced(
        byTyping typed: String,
        caretBounds: CGRect,
        paragraphMetrics: ActiveFieldParagraphMetrics?
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: applicationBundleIdentifier,
            surface: surface,
            elementIdentifier: elementIdentifier,
            focusGeneration: focusGeneration,
            textBefore: BoundedText.suffix(
                (textBefore + typed)[...],
                maximumUTF16Units: 8_000
            ),
            selectedText: "",
            textAfter: textAfter,
            selectionRange: NSRange(
                location: selectionRange.location + typed.utf16.count,
                length: 0
            ),
            caretBounds: caretBounds,
            inputFrame: inputFrame,
            paragraphStartBounds: paragraphStartBounds,
            geometryQuality: geometryQuality,
            geometrySource: geometrySource,
            captureSequence: captureSequence,
            textStyle: textStyle,
            paragraphMetrics: paragraphMetrics,
            paragraphMetricsFailureReason: paragraphMetrics == nil
                ? paragraphMetricsFailureReason
                : nil,
            fieldKind: fieldKind,
            publicationStructure: publicationStructure,
            geometryStructure: geometryStructure,
            masksHostPlaceholder: false,
            hostPlaceholderBounds: nil,
            fieldContext: fieldContext
        )
    }
}
