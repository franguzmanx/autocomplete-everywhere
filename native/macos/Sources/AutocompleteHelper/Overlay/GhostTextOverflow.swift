import Foundation

/// Categorical geometry only. No content, coordinates, app or field identity.
struct GhostTextOverflow: Equatable, Sendable {
    enum Amount: String, Sendable {
        case none, subpixel, small, line
        case multipleLines = "multiple_lines"

        init(_ points: CGFloat, lineHeight: CGFloat) {
            switch points {
            case ...0: self = .none
            case ...1: self = .subpixel
            case ...2: self = .small
            case ...lineHeight: self = .line
            default: self = .multipleLines
            }
        }
    }

    enum Fitting: String, Sendable {
        case notAllowed = "not_allowed", noVisibleLine = "no_visible_line"
        case noSafeBoundary = "no_safe_boundary", relayoutRejected = "relayout_rejected", fitted
    }
    var fitting: Fitting = .notAllowed

    let left: Amount
    let right: Amount
    let top: Amount
    let bottom: Amount
    let completionLines: Int
    let availableLines: Int

    init(frame: CGRect, visibleField: CGRect, caret: CGRect, lineHeight: CGFloat, completionLines: Int) {
        left = Amount(visibleField.minX - frame.minX, lineHeight: lineHeight)
        right = Amount(frame.maxX - visibleField.maxX, lineHeight: lineHeight)
        top = Amount(frame.maxY - visibleField.maxY, lineHeight: lineHeight)
        bottom = Amount(visibleField.minY - frame.minY, lineHeight: lineHeight)
        self.completionLines = min(9, max(0, completionLines))
        let capacity = lineHeight > 0 ? floor((caret.maxY - visibleField.minY) / lineHeight) : 0
        availableLines = capacity.isFinite ? Int(min(9, max(0, capacity))) : 0
    }
}
