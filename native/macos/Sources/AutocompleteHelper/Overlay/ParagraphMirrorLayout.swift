import AppKit
import Foundation

@MainActor
struct ParagraphMirrorLineSlice: Equatable {
    let characterRange: NSRange
    let horizontalDrawOffset: CGFloat
    let bounds: CGRect
}

@MainActor
struct ParagraphMirrorLayoutResult {
    let attributedText: NSAttributedString
    let completionRange: NSRange
    let containerSize: CGSize
    let frame: CGRect
    let textOrigin: CGPoint
    let lineFragments: [CGRect]
    let completionLineSlices: [ParagraphMirrorLineSlice]
    let anchor: CGRect
    var masksHostPlaceholder = false
}

enum ParagraphMirrorLayoutFailureReason: String, Equatable, Sendable {
    case invalidInput = "invalid_input"
    case lineHeightMismatch = "line_height_mismatch"
    case fontUnavailable = "font_unavailable"
    case anchorOutsideParagraph = "anchor_outside_paragraph"
    case styleFontUnavailable = "style_font_unavailable"
    case glyphRange = "glyph_range"
    case insertionBoundary = "insertion_boundary"
    case horizontalDrift = "horizontal_drift"
    case verticalDrift = "vertical_drift"
    case alignment = "alignment"
    case fragments = "fragments"
    case usedRect = "used_rect"
}

@MainActor
struct ParagraphMirrorLayoutEvaluation {
    let presentation: ParagraphMirrorLayoutResult?
    let failureReason: ParagraphMirrorLayoutFailureReason?
}

@MainActor
enum ParagraphMirrorLayout {
    static func validated(
        surface: WritingSurface,
        backingScaleFactor: CGFloat = 1,
        metrics: ActiveFieldParagraphMetrics,
        completion: String,
        caretBounds: CGRect
    ) -> ParagraphMirrorLayoutResult? {
        evaluate(
            surface: surface,
            backingScaleFactor: backingScaleFactor,
            metrics: metrics,
            completion: completion,
            caretBounds: caretBounds
        ).presentation
    }

    /// The complete paragraph laid out once and aligned to the measured
    /// caret. Both the presentation and the type-through prediction derive
    /// from the same alignment.
    private struct AlignedLayout {
        let attributed: NSMutableAttributedString
        // NSLayoutManager does not retain its NSTextStorage. Keep the storage
        // alive for every fragment and predicted-caret query performed after
        // `align` returns.
        let textStorage: NSTextStorage
        let font: NSFont
        let layoutManager: NSLayoutManager
        let container: NSTextContainer
        let completionRange: NSRange
        let completionGlyphRange: NSRange
        let boundary: CGFloat
        let residualDrawOffset: CGFloat
        let insertionLineRect: CGRect
        let layoutOriginX: CGFloat
        let layoutTopY: CGFloat
        let anchorX: CGFloat
    }

    private enum Alignment {
        case aligned(AlignedLayout)
        case rejected(ParagraphMirrorLayoutFailureReason)
    }

    private static func align(
        metrics: ActiveFieldParagraphMetrics,
        completion: String,
        caretBounds: CGRect,
        backingScaleFactor: CGFloat
    ) -> Alignment {
        guard valid(metrics),
              valid(caretBounds),
              backingScaleFactor.isFinite,
              backingScaleFactor > 0,
              !completion.isEmpty
        else { return .rejected(.invalidInput) }
        guard abs(caretBounds.height - metrics.lineHeight) <= 1 else {
            return .rejected(.lineHeightMismatch)
        }
        guard let font = GhostTextTypography.font(for: metrics.textStyle) else {
            return .rejected(.fontUnavailable)
        }

        let anchorX = switch metrics.writingDirection {
        case .leftToRight: caretBounds.maxX
        case .rightToLeft: caretBounds.minX
        }
        guard anchorX >= metrics.origin.x,
              anchorX <= metrics.origin.x + metrics.width
        else { return .rejected(.anchorOutsideParagraph) }

        let prefix = metrics.textBeforeCaret
        let completeText = prefix + completion
        let prefixRange = NSRange(location: 0, length: prefix.utf16.count)
        let completionRange = NSRange(
            location: prefixRange.length,
            length: completion.utf16.count
        )
        let attributed = NSMutableAttributedString(
            string: completeText,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.clear,
                .paragraphStyle: paragraphStyle(for: metrics),
            ]
        )
        if let insertionIndent = metrics.insertionLineHeadIndent {
            let firstParagraph = paragraphStyle(for: metrics).mutableCopy() as! NSMutableParagraphStyle
            firstParagraph.firstLineHeadIndent = insertionIndent
            attributed.addAttribute(
                .paragraphStyle,
                value: firstParagraph,
                range: (completeText as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            )
        }
        for run in metrics.prefixStyleRuns {
            guard let runFont = GhostTextTypography.font(for: run.style) else {
                return .rejected(.styleFontUnavailable)
            }
            attributed.addAttribute(.font, value: runFont, range: run.range)
        }
        attributed.addAttribute(
            .foregroundColor,
            value: GhostTextColor.resolve(for: metrics.textStyle),
            range: completionRange
        )

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let layoutContainerSize = CGSize(
            width: metrics.width,
            height: .greatestFiniteMagnitude
        )
        let container = NSTextContainer(containerSize: layoutContainerSize)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let targetBoundary = anchorX - metrics.origin.x
        guard var resolved = resolvedCompletion(
            layoutManager: layoutManager,
            completionRange: completionRange
        ) else {
            return .rejected(.glyphRange)
        }
        let residualDrawOffset = targetBoundary - resolved.boundary
        // AX range bounds and TextKit can disagree by a fraction of an em,
        // especially when the host and TextKit resolve different fallback
        // fonts for RTL scripts. A discrepancy below half the measured line
        // height is still a single, unambiguous insertion boundary. The
        // shared panel accepts at most 8 pt of draw offset; its remaining
        // 1 pt alignment tolerance covers sub-point measurement error.
        let maximumDrawOffset: CGFloat = 8
        let maximumAlignmentError: CGFloat = 1
        let maximumCaretCalibration = min(
            maximumDrawOffset + maximumAlignmentError,
            metrics.lineHeight / 2
        )
        var calibratedResidual = residualDrawOffset
        if metrics.writingDirection == .leftToRight,
           abs(calibratedResidual) > maximumCaretCalibration {
            let prefixGlyphRange = layoutManager.glyphRange(
                forCharacterRange: prefixRange,
                actualCharacterRange: nil
            )
            let minimumTrackingSample = 64
            guard prefixGlyphRange.length >= minimumTrackingSample else {
                return .rejected(.horizontalDrift)
            }
            let tracking = calibratedResidual / CGFloat(prefixGlyphRange.length)
            guard tracking.isFinite, abs(tracking) <= 0.125 else {
                return .rejected(.horizontalDrift)
            }
            attributed.addAttribute(
                .kern,
                value: tracking,
                range: NSRange(location: 0, length: attributed.length)
            )
            storage.setAttributedString(attributed)
            layoutManager.ensureLayout(for: container)
            guard let calibrated = resolvedCompletion(
                layoutManager: layoutManager,
                completionRange: completionRange
            ) else {
                return .rejected(.glyphRange)
            }
            resolved = calibrated
            calibratedResidual = targetBoundary - calibrated.boundary
        }
        guard calibratedResidual.isFinite,
              abs(calibratedResidual) <= maximumCaretCalibration
        else { return .rejected(.horizontalDrift) }
        calibratedResidual = min(
            maximumDrawOffset,
            max(-maximumDrawOffset, calibratedResidual)
        )

        let insertionLineRect = layoutManager.lineFragmentRect(
            forGlyphAt: resolved.glyphRange.location,
            effectiveRange: nil
        )
        let rawCaretMinY = metrics.origin.y
            - insertionLineRect.minY
            - metrics.lineHeight
        let verticalAdjustment = caretBounds.minY - rawCaretMinY
        guard verticalAdjustment.isFinite,
              abs(verticalAdjustment) <= 1
        else { return .rejected(.verticalDrift) }

        let layoutOriginX = metrics.origin.x
        let layoutTopY = metrics.origin.y + verticalAdjustment
        let alignedBoundary = layoutOriginX + resolved.boundary + calibratedResidual
        let alignedCaretMinY = layoutTopY
            - insertionLineRect.minY
            - metrics.lineHeight
        guard abs(alignedBoundary - anchorX) <= maximumAlignmentError,
              abs(alignedCaretMinY - caretBounds.minY) <= 1
        else { return .rejected(.alignment) }

        return .aligned(AlignedLayout(
            attributed: attributed,
            textStorage: storage,
            font: font,
            layoutManager: layoutManager,
            container: container,
            completionRange: completionRange,
            completionGlyphRange: resolved.glyphRange,
            boundary: resolved.boundary,
            residualDrawOffset: calibratedResidual,
            insertionLineRect: insertionLineRect,
            layoutOriginX: layoutOriginX,
            layoutTopY: layoutTopY,
            anchorX: anchorX
        ))
    }

    static func evaluate(
        surface: WritingSurface,
        backingScaleFactor: CGFloat = 1,
        metrics: ActiveFieldParagraphMetrics,
        completion: String,
        caretBounds: CGRect,
        masksHostPlaceholder: Bool = false
    ) -> ParagraphMirrorLayoutEvaluation {
        func rejected(
            _ reason: ParagraphMirrorLayoutFailureReason
        ) -> ParagraphMirrorLayoutEvaluation {
            ParagraphMirrorLayoutEvaluation(
                presentation: nil,
                failureReason: reason
            )
        }

        let aligned: AlignedLayout
        switch align(
            metrics: metrics,
            completion: completion,
            caretBounds: caretBounds,
            backingScaleFactor: backingScaleFactor
        ) {
        case let .aligned(layout):
            aligned = layout
        case let .rejected(reason):
            return rejected(reason)
        }
        let layoutManager = aligned.layoutManager
        let container = aligned.container
        let completionGlyphRange = aligned.completionGlyphRange
        let completionRange = aligned.completionRange
        let boundary = aligned.boundary
        let residualDrawOffset = aligned.residualDrawOffset
        let layoutOriginX = aligned.layoutOriginX
        let layoutTopY = aligned.layoutTopY

        func project(_ rect: CGRect, horizontalOffset: CGFloat) -> CGRect {
            var minX = layoutOriginX
                + rect.minX
                + horizontalOffset
            var maxX = layoutOriginX
                + rect.maxX
                + horizontalOffset
            let measuredMinX = metrics.origin.x
            let measuredMaxX = metrics.origin.x + metrics.width
            if abs(minX - measuredMinX) <= 0.01 { minX = measuredMinX }
            if abs(maxX - measuredMaxX) <= 0.01 { maxX = measuredMaxX }
            return CGRect(
                x: minX,
                y: layoutTopY - rect.maxY,
                width: max(0, maxX - minX),
                height: rect.height
            )
        }

        var localFragments: [(rect: CGRect, horizontalOffset: CGFloat)] = []
        var completionLineSlices: [ParagraphMirrorLineSlice] = []
        let fullText = aligned.attributed.string as NSString
        layoutManager.enumerateLineFragments(
            forGlyphRange: completionGlyphRange
        ) { _, usedRect, _, lineGlyphRange, _ in
            let slice = NSIntersectionRange(
                completionGlyphRange,
                lineGlyphRange
            )
            guard slice.length > 0 else { return }
            let isInsertionLine = NSLocationInRange(
                completionGlyphRange.location,
                lineGlyphRange
            )
            let lineHorizontalOffset = isInsertionLine
                ? residualDrawOffset
                : 0
            var characterSlice = NSIntersectionRange(
                completionRange,
                layoutManager.characterRange(
                    forGlyphRange: slice,
                    actualGlyphRange: nil
                )
            )
            while characterSlice.length > 0,
                  isLineBreak(
                    fullText.character(at: NSMaxRange(characterSlice) - 1)
                  ) {
                characterSlice.length -= 1
            }


            let visualFragments: [CGRect]
            if characterSlice.length > 0 {
                let visibleGlyphRange = NSIntersectionRange(
                    slice,
                    layoutManager.glyphRange(
                        forCharacterRange: characterSlice,
                        actualCharacterRange: nil
                    )
                )
                if visibleGlyphRange.length > 0 {
                    visualFragments = enclosingRects(
                        layoutManager: layoutManager,
                        glyphRange: visibleGlyphRange,
                        lineMinY: usedRect.minY,
                        lineHeight: usedRect.height,
                        container: container
                    )
                } else {
                    visualFragments = []
                }
            } else {
                visualFragments = []
            }

            let fragments = visualFragments.isEmpty
                ? [CGRect(
                    x: boundary,
                    y: usedRect.minY,
                    width: 0,
                    height: usedRect.height
                )]
                : visualFragments
            if characterSlice.length > 0 {
                let bounds = fragments.map { project($0, horizontalOffset: lineHorizontalOffset) }
                    .reduce(CGRect.null) { $0.union($1) }
                completionLineSlices.append(.init(characterRange: characterSlice,
                    horizontalDrawOffset: lineHorizontalOffset, bounds: bounds))
            }
            localFragments.append(
                contentsOf: fragments.map {
                    (rect: $0, horizontalOffset: lineHorizontalOffset)
                }
            )
        }
        guard !localFragments.isEmpty, !completionLineSlices.isEmpty else {
            return rejected(.fragments)
        }

        let fragments = localFragments.map { project($0.rect, horizontalOffset: $0.horizontalOffset) }
        let visibleFragments = fragments.filter {
            $0.width > 0 && $0.height > 0
        }
        guard let firstVisible = visibleFragments.first else {
            return rejected(.fragments)
        }
        let visibleBounds = visibleFragments.dropFirst().reduce(firstVisible) {
            $0.union($1)
        }
        let frame = visibleBounds.standardized
        guard frame.width > 0, frame.height > 0 else {
            return rejected(.fragments)
        }

        let fullGlyphRange = layoutManager.glyphRange(for: container)
        let usedRect = layoutManager.usedRect(for: container)
        guard fullGlyphRange.length > 0,
              usedRect.height.isFinite,
              usedRect.height > 0
        else { return rejected(.usedRect) }
        let textOrigin = CGPoint(
            x: layoutOriginX - frame.minX,
            y: frame.maxY - layoutTopY + baselineOffset(
                surface: surface,
                backingScaleFactor: backingScaleFactor,
                metrics: metrics,
                font: aligned.font,
                layoutManager: layoutManager,
                glyphRange: fullGlyphRange
            )
        )
        let resolvedContainerSize = CGSize(
            width: metrics.width,
            height: ceil(usedRect.maxY)
        )
        guard resolvedContainerSize.height > 0 else {
            return rejected(.usedRect)
        }
        return ParagraphMirrorLayoutEvaluation(
            presentation: ParagraphMirrorLayoutResult(
                attributedText: aligned.attributed,
                completionRange: completionRange,
                containerSize: resolvedContainerSize,
                frame: frame,
                textOrigin: textOrigin,
                lineFragments: fragments,
                completionLineSlices: completionLineSlices,
                anchor: caretBounds,
                masksHostPlaceholder: masksHostPlaceholder
            ),
            failureReason: nil
        )
    }

    /// Where the host caret will be after the user types the first
    /// `typedUTF16Length` code units of `completion`. The paragraph string is
    /// unchanged by type-through, so the aligned layout already contains the
    /// answer: the insertion point of the next completion character.
    static func predictedCaret(
        backingScaleFactor: CGFloat = 1,
        metrics: ActiveFieldParagraphMetrics,
        completion: String,
        caretBounds: CGRect,
        typedUTF16Length: Int
    ) -> CGRect? {
        guard typedUTF16Length > 0,
              typedUTF16Length < completion.utf16.count,
              case let .aligned(aligned) = align(
                  metrics: metrics,
                  completion: completion,
                  caretBounds: caretBounds,
                  backingScaleFactor: backingScaleFactor
              )
        else { return nil }
        let layoutManager = aligned.layoutManager
        let characterIndex = aligned.completionRange.location + typedUTF16Length
        guard characterIndex < aligned.attributed.length else { return nil }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex != NSNotFound,
              let boundary = insertionBoundary(
                  layoutManager: layoutManager,
                  characterIndex: characterIndex,
                  glyphIndex: glyphIndex
              )
        else { return nil }
        var lineGlyphRange = NSRange()
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &lineGlyphRange
        )
        let isInsertionLine = NSLocationInRange(
            aligned.completionGlyphRange.location,
            lineGlyphRange
        )
        let x = aligned.layoutOriginX + boundary
            + (isInsertionLine ? aligned.residualDrawOffset : 0)
        let minY = aligned.layoutTopY - lineRect.minY - metrics.lineHeight
        guard x.isFinite, minY.isFinite else { return nil }
        return CGRect(x: x, y: minY, width: 0, height: caretBounds.height)
    }

    private static func insertionBoundary(
        layoutManager: NSLayoutManager,
        characterIndex: Int,
        glyphIndex: Int
    ) -> CGFloat? {
        let count = layoutManager.getLineFragmentInsertionPoints(
            forCharacterAt: characterIndex,
            alternatePositions: false,
            inDisplayOrder: false,
            positions: nil,
            characterIndexes: nil
        )
        guard count > 0 else { return nil }
        var positions = Array(repeating: CGFloat.zero, count: count)
        var characterIndexes = Array(repeating: 0, count: count)
        let resolvedCount = positions.withUnsafeMutableBufferPointer {
            positionBuffer in
            characterIndexes.withUnsafeMutableBufferPointer {
                characterIndexBuffer in
                layoutManager.getLineFragmentInsertionPoints(
                    forCharacterAt: characterIndex,
                    alternatePositions: false,
                    inDisplayOrder: false,
                    positions: positionBuffer.baseAddress,
                    characterIndexes: characterIndexBuffer.baseAddress
                )
            }
        }
        guard resolvedCount == count else { return nil }

        let matches = zip(positions, characterIndexes)
            .filter { $0.1 == characterIndex }
            .map(\.0)
        guard let position = matches.first,
              matches.allSatisfy({ abs($0 - position) <= 0.01 })
        else { return nil }

        var lineGlyphRange = NSRange()
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &lineGlyphRange
        )
        guard NSLocationInRange(glyphIndex, lineGlyphRange) else { return nil }
        return lineRect.minX + position
    }

    private static func resolvedCompletion(
        layoutManager: NSLayoutManager,
        completionRange: NSRange
    ) -> (glyphRange: NSRange, boundary: CGFloat)? {
        var actualCharacterRange = NSRange()
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: completionRange,
            actualCharacterRange: &actualCharacterRange
        )
        guard glyphRange.length > 0,
              actualCharacterRange == completionRange,
              let boundary = insertionBoundary(
                layoutManager: layoutManager,
                characterIndex: completionRange.location,
                glyphIndex: glyphRange.location
              )
        else { return nil }
        return (glyphRange, boundary)
    }

    private static func enclosingRects(
        layoutManager: NSLayoutManager,
        glyphRange: NSRange,
        lineMinY: CGFloat,
        lineHeight: CGFloat,
        container: NSTextContainer
    ) -> [CGRect] {
        var rects: [CGRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: glyphRange,
            in: container
        ) { rect, _ in
            guard rect.width > 0 else { return }
            rects.append(
                CGRect(
                    x: rect.minX,
                    y: lineMinY,
                    width: rect.width,
                    height: lineHeight
                )
            )
        }
        return rects
    }

    private static func isLineBreak(_ codeUnit: unichar) -> Bool {
        switch codeUnit {
        case 0x000A, 0x000B, 0x000C, 0x000D, 0x0085, 0x2028, 0x2029:
            true
        default:
            false
        }
    }

    private static func baselineOffset(
        surface: WritingSurface,
        backingScaleFactor: CGFloat,
        metrics: ActiveFieldParagraphMetrics,
        font: NSFont,
        layoutManager: NSLayoutManager,
        glyphRange: NSRange
    ) -> CGFloat {
        guard surface.isWebContent, glyphRange.length > 0 else { return 0 }
        let textKitBaseline = layoutManager.location(
            forGlyphAt: glyphRange.location
        ).y
        let fontLineHeight = font.ascender - font.descender + font.leading
        let cssBaseline = (metrics.lineHeight - fontLineHeight) / 2
            + font.ascender
        let opticalCorrection = 1 / backingScaleFactor
        let offset = cssBaseline - textKitBaseline - opticalCorrection
        return offset.isFinite ? offset : 0
    }

    private static func paragraphStyle(
        for metrics: ActiveFieldParagraphMetrics
    ) -> NSParagraphStyle {
        let source = metrics.attributes
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = switch metrics.writingDirection {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = metrics.lineHeight
        paragraph.maximumLineHeight = metrics.lineHeight
        paragraph.firstLineHeadIndent = source.firstLineHeadIndent
        paragraph.headIndent = source.headIndent
        paragraph.tailIndent = source.tailIndent
        paragraph.lineSpacing = source.lineSpacing
        paragraph.paragraphSpacingBefore = source.paragraphSpacingBefore
        paragraph.paragraphSpacing = source.paragraphSpacingAfter
        paragraph.tabStops = source.tabStops.map {
            NSTextTab(textAlignment: .left, location: $0)
        }
        return paragraph
    }

    private static func valid(_ caret: CGRect) -> Bool {
        !caret.isNull
            && !caret.isInfinite
            && caret.origin.x.isFinite
            && caret.origin.y.isFinite
            && caret.size.width.isFinite
            && caret.size.height.isFinite
            && caret.size.width >= 0
            && caret.size.height > 0
    }

    private static func valid(_ metrics: ActiveFieldParagraphMetrics) -> Bool {
        let attributes = metrics.attributes
        let values = [
            metrics.origin.x,
            metrics.origin.y,
            metrics.width,
            metrics.lineHeight,
            metrics.textStyle.fontSize,
            attributes.firstLineHeadIndent,
            attributes.headIndent,
            attributes.tailIndent,
            attributes.lineSpacing,
            attributes.paragraphSpacingBefore,
            attributes.paragraphSpacingAfter,
        ] + attributes.tabStops + [metrics.insertionLineHeadIndent ?? 0]
        let prefixLength = metrics.textBeforeCaret.utf16.count
        var nextStyleLocation = 0
        let hasCompleteStyleCoverage = metrics.prefixStyleRuns.allSatisfy { run in
            guard run.range.location == nextStyleLocation,
                  run.range.length > 0,
                  run.style.fontSize.isFinite,
                  run.style.fontSize > 0,
                  !run.style.fontName.isEmpty
            else { return false }
            nextStyleLocation = NSMaxRange(run.range)
            return nextStyleLocation <= prefixLength
        } && nextStyleLocation == prefixLength
        return metrics.textBeforeCaret.utf16.count <= 2_000
            && values.allSatisfy(\.isFinite)
            && metrics.width > 0
            && metrics.lineHeight > 0
            && metrics.textStyle.fontSize > 0
            && hasCompleteStyleCoverage
            && attributes.listMarker == nil
            && attributes.listLevel == nil
            && attributes.tabStops.allSatisfy { $0 >= 0 }
    }
}
