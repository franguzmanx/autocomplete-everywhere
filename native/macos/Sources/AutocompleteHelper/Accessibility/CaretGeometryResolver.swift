import Foundation

enum CaretGeometrySource: Equatable, Sendable {
    case zeroLengthRange
    case precedingGrapheme
    case followingGrapheme
    /// Trailing edge of the current line box when the caret is at the end of
    /// its line. Chromium exposes line boxes but no per-character rectangles
    /// unless screen-reader mode is forced, so this is its measured caret.
    case lineEnd
    /// Leading edge of the current line box when the caret is at the start of
    /// its line (including an empty line).
    case lineStart

    var isLineEdge: Bool { self == .lineEnd || self == .lineStart }
}

enum CaretGeometryQuality: Equatable, Sendable {
    case exact
    case derived
}

enum CaretWritingDirection: Equatable, Sendable {
    case leftToRight
    case rightToLeft
}

enum CaretSelectionContext: Equatable, Sendable {
    case collapsedAtTextEnd
    case collapsedInText
    case other
}

struct CaretGeometryCandidate: Equatable, Sendable {
    let rect: CGRect
    let source: CaretGeometrySource
}

struct CaretGeometryInput: Sendable {
    let candidates: [CaretGeometryCandidate]
    let inputFrame: CGRect
    let measuredLineHeight: CGFloat?
    let writingDirection: CaretWritingDirection
    let displays: [DisplayGeometry]
    let selectionContext: CaretSelectionContext
}

struct ResolvedCaretGeometry: Equatable, Sendable {
    let rect: CGRect
    let source: CaretGeometrySource
    let quality: CaretGeometryQuality
}

enum CaretGeometryFailureReason: String, Equatable, Sendable {
    case noCandidates
    case invalidCandidateBounds
    case outsideInputFrame
    case lineHeightMismatch
    case displayUnavailable
    case conflictingCandidates
}

enum CaretGeometryOutcome: Equatable, Sendable {
    case resolved
    case failed(CaretGeometryFailureReason)
}

enum CaretBoundsState: String, Equatable, Sendable {
    case available
    case missing
    case invalid
}

struct CaretGeometryEvaluation: Equatable, Sendable {
    let geometry: ResolvedCaretGeometry?
    let displayMatched: Bool
    let outcome: CaretGeometryOutcome
}

enum CaretGeometryResolver {
    static func boundsState(
        _ rect: CGRect?,
        source: CaretGeometrySource
    ) -> CaretBoundsState {
        guard let rect else { return .missing }
        return basicBoundsAreValid(rect, source: source) ? .available : .invalid
    }

    static func resolve(_ input: CaretGeometryInput) -> ResolvedCaretGeometry? {
        evaluate(input).geometry
    }

    static func evaluate(
        _ input: CaretGeometryInput
    ) -> CaretGeometryEvaluation {
        guard !input.candidates.isEmpty else {
            return CaretGeometryEvaluation(
                geometry: nil,
                displayMatched: false,
                outcome: .failed(.noCandidates)
            )
        }
        let toleranceFrame = input.inputFrame.insetBy(dx: -4, dy: -4)
        var valid: [CaretGeometryCandidate] = []
        var failures: [CaretGeometryFailureReason] = []
        var displayMatched = false
        for candidate in input.candidates {
            guard boundsState(candidate.rect, source: candidate.source) == .available else {
                failures.append(.invalidCandidateBounds)
                continue
            }
            let caret = derivedCaret(from: candidate, direction: input.writingDirection)
            let candidateHasDisplay = DisplayCoordinateConverter.appKitRect(
                fromAccessibilityRect: candidate.rect,
                displays: input.displays
            ) != nil
            let caretHasDisplay = DisplayCoordinateConverter.appKitRect(
                fromAccessibilityRect: caret.rect,
                displays: input.displays
            ) != nil
            let hasDisplay = candidateHasDisplay && caretHasDisplay
            displayMatched = displayMatched || hasDisplay
            // Glyph ink and Chromium marker boxes may extend beyond a clipped
            // editor even when the caret edge itself is valid. The caret is the
            // anchor we render from, so validate that point rather than requiring
            // the entire source glyph rectangle to fit inside the field.
            guard isFullyContained(caret.rect, in: toleranceFrame)
            else {
                failures.append(.outsideInputFrame)
                continue
            }
            if let lineHeight = input.measuredLineHeight,
               lineHeight > 0,
               (candidate.rect.height < lineHeight * 0.6
                || candidate.rect.height > lineHeight * 1.4) {
                failures.append(.lineHeightMismatch)
                continue
            }
            guard hasDisplay else {
                failures.append(.displayUnavailable)
                continue
            }
            valid.append(caret)
        }
        // Prefer character geometry only after it passed field, display and
        // line-height validation. Merely receiving a glyph rectangle does not
        // prove it belongs to this editor. Line edges remain available when
        // all reported glyphs are unusable, and never conflict with valid ones.
        if valid.contains(where: { $0.source == .precedingGrapheme || $0.source == .followingGrapheme }) {
            valid.removeAll { $0.source.isLineEdge }
        }
        guard let selected = valid.sorted(by: {
            priority($0.source) < priority($1.source)
        }).first else {
            return CaretGeometryEvaluation(
                geometry: nil,
                displayMatched: displayMatched,
                outcome: .failed(preferredFailure(in: failures))
            )
        }
        let resolvedCandidate: CaretGeometryCandidate
        if valid.allSatisfy({ spatiallyConcordant($0.rect, selected.rect) }) {
            resolvedCandidate = selected
        } else if let preceding = terminalPrecedingCandidate(
            in: valid,
            selectionContext: input.selectionContext
        ) {
            resolvedCandidate = preceding
        } else if let consensus = adjacentGlyphConsensusCandidate(
            in: valid,
            selectionContext: input.selectionContext
        ) {
            resolvedCandidate = consensus
        } else {
            return CaretGeometryEvaluation(
                geometry: nil,
                displayMatched: displayMatched,
                outcome: .failed(.conflictingCandidates)
            )
        }
        guard let appKitRect = DisplayCoordinateConverter.appKitRect(
            fromAccessibilityRect: resolvedCandidate.rect,
            displays: input.displays
        ) else {
            return CaretGeometryEvaluation(
                geometry: nil,
                displayMatched: false,
                outcome: .failed(.displayUnavailable)
            )
        }
        return CaretGeometryEvaluation(
            geometry: ResolvedCaretGeometry(
                rect: appKitRect,
                source: resolvedCandidate.source,
                quality: resolvedCandidate.source == .zeroLengthRange ? .exact : .derived
            ),
            displayMatched: true,
            outcome: .resolved
        )
    }

    private static func priority(_ source: CaretGeometrySource) -> Int {
        switch source {
        case .zeroLengthRange: 0
        case .precedingGrapheme: 1
        case .followingGrapheme: 2
        case .lineEnd: 3
        case .lineStart: 4
        }
    }

    private static func basicBoundsAreValid(
        _ rect: CGRect,
        source: CaretGeometrySource
    ) -> Bool {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height > 0
        else { return false }
        switch source {
        case .zeroLengthRange:
            return rect.width <= max(4, rect.height * 0.25)
        case .precedingGrapheme, .followingGrapheme:
            return rect.width > 0
        case .lineEnd, .lineStart:
            // An empty line legitimately has a zero-width box.
            return true
        }
    }

    private static func spatiallyConcordant(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.midX - rhs.midX) <= 4 && abs(lhs.midY - rhs.midY) <= 2
    }

    private static func terminalPrecedingCandidate(
        in candidates: [CaretGeometryCandidate],
        selectionContext: CaretSelectionContext
    ) -> CaretGeometryCandidate? {
        guard selectionContext == .collapsedAtTextEnd,
              candidates.count == 2,
              candidates.contains(where: { $0.source == .zeroLengthRange }),
              let preceding = candidates.first(where: { $0.source == .precedingGrapheme })
        else { return nil }
        return preceding
    }

    private static func adjacentGlyphConsensusCandidate(
        in candidates: [CaretGeometryCandidate],
        selectionContext: CaretSelectionContext
    ) -> CaretGeometryCandidate? {
        guard selectionContext == .collapsedInText,
              candidates.count == 3,
              candidates.contains(where: { $0.source == .zeroLengthRange }),
              let preceding = candidates.first(where: { $0.source == .precedingGrapheme }),
              let following = candidates.first(where: { $0.source == .followingGrapheme }),
              spatiallyConcordant(preceding.rect, following.rect)
        else { return nil }
        return preceding
    }

    private static func derivedCaret(
        from candidate: CaretGeometryCandidate,
        direction: CaretWritingDirection
    ) -> CaretGeometryCandidate {
        guard candidate.source != .zeroLengthRange else { return candidate }
        let x: CGFloat
        switch (candidate.source, direction) {
        case (.precedingGrapheme, .leftToRight), (.followingGrapheme, .rightToLeft),
             (.lineEnd, .leftToRight), (.lineStart, .rightToLeft):
            x = candidate.rect.maxX
        case (.precedingGrapheme, .rightToLeft), (.followingGrapheme, .leftToRight),
             (.lineEnd, .rightToLeft), (.lineStart, .leftToRight):
            x = candidate.rect.minX
        case (.zeroLengthRange, _):
            x = candidate.rect.minX
        }
        return CaretGeometryCandidate(
            rect: CGRect(x: x, y: candidate.rect.minY, width: 0, height: candidate.rect.height),
            source: candidate.source
        )
    }

    private static func isFullyContained(_ rect: CGRect, in frame: CGRect) -> Bool {
        rect.minX >= frame.minX && rect.maxX <= frame.maxX
            && rect.minY >= frame.minY && rect.maxY <= frame.maxY
    }

    private static func preferredFailure(
        in failures: [CaretGeometryFailureReason]
    ) -> CaretGeometryFailureReason {
        for reason in [
            CaretGeometryFailureReason.outsideInputFrame,
            .lineHeightMismatch,
            .displayUnavailable,
            .invalidCandidateBounds,
        ] where failures.contains(reason) {
            return reason
        }
        return .invalidCandidateBounds
    }
}
