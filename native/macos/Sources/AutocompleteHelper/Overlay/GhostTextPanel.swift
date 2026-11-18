import AppKit
import CoreText

enum GhostTextTypography {
    static func style(for snapshot: ActiveFieldSnapshot) -> ActiveFieldTextStyle? {
        snapshot.textStyle ?? snapshot.paragraphMetrics?.textStyle
    }

    static func resolution(
        for style: ActiveFieldTextStyle?
    ) -> FixtureFontResolution {
        guard let style,
              style.fontSize.isFinite,
              style.fontSize > 0
        else { return .unavailable }
        if NSFont(name: style.fontName, size: style.fontSize) != nil {
            return .exact
        }
        return style.fontName.hasPrefix(".") ? .systemFallback : .unavailable
    }

    static func font(for style: ActiveFieldTextStyle?) -> NSFont? {
        guard
            let style,
            style.fontSize.isFinite,
            style.fontSize > 0
        else { return nil }
        if let exactFont = NSFont(name: style.fontName, size: style.fontSize) {
            return exactFont
        }
        guard style.fontName.hasPrefix(".") else { return nil }
        return NSFont.systemFont(ofSize: style.fontSize)
    }

}

@MainActor
enum GhostTextColor {
    static var opacity: CGFloat = 0.30
    static func resolve(for style: ActiveFieldTextStyle?) -> NSColor {
        guard let color = style?.foregroundColor else {
            return NSColor.labelColor.withAlphaComponent(opacity)
        }
        return NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: opacity
        )
    }
}

enum GhostTextWritingDirection: Equatable, Sendable {
    case leftToRight
    case rightToLeft
}

struct GhostTextSingleLinePresentation {
    let text: String
    let frame: CGRect
    let baselineY: CGFloat
    let font: NSFont
    let direction: GhostTextWritingDirection
    var foregroundColor: NSColor = .secondaryLabelColor
    var masksHostPlaceholder = false
    var hostPlaceholderBounds: CGRect? = nil
}

@MainActor
class GhostTextAccessibleView: NSView {
    var accessibleSuggestion: String?

    override func isAccessibilityElement() -> Bool {
        accessibleSuggestion != nil && window?.isVisible == true && window?.contentView === self
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { "Suggested text" }
    override func accessibilityValue() -> Any? {
        isAccessibilityElement() ? accessibleSuggestion : nil
    }
}

@MainActor
final class GhostTextLineView: GhostTextAccessibleView {
    private var line: CTLine?

    private(set) var text = ""
    private(set) var direction = GhostTextWritingDirection.leftToRight
    private(set) var baselineOffset: CGFloat = 0
    private(set) var drawOriginX: CGFloat = 0
    private(set) var placeholderMaskRect: CGRect?

    var lineCount: Int { line == nil ? 0 : 1 }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(with presentation: GhostTextSingleLinePresentation) {
        text = presentation.text
        direction = presentation.direction
        layer?.backgroundColor = presentation.masksHostPlaceholder
                && presentation.hostPlaceholderBounds == nil
            ? NSColor.textBackgroundColor.cgColor
            : NSColor.clear.cgColor
        placeholderMaskRect = presentation.hostPlaceholderBounds.map {
            $0.offsetBy(dx: -presentation.frame.minX, dy: -presentation.frame.minY)
                .intersection(bounds)
        }
        baselineOffset = presentation.baselineY - presentation.frame.minY
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = switch presentation.direction {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
        let attributed = NSAttributedString(
            string: presentation.text,
            attributes: [
                .font: presentation.font,
                .foregroundColor: presentation.foregroundColor,
                .paragraphStyle: paragraph,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        self.line = line
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        drawOriginX = switch presentation.direction {
        case .leftToRight: 0
        case .rightToLeft: max(0, presentation.frame.width - width)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let line, let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        if let placeholderMaskRect,
           !placeholderMaskRect.isNull,
           placeholderMaskRect.width > 0,
           placeholderMaskRect.height > 0 {
            // AX exposes the placeholder geometry and typography, but not its
            // CSS background. This semantic color follows system appearance
            // without mutating host text or adding a screen-capture permission.
            context.setFillColor(NSColor.textBackgroundColor.cgColor)
            context.fill(placeholderMaskRect)
        }
        context.saveGState()
        context.clip(to: bounds)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: drawOriginX, y: baselineOffset)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

@MainActor
final class GhostTextParagraphView: GhostTextAccessibleView {
    private struct DrawableSlice {
        let glyphRange: NSRange
        let horizontalDrawOffset: CGFloat
    }

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()
    private var drawableSlices: [DrawableSlice] = []

    private(set) var attributedText = NSAttributedString()
    private(set) var lineFragmentCount = 0
    private(set) var textOrigin = CGPoint.zero
    private(set) var completionLineSlices: [ParagraphMirrorLineSlice] = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        wantsLayer = true
        layer?.masksToBounds = true
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @discardableResult
    func update(with presentation: ParagraphMirrorLayoutResult) -> Bool {
        layer?.backgroundColor = presentation.masksHostPlaceholder
            ? NSColor.textBackgroundColor.cgColor
            : NSColor.clear.cgColor
        textContainer.containerSize = presentation.containerSize
        textStorage.setAttributedString(presentation.attributedText)
        layoutManager.ensureLayout(for: textContainer)

        var resolvedSlices: [DrawableSlice] = []
        for slice in presentation.completionLineSlices {
            var actualCharacterRange = NSRange()
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: slice.characterRange,
                actualCharacterRange: &actualCharacterRange
            )
            guard glyphRange.length > 0,
                  actualCharacterRange == slice.characterRange
            else {
                drawableSlices = []
                return false
            }
            resolvedSlices.append(
                DrawableSlice(
                    glyphRange: glyphRange,
                    horizontalDrawOffset: slice.horizontalDrawOffset
                )
            )
        }
        guard !resolvedSlices.isEmpty else {
            drawableSlices = []
            return false
        }

        attributedText = presentation.attributedText
        textOrigin = presentation.textOrigin
        completionLineSlices = presentation.completionLineSlices
        drawableSlices = resolvedSlices
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var fragmentCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            _, _, _, _, _ in fragmentCount += 1
        }
        lineFragmentCount = fragmentCount
        needsDisplay = true
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for slice in drawableSlices {
            let drawOrigin = CGPoint(
                x: textOrigin.x + slice.horizontalDrawOffset,
                y: textOrigin.y
            )
            layoutManager.drawBackground(
                forGlyphRange: slice.glyphRange,
                at: drawOrigin
            )
            layoutManager.drawGlyphs(
                forGlyphRange: slice.glyphRange,
                at: drawOrigin
            )
        }
    }
}

@MainActor
final class GhostTextPanel: NSPanel, GhostTextDisplaying {
    typealias OrderFrontAction = @MainActor (NSPanel) -> Void

    private let lineView = GhostTextLineView(frame: .zero)
    private let paragraphView = GhostTextParagraphView(frame: .zero)
    private let orderFrontAction: OrderFrontAction
    private var isShowing = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(
        orderFrontAction: @escaping OrderFrontAction = { panel in
            panel.orderFrontRegardless()
        }
    ) {
        self.orderFrontAction = orderFrontAction
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = lineView
    }

    @discardableResult
    func showSingleLine(_ presentation: GhostTextSingleLinePresentation) -> Bool {
        guard Self.isValid(presentation) else { dismiss(); return false }

        setFrame(presentation.frame, display: false, animate: false)
        if contentView !== lineView { contentView = lineView }
        lineView.update(with: presentation)
        guard orderIfNeeded() else { dismiss(); return false }
        displayIfNeeded()
        publishAccessibility(presentation.text, in: lineView)
        return true
    }

    @discardableResult
    func showParagraphMirror(_ presentation: ParagraphMirrorLayoutResult) -> Bool {
        guard Self.isValid(presentation) else { dismiss(); return false }
        guard paragraphView.update(with: presentation) else { dismiss(); return false }

        setFrame(presentation.frame, display: false, animate: false)
        if contentView !== paragraphView { contentView = paragraphView }
        guard orderIfNeeded() else { dismiss(); return false }
        displayIfNeeded()
        publishAccessibility(
            presentation.attributedText.attributedSubstring(from: presentation.completionRange).string,
            in: paragraphView
        )
        return true
    }

    func dismiss() {
        lineView.accessibleSuggestion = nil
        paragraphView.accessibleSuggestion = nil
        guard isShowing else { return }
        isShowing = false
        orderOut(nil)
    }

    private func publishAccessibility(_ text: String, in view: GhostTextAccessibleView) {
        let changed = view.accessibleSuggestion != text
        lineView.accessibleSuggestion = nil
        paragraphView.accessibleSuggestion = nil
        view.accessibleSuggestion = text
        if changed { NSAccessibility.post(element: view, notification: .valueChanged) }
    }

    private func orderIfNeeded() -> Bool {
        if !isShowing || !isVisible {
            isShowing = true
            orderFrontAction(self)
        }

        guard isVisible else {
            isShowing = false
            orderOut(nil)
            return false
        }
        return true
    }

    private static func isValid(
        _ presentation: GhostTextSingleLinePresentation
    ) -> Bool {
        let frame = presentation.frame
        let localBaseline = presentation.baselineY - frame.minY
        return !presentation.text.isEmpty
            && !presentation.text.contains(where: { $0.isNewline })
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
            && presentation.baselineY.isFinite
            && localBaseline >= 0
            && localBaseline <= frame.height
    }

    private static func isValid(
        _ presentation: ParagraphMirrorLayoutResult
    ) -> Bool {
        let frame = presentation.frame
        let range = presentation.completionRange
        return frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
            && range.location >= 0
            && range.length > 0
            && NSMaxRange(range) <= presentation.attributedText.length
            && presentation.containerSize.width.isFinite
            && presentation.containerSize.height.isFinite
            && presentation.containerSize.width > 0
            && presentation.containerSize.height > 0
            && presentation.textOrigin.x.isFinite
            && presentation.textOrigin.y.isFinite
            && !presentation.lineFragments.isEmpty
            && !presentation.completionLineSlices.isEmpty
            && presentation.completionLineSlices.allSatisfy {
                $0.characterRange.location >= presentation.completionRange.location
                    && NSMaxRange($0.characterRange)
                        <= NSMaxRange(presentation.completionRange)
                    && $0.characterRange.length > 0
                    && $0.horizontalDrawOffset.isFinite
                    && abs($0.horizontalDrawOffset) <= 8
            }
    }
}
