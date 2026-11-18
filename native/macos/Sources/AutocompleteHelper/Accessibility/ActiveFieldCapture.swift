import ApplicationServices
import AppKit
import Foundation

struct AccessibilityElement {
    let identifier: String
    let rawValue: AXUIElement?

    init(identifier: String, rawValue: AXUIElement? = nil) {
        self.identifier = identifier
        self.rawValue = rawValue
    }
}

protocol AccessibilityReading {
    func frontmostApplicationBundleIdentifier() -> String?
    func frontmostProcessIdentifier() -> Int32?
    func userInterfaceIdentifier(for element: AccessibilityElement) -> String?
    func sourceContexts(for element: AccessibilityElement) -> [FieldSource]
    func focusedElement() -> AccessibilityElement?
    func prepareFrontmostWebContent()
    func applicationBundleIdentifier(for element: AccessibilityElement) -> String?
    func processIdentifier(for element: AccessibilityElement) -> Int32?
    func isWebContentElement(_ element: AccessibilityElement) -> Bool
    func prepareWebContent(for element: AccessibilityElement) -> AccessibilityElement
    func webTextContext(for element: AccessibilityElement) -> WebTextContext?
    func role(for element: AccessibilityElement) -> String?
    func subrole(for element: AccessibilityElement) -> String?
    func stringValue(for element: AccessibilityElement) -> String?
    func selectedTextRange(for element: AccessibilityElement) -> NSRange?
    func bounds(for range: NSRange, in element: AccessibilityElement) -> CGRect?
    func frame(for element: AccessibilityElement) -> CGRect?
    func textStyle(for range: NSRange, in element: AccessibilityElement) -> ActiveFieldTextStyle?
    func textStyleRuns(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> [ActiveFieldTextStyleRun]?
    func paragraphAttributes(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> ActiveFieldParagraphAttributes?
    func displayGeometries() -> [DisplayGeometry]
}

extension AccessibilityReading {
    func userInterfaceIdentifier(for element: AccessibilityElement) -> String? { nil }
    func sourceContexts(for element: AccessibilityElement) -> [FieldSource] { [] }
    func frontmostApplicationBundleIdentifier() -> String? { nil }
    func frontmostProcessIdentifier() -> Int32? { nil }
    func prepareFrontmostWebContent() {}

    func processIdentifier(for element: AccessibilityElement) -> Int32? { nil }

    func isWebContentElement(_ element: AccessibilityElement) -> Bool { false }

    func prepareWebContent(for element: AccessibilityElement) -> AccessibilityElement { element }

    func webTextContext(for element: AccessibilityElement) -> WebTextContext? { nil }

    func frame(for element: AccessibilityElement) -> CGRect? { nil }

    func textStyle(for range: NSRange, in element: AccessibilityElement) -> ActiveFieldTextStyle? {
        nil
    }

    func textStyleRuns(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> [ActiveFieldTextStyleRun]? {
        textStyle(for: range, in: element).map {
            [ActiveFieldTextStyleRun(
                range: NSRange(location: 0, length: range.length),
                style: $0
            )]
        }
    }

    func paragraphAttributes(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> ActiveFieldParagraphAttributes? { nil }

    func displayGeometries() -> [DisplayGeometry] { [] }
}

enum ActiveFieldSkipReason: Equatable, Sendable {
    case accessibilityUnavailable
    case unsupportedApplication
    case unsupportedRole
    case secureField
    case valueMissing
    case rangeMissing
    case rangeOutOfBounds
    case markerReadFailed

    var isTransientReadFailure: Bool {
        switch self {
        case .accessibilityUnavailable, .valueMissing, .rangeMissing,
             .rangeOutOfBounds, .markerReadFailed:
            true
        case .unsupportedApplication, .unsupportedRole, .secureField:
            false
        }
    }
}

enum GeometryQuality: Equatable, Sendable {
    case exact
    case derived
    case unavailable
}

private enum CaretWritingDirectionResolution {
    case resolved(CaretWritingDirection)
    case neutral
    case ambiguous
}

struct ActiveFieldTextColor: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
}

struct ActiveFieldTextStyle: Equatable, Sendable {
    let fontName: String
    let fontSize: CGFloat
    let isEstimated: Bool
    let foregroundColor: ActiveFieldTextColor?

    init(
        fontName: String,
        fontSize: CGFloat,
        foregroundColor: ActiveFieldTextColor? = nil,
        isEstimated: Bool = false
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.foregroundColor = foregroundColor
        self.isEstimated = isEstimated
    }

}

struct ActiveFieldTextStyleRun: Equatable, Sendable {
    let range: NSRange
    let style: ActiveFieldTextStyle
}

enum ActiveFieldParagraphMetricsFailureReason: String, Equatable, Sendable {
    case empty
    case tooLong = "too_long"
    case directionUnavailable = "direction_unavailable"
    case paragraphStartUnavailable = "paragraph_start_unavailable"
    case inputFrameUnavailable = "input_frame_unavailable"
    case caretUnavailable = "caret_unavailable"
    case styleRunsUnavailable = "style_runs_unavailable"
    case styleCoverageInvalid = "style_coverage_invalid"
    case paragraphAttributesUnavailable = "paragraph_attributes_unavailable"
    case listUnsupported = "list_unsupported"
    case lineHeightInvalid = "line_height_invalid"
    case lineHeightMismatch = "line_height_mismatch"
    case boundsInvalid = "bounds_invalid"
}

enum ActiveFieldSelectionPosition: String, Equatable, Sendable {
    case start
    case middle
    case end
}

enum ActiveFieldTerminalClass: String, Equatable, Sendable {
    case empty
    case newline
    case space
    case letter
    case other
}

struct ActiveFieldPublicationStructure: Equatable, Sendable {
    let selectionPosition: ActiveFieldSelectionPosition
    let selectionCollapsed: Bool
    let textBeforeTerminal: ActiveFieldTerminalClass
    let textAfterIsEmpty: Bool
    let valueTerminal: ActiveFieldTerminalClass
}

enum ActiveFieldDirectionState: String, Equatable, Sendable {
    case leftToRight
    case rightToLeft
    case neutral
    case ambiguous
}

enum ActiveFieldResolverOutcome: Equatable, Sendable {
    case notRun
    case resolved
    case failed(CaretGeometryFailureReason)
}

struct ActiveFieldGeometryStructure: Equatable, Sendable {
    let inputFrameAvailable: Bool
    let direction: ActiveFieldDirectionState
    let zeroLengthBounds: CaretBoundsState
    let precedingGlyphBounds: CaretBoundsState
    let followingGlyphBounds: CaretBoundsState
    let displayMatched: Bool
    let resolverOutcome: ActiveFieldResolverOutcome
    let paragraphStartAvailable: Bool
    var lineEdgeBounds: CaretBoundsState = .missing
}

struct ActiveFieldParagraphAttributes: Equatable, Sendable {
    var firstLineHeadIndent: CGFloat
    var headIndent: CGFloat
    var tailIndent: CGFloat
    var lineSpacing: CGFloat
    var paragraphSpacingBefore: CGFloat
    var paragraphSpacingAfter: CGFloat
    var tabStops: [CGFloat]
    var listMarker: String?
    var listLevel: Int?

    static let plain = ActiveFieldParagraphAttributes(
        firstLineHeadIndent: 0,
        headIndent: 0,
        tailIndent: 0,
        lineSpacing: 0,
        paragraphSpacingBefore: 0,
        paragraphSpacingAfter: 0,
        tabStops: [],
        listMarker: nil,
        listLevel: nil
    )

    init(
        firstLineHeadIndent: CGFloat,
        headIndent: CGFloat,
        tailIndent: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacingBefore: CGFloat,
        paragraphSpacingAfter: CGFloat,
        tabStops: [CGFloat],
        listMarker: String? = nil,
        listLevel: Int? = nil
    ) {
        self.firstLineHeadIndent = firstLineHeadIndent
        self.headIndent = headIndent
        self.tailIndent = tailIndent
        self.lineSpacing = lineSpacing
        self.paragraphSpacingBefore = paragraphSpacingBefore
        self.paragraphSpacingAfter = paragraphSpacingAfter
        self.tabStops = tabStops
        self.listMarker = listMarker
        self.listLevel = listLevel
    }

}

struct ActiveFieldParagraphMetrics: Equatable, Sendable {
    var textBeforeCaret: String
    var origin: CGPoint
    var width: CGFloat
    var lineHeight: CGFloat
    var writingDirection: CaretWritingDirection
    var textStyle: ActiveFieldTextStyle
    var prefixStyleRuns: [ActiveFieldTextStyleRun]
    var attributes: ActiveFieldParagraphAttributes
    /// True when the host exposed no font information and `textStyle` is
    /// derived from the measured line pitch. Geometry is still measured.
    var typographyIsEstimated = false
    /// Position of a completion-only first line, not a repeated paragraph indent.
    var insertionLineHeadIndent: CGFloat? = nil
}

enum ActiveFieldKind: Equatable, Sendable {
    case singleLine
    case multiline
}

struct ActiveFieldSnapshot: Equatable, Sendable {
    let applicationBundleIdentifier: String
    let surface: WritingSurface
    let elementIdentifier: String
    let focusGeneration: UInt64
    let textBefore: String
    let selectedText: String
    let textAfter: String
    let selectionRange: NSRange
    let caretBounds: CGRect?
    let inputFrame: CGRect?
    let paragraphStartBounds: CGRect?
    let geometryQuality: GeometryQuality
    let geometrySource: CaretGeometrySource?
    let captureSequence: UInt64
    let textStyle: ActiveFieldTextStyle?
    let paragraphMetrics: ActiveFieldParagraphMetrics?
    let paragraphMetricsFailureReason: ActiveFieldParagraphMetricsFailureReason?
    let fieldKind: ActiveFieldKind
    let publicationStructure: ActiveFieldPublicationStructure?
    let geometryStructure: ActiveFieldGeometryStructure?
    let masksHostPlaceholder: Bool
    let hostPlaceholderBounds: CGRect?
    var fieldContext: ActiveFieldContext

    init(
        applicationBundleIdentifier: String,
        surface: WritingSurface = .native,
        elementIdentifier: String,
        focusGeneration: UInt64,
        textBefore: String,
        selectedText: String,
        textAfter: String,
        selectionRange: NSRange,
        caretBounds: CGRect?,
        inputFrame: CGRect? = nil,
        paragraphStartBounds: CGRect? = nil,
        geometryQuality: GeometryQuality,
        geometrySource: CaretGeometrySource? = nil,
        captureSequence: UInt64 = 0,
        textStyle: ActiveFieldTextStyle? = nil,
        paragraphMetrics: ActiveFieldParagraphMetrics? = nil,
        paragraphMetricsFailureReason: ActiveFieldParagraphMetricsFailureReason? = nil,
        fieldKind: ActiveFieldKind = .multiline,
        publicationStructure: ActiveFieldPublicationStructure? = nil,
        geometryStructure: ActiveFieldGeometryStructure? = nil,
        masksHostPlaceholder: Bool = false,
        hostPlaceholderBounds: CGRect? = nil,
        fieldContext: ActiveFieldContext? = nil
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.surface = surface
        self.elementIdentifier = elementIdentifier
        self.focusGeneration = focusGeneration
        self.textBefore = textBefore
        self.selectedText = selectedText
        self.textAfter = textAfter
        self.selectionRange = selectionRange
        self.caretBounds = caretBounds
        self.inputFrame = inputFrame
        self.paragraphStartBounds = paragraphStartBounds
        self.geometryQuality = geometryQuality
        self.geometrySource = geometrySource
        self.captureSequence = captureSequence
        self.textStyle = textStyle
        self.paragraphMetrics = paragraphMetrics
        self.paragraphMetricsFailureReason = paragraphMetricsFailureReason
        self.fieldKind = fieldKind
        self.publicationStructure = publicationStructure
        self.geometryStructure = geometryStructure
        self.masksHostPlaceholder = masksHostPlaceholder
        self.hostPlaceholderBounds = hostPlaceholderBounds
        self.fieldContext = fieldContext ?? ActiveFieldContext(
            shape: fieldKind == .singleLine ? .singleLine : .multiline
        )
    }
}

enum ActiveFieldCaptureResult: Equatable, Sendable {
    case captured(ActiveFieldSnapshot)
    case skipped(ActiveFieldSkipReason)
}

/// Captures one immutable snapshot of the focused editable field.
///
/// Eligibility is decided from accessibility capabilities, not from an
/// application allowlist: native text fields/text areas and editable web
/// elements that answer text-marker queries can be captured. Secure fields,
/// the product's own process, and search/combo widgets are excluded before
/// their text is read.
final class ActiveFieldCapture<Reader: AccessibilityReading>: @unchecked Sendable {
    private static var nativeMultilineRole: String { kAXTextAreaRole as String }
    private static var singleLineRole: String { kAXTextFieldRole as String }
    private static var webAreaRole: String { "AXWebArea" }
    private static var secureSubrole: String { kAXSecureTextFieldSubrole as String }
    private static var searchSubrole: String { "AXSearchField" }
    private static var comboBoxRole: String { kAXComboBoxRole as String }

    private let reader: Reader
    private let excludedProcessIdentifier: Int32?
    private let lock = NSLock()
    private var configuration = CaptureConfiguration.disabled
    private var focusedElementIdentifier: String?
    private var webCapabilityElementIdentifier: String?
    private var focusedElementIsWebContent: Bool?
    private var focusGeneration: UInt64 = 0
    private var captureSequence: UInt64 = 0

    init(reader: Reader, excludedProcessIdentifier: Int32? = nil) {
        self.reader = reader
        self.excludedProcessIdentifier = excludedProcessIdentifier
    }

    func updateConfiguration(_ configuration: CaptureConfiguration) {
        lock.withLock { self.configuration = configuration }
    }

    func capture() -> ActiveFieldCaptureResult {
        lock.lock()
        defer { lock.unlock() }
        captureSequence &+= 1
        guard configuration.isEnabled else {
            return .skipped(.unsupportedApplication)
        }

        if let excludedProcessIdentifier,
           reader.frontmostProcessIdentifier() == excludedProcessIdentifier {
            return .skipped(.unsupportedApplication)
        }

        if let frontmost = reader.frontmostApplicationBundleIdentifier(), !configuration.allows(frontmost) {
            return .skipped(.unsupportedApplication)
        }

        // A transient focus read failure must not look like a focus change;
        // the previous field identity is kept until a different element is
        // actually observed.
        var focusedElement = reader.focusedElement()
        if focusedElement == nil {
            // Some Chromium/Electron hosts expose their AXWebArea before they
            // publish AXFocusedUIElement. Touching that tree activates the
            // lazy accessibility bridge; retry once in the same capture.
            // Never probe an unknown application's tree while user exclusions exist.
            guard configuration.excludedApplications.isEmpty || reader.frontmostApplicationBundleIdentifier().map(configuration.allows) == true else {
                return .skipped(.unsupportedApplication)
            }
            reader.prepareFrontmostWebContent()
            focusedElement = reader.focusedElement()
        }
        guard let element = focusedElement else {
            return .skipped(.accessibilityUnavailable)
        }

        guard reader.subrole(for: element) != Self.secureSubrole else {
            return .skipped(.secureField)
        }
        guard let bundleIdentifier = reader.applicationBundleIdentifier(for: element) else {
            return .skipped(.unsupportedApplication)
        }
        if let excludedProcessIdentifier,
           reader.processIdentifier(for: element) == excludedProcessIdentifier {
            return .skipped(.unsupportedApplication)
        }
        guard configuration.allows(bundleIdentifier) else { return .skipped(.unsupportedApplication) }
        // Our settings may contain private library/account editors. Only the
        // explicit practice field is a writing surface, even during practice.
        if bundleIdentifier == "com.autocompletion.settings", reader.userInterfaceIdentifier(for: element) != "autocompletion-exercise" {
            return .skipped(.unsupportedApplication)
        }
        guard let role = reader.role(for: element) else {
            return .skipped(.unsupportedRole)
        }

        let isWebContent: Bool
        if webCapabilityElementIdentifier == element.identifier,
           focusedElementIsWebContent == true {
            isWebContent = true
        } else {
            isWebContent = reader.isWebContentElement(element)
            webCapabilityElementIdentifier = element.identifier
            focusedElementIsWebContent = isWebContent
        }
        if isWebContent {
            return captureWeb(element: element, role: role, bundleIdentifier: bundleIdentifier)
        }
        return captureNative(element: element, role: role, bundleIdentifier: bundleIdentifier)
    }

    // MARK: - Native text controls

    private func captureNative(
        element: AccessibilityElement,
        role: String,
        bundleIdentifier: String
    ) -> ActiveFieldCaptureResult {
        guard role == Self.nativeMultilineRole || role == Self.singleLineRole,
              role != Self.comboBoxRole,
              reader.subrole(for: element) != Self.searchSubrole
        else {
            return .skipped(.unsupportedRole)
        }
        let fieldKind: ActiveFieldKind = role == Self.singleLineRole
            ? .singleLine
            : .multiline
        updateFocusIdentity(element.identifier)

        guard let text = reader.stringValue(for: element) else {
            return .skipped(.valueMissing)
        }
        guard let selection = reader.selectedTextRange(for: element) else {
            return .skipped(.rangeMissing)
        }
        guard let swiftRange = Range(selection, in: text) else {
            return .skipped(.rangeOutOfBounds)
        }

        let textBefore = Self.suffix(text[..<swiftRange.lowerBound], maximumUTF16Units: 8_000)
        let selectedText = Self.prefix(text[swiftRange], maximumUTF16Units: 2_000)
        let textAfter = Self.prefix(text[swiftRange.upperBound...], maximumUTF16Units: 2_000)
        let publicationStructure = Self.publicationStructure(
            selectionLocation: selection.location,
            selectionLength: selection.length,
            textBefore: text[..<swiftRange.lowerBound],
            textAfterIsEmpty: swiftRange.upperBound == text.endIndex,
            valueTerminal: Self.terminalClass(in: text[...])
        )
        let displays = reader.displayGeometries()
        let direction = Self.directionState(
            Self.caretWritingDirection(at: swiftRange.upperBound, in: text)
        )

        var candidates: [CaretGeometryCandidate] = []
        var zeroLengthBounds: CGRect?
        var precedingGlyphBounds: CGRect?
        var followingGlyphBounds: CGRect?
        if !direction.isAmbiguous, selection.length == 0 {
            let caretRange = NSRange(location: NSMaxRange(selection), length: 0)
            zeroLengthBounds = reader.bounds(for: caretRange, in: element)
            if let zeroLengthBounds {
                candidates.append(.init(rect: zeroLengthBounds, source: .zeroLengthRange))
            }
            if direction.resolved != nil {
                if let range = Self.previousCharacterRange(before: swiftRange.upperBound, in: text) {
                    precedingGlyphBounds = reader.bounds(for: range, in: element)
                    if let precedingGlyphBounds, precedingGlyphBounds.height > 0 {
                        candidates.append(
                            .init(rect: precedingGlyphBounds, source: .precedingGrapheme)
                        )
                    }
                }
                if let range = Self.followingCharacterRange(at: swiftRange.upperBound, in: text) {
                    followingGlyphBounds = reader.bounds(for: range, in: element)
                    if let followingGlyphBounds, followingGlyphBounds.height > 0 {
                        candidates.append(
                            .init(rect: followingGlyphBounds, source: .followingGrapheme)
                        )
                    }
                }
            }
        }

        let inputFrameAX = reader.frame(for: element)
        let geometry = Self.resolveGeometry(
            candidates: candidates,
            inputFrameAX: inputFrameAX,
            direction: direction,
            displays: displays,
            selection: selection,
            textLength: text.utf16.count
        )
        let styleRange: NSRange?
        if selection.location > 0 {
            styleRange = NSRange(location: selection.location - 1, length: 1)
        } else if !text.isEmpty {
            styleRange = NSRange(location: 0, length: 1)
        } else {
            styleRange = nil
        }
        let textStyle = styleRange.flatMap { reader.textStyle(for: $0, in: element) }
        let inputFrameAnchor = zeroLengthBounds ?? precedingGlyphBounds ?? followingGlyphBounds
        let inputFrame = Self.appKitFrame(
            inputFrameAX,
            anchoredBy: inputFrameAnchor,
            displays: displays
        )
        let paragraphRange = Self.currentParagraphRange(before: swiftRange.upperBound, in: text)
        let paragraphStartBounds = Self.firstCharacterRange(in: paragraphRange, text: text)
            .flatMap { range in
                reader.bounds(for: range, in: element).flatMap {
                    DisplayCoordinateConverter.appKitRect(fromAccessibilityRect: $0, displays: displays)
                }
            }
        let metrics = Self.nativeParagraphMetrics(
            paragraphRange: paragraphRange,
            text: text,
            element: element,
            reader: reader,
            direction: direction.resolved,
            paragraphStartBounds: paragraphStartBounds,
            inputFrame: inputFrame,
            caretBounds: geometry.caretBounds,
            geometryQuality: geometry.quality,
            textStyle: textStyle
        )
        let geometryStructure = ActiveFieldGeometryStructure(
            inputFrameAvailable: inputFrameAX != nil,
            direction: direction.state,
            zeroLengthBounds: CaretGeometryResolver.boundsState(zeroLengthBounds, source: .zeroLengthRange),
            precedingGlyphBounds: CaretGeometryResolver.boundsState(precedingGlyphBounds, source: .precedingGrapheme),
            followingGlyphBounds: CaretGeometryResolver.boundsState(followingGlyphBounds, source: .followingGrapheme),
            displayMatched: geometry.displayMatched,
            resolverOutcome: geometry.resolverOutcome,
            paragraphStartAvailable: paragraphStartBounds != nil
        )

        return .captured(
            ActiveFieldSnapshot(
                applicationBundleIdentifier: bundleIdentifier,
                surface: .native,
                elementIdentifier: element.identifier,
                focusGeneration: focusGeneration,
                textBefore: textBefore,
                selectedText: selectedText,
                textAfter: textAfter,
                selectionRange: selection,
                caretBounds: geometry.caretBounds,
                inputFrame: inputFrame,
                paragraphStartBounds: paragraphStartBounds,
                geometryQuality: geometry.quality,
                geometrySource: geometry.source,
                captureSequence: captureSequence,
                textStyle: textStyle,
                paragraphMetrics: metrics.metrics,
                paragraphMetricsFailureReason: metrics.failureReason,
                fieldKind: fieldKind,
                publicationStructure: publicationStructure,
                geometryStructure: geometryStructure,
                fieldContext: ActiveFieldContext(shape: fieldKind == .singleLine ? .singleLine : .multiline, sources: reader.sourceContexts(for: element))
            )
        )
    }

    // MARK: - Web content

    private func captureWeb(
        element: AccessibilityElement,
        role: String,
        bundleIdentifier: String
    ) -> ActiveFieldCaptureResult {
        guard role != Self.webAreaRole,
              role != Self.comboBoxRole,
              reader.subrole(for: element) != Self.searchSubrole
        else { return .skipped(.unsupportedRole) }
        let preparedElement = reader.prepareWebContent(for: element)
        guard let context = reader.webTextContext(for: preparedElement)
        else {
            return .skipped(.markerReadFailed)
        }
        guard context.subrole != Self.secureSubrole else {
            return .skipped(.secureField)
        }
        guard context.role != Self.comboBoxRole, context.subrole != Self.searchSubrole else {
            return .skipped(.unsupportedRole)
        }
        let fieldKind: ActiveFieldKind = context.role == Self.singleLineRole
            ? .singleLine
            : .multiline
        let fieldContext = ActiveFieldContext(
            shape: fieldKind == .singleLine ? .singleLine : .multiline,
            label: context.label,
            placeholder: context.placeholder,
            relatedFields: context.relatedFields,
            sources: reader.sourceContexts(for: preparedElement)
        )
        updateFocusIdentity(context.editableIdentifier)

        let selection = NSRange(
            location: context.selectionLocation,
            length: context.selectionLength
        )
        guard selection.location >= 0, selection.length >= 0 else {
            return .skipped(.rangeOutOfBounds)
        }
        let text = context.textBefore + context.selectedText + context.textAfter
        let caretIndex = text.index(
            text.startIndex,
            offsetBy: (context.textBefore + context.selectedText).count
        )
        let publicationStructure = Self.publicationStructure(
            selectionLocation: selection.location,
            selectionLength: selection.length,
            textBefore: context.textBefore[...],
            textAfterIsEmpty: context.textAfter.isEmpty,
            valueTerminal: Self.terminalClass(in: text[...])
        )
        let displays = reader.displayGeometries()
        let direction = Self.directionState(
            Self.caretWritingDirection(at: caretIndex, in: text)
        )

        var candidates: [CaretGeometryCandidate] = []
        var zeroLengthBounds: CGRect?
        var precedingGlyphBounds: CGRect?
        var followingGlyphBounds: CGRect?
        var lineEdgeBounds: CGRect?
        if !direction.isAmbiguous, selection.length == 0 {
            for candidate in context.caretCandidates {
                switch candidate.source {
                case .zeroLengthRange:
                    zeroLengthBounds = candidate.rect
                    candidates.append(candidate)
                case .precedingGrapheme where direction.resolved != nil:
                    precedingGlyphBounds = candidate.rect
                    if candidate.rect.height > 0 { candidates.append(candidate) }
                case .followingGrapheme where direction.resolved != nil:
                    followingGlyphBounds = candidate.rect
                    if candidate.rect.height > 0 { candidates.append(candidate) }
                case .lineEnd, .lineStart:
                    // Candidate priority belongs after geometry validation.
                    // A reported glyph can be outside the focused editor.
                    lineEdgeBounds = candidate.rect
                    candidates.append(candidate)
                default:
                    continue
                }
            }
        }
        let geometry = Self.resolveGeometry(
            candidates: candidates,
            inputFrameAX: context.frame,
            direction: direction,
            displays: displays,
            selection: selection,
            textLength: selection.location + selection.length + context.textAfter.utf16.count
        )
        let textStyle = context.caretTextStyle ?? context.paragraphStyleRuns?.last?.style
        let inputFrameAnchor = zeroLengthBounds ?? precedingGlyphBounds
            ?? followingGlyphBounds ?? lineEdgeBounds
        let inputFrame = Self.appKitFrame(
            context.frame,
            anchoredBy: inputFrameAnchor,
            displays: displays
        )
        let paragraphBounds = (context.paragraphBounds ?? context.lineBounds).flatMap {
            DisplayCoordinateConverter.appKitRect(fromAccessibilityRect: $0, displays: displays)
        }
        let lineBounds = context.lineBounds.flatMap {
            DisplayCoordinateConverter.appKitRect(fromAccessibilityRect: $0, displays: displays)
        }
        let metrics = Self.webParagraphMetrics(
            context: context,
            direction: direction,
            paragraphBounds: paragraphBounds,
            lineBounds: lineBounds,
            inputFrame: inputFrame,
            caretBounds: geometry.caretBounds
        )
        let geometryStructure = ActiveFieldGeometryStructure(
            inputFrameAvailable: context.frame != nil,
            direction: direction.state,
            zeroLengthBounds: CaretGeometryResolver.boundsState(zeroLengthBounds, source: .zeroLengthRange),
            precedingGlyphBounds: CaretGeometryResolver.boundsState(precedingGlyphBounds, source: .precedingGrapheme),
            followingGlyphBounds: CaretGeometryResolver.boundsState(followingGlyphBounds, source: .followingGrapheme),
            displayMatched: geometry.displayMatched,
            resolverOutcome: geometry.resolverOutcome,
            paragraphStartAvailable: paragraphBounds != nil,
            lineEdgeBounds: CaretGeometryResolver.boundsState(lineEdgeBounds, source: .lineEnd)
        )

        return .captured(
            ActiveFieldSnapshot(
                applicationBundleIdentifier: bundleIdentifier,
                surface: .web,
                elementIdentifier: context.editableIdentifier,
                focusGeneration: focusGeneration,
                textBefore: context.textBefore,
                selectedText: context.selectedText,
                textAfter: context.textAfter,
                selectionRange: selection,
                caretBounds: geometry.caretBounds,
                inputFrame: inputFrame,
                paragraphStartBounds: paragraphBounds,
                geometryQuality: geometry.quality,
                geometrySource: geometry.source,
                captureSequence: captureSequence,
                textStyle: textStyle,
                paragraphMetrics: metrics.metrics,
                paragraphMetricsFailureReason: metrics.failureReason,
                fieldKind: fieldKind,
                publicationStructure: publicationStructure,
                geometryStructure: geometryStructure,
                masksHostPlaceholder: context.textBefore.isEmpty
                    && context.selectedText.isEmpty
                    && context.textAfter.isEmpty,
                hostPlaceholderBounds: context.hostPlaceholderBounds.flatMap {
                    DisplayCoordinateConverter.appKitRect(
                        fromAccessibilityRect: $0,
                        displays: displays
                    )
                },
                fieldContext: fieldContext
            )
        )
    }

    // MARK: - Shared helpers

    private func updateFocusIdentity(_ identity: String) {
        if focusedElementIdentifier != identity {
            focusedElementIdentifier = identity
            focusGeneration &+= 1
        }
    }

    private struct DirectionState {
        let resolved: CaretWritingDirection?
        let isAmbiguous: Bool
        let state: ActiveFieldDirectionState
    }

    private static func directionState(
        _ resolution: CaretWritingDirectionResolution
    ) -> DirectionState {
        switch resolution {
        case let .resolved(direction):
            return DirectionState(
                resolved: direction,
                isAmbiguous: false,
                state: direction == .leftToRight ? .leftToRight : .rightToLeft
            )
        case .neutral:
            return DirectionState(resolved: nil, isAmbiguous: false, state: .neutral)
        case .ambiguous:
            return DirectionState(resolved: nil, isAmbiguous: true, state: .ambiguous)
        }
    }

    private struct ResolvedGeometry {
        let caretBounds: CGRect?
        let quality: GeometryQuality
        let source: CaretGeometrySource?
        let displayMatched: Bool
        let resolverOutcome: ActiveFieldResolverOutcome
    }

    private static func resolveGeometry(
        candidates: [CaretGeometryCandidate],
        inputFrameAX: CGRect?,
        direction: DirectionState,
        displays: [DisplayGeometry],
        selection: NSRange,
        textLength: Int
    ) -> ResolvedGeometry {
        // A detached marker must not calibrate the valid line that survives
        // resolution. In particular, Chromium can report an off-editor glyph
        // with a different height alongside a correctly measured text node.
        let containedCandidates = candidates.filter { candidate in
            CaretGeometryResolver.boundsState(candidate.rect, source: candidate.source) == .available
                && inputFrameAX?.insetBy(dx: -4, dy: -4).contains(candidate.rect) == true
                && DisplayCoordinateConverter.appKitRect(
                    fromAccessibilityRect: candidate.rect, displays: displays
                ) != nil
        }
        let measuredLineHeight = containedCandidates.first(where: {
            $0.source != .zeroLengthRange
        })?.rect.height ?? containedCandidates.first?.rect.height
        let selectionContext: CaretSelectionContext
        if selection.length != 0 {
            selectionContext = .other
        } else if selection.location == textLength {
            selectionContext = .collapsedAtTextEnd
        } else if selection.location > 0 {
            selectionContext = .collapsedInText
        } else {
            selectionContext = .other
        }
        let evaluation = inputFrameAX.map { inputFrame in
            CaretGeometryResolver.evaluate(.init(
                candidates: candidates,
                inputFrame: inputFrame,
                measuredLineHeight: measuredLineHeight,
                writingDirection: direction.resolved ?? .leftToRight,
                displays: displays,
                selectionContext: selectionContext
            ))
        }
        let resolved = evaluation?.geometry
        let quality: GeometryQuality = switch resolved?.quality {
        case .exact: .exact
        case .derived: .derived
        case nil: .unavailable
        }
        let outcome: ActiveFieldResolverOutcome = switch evaluation?.outcome {
        case .resolved: .resolved
        case let .failed(reason): .failed(reason)
        case nil: .notRun
        }
        return ResolvedGeometry(
            caretBounds: resolved?.rect,
            quality: quality,
            source: resolved?.source,
            displayMatched: evaluation?.displayMatched ?? false,
            resolverOutcome: outcome
        )
    }

    private static func appKitFrame(
        _ frame: CGRect?,
        anchoredBy anchor: CGRect?,
        displays: [DisplayGeometry]
    ) -> CGRect? {
        frame.flatMap { frame in
            if let anchor {
                return DisplayCoordinateConverter.appKitRect(
                    fromAccessibilityRect: frame,
                    anchoredBy: anchor,
                    displays: displays
                )
            }
            return DisplayCoordinateConverter.appKitRect(
                fromAccessibilityRect: frame,
                displays: displays
            )
        }
    }

    private static func publicationStructure(
        selectionLocation: Int,
        selectionLength: Int,
        textBefore: Substring,
        textAfterIsEmpty: Bool,
        valueTerminal: ActiveFieldTerminalClass
    ) -> ActiveFieldPublicationStructure {
        let position: ActiveFieldSelectionPosition
        if selectionLocation == 0 {
            position = .start
        } else if textAfterIsEmpty {
            position = .end
        } else {
            position = .middle
        }
        return ActiveFieldPublicationStructure(
            selectionPosition: position,
            selectionCollapsed: selectionLength == 0,
            textBeforeTerminal: terminalClass(in: textBefore),
            textAfterIsEmpty: textAfterIsEmpty,
            valueTerminal: valueTerminal
        )
    }

    private static func terminalClass<S: StringProtocol>(
        in text: S
    ) -> ActiveFieldTerminalClass {
        guard let terminal = text.last else { return .empty }
        if terminal.isNewline { return .newline }
        if terminal.isWhitespace { return .space }
        if terminal.isLetter { return .letter }
        return .other
    }

    private static func previousCharacterRange(
        before index: String.Index,
        in text: String
    ) -> NSRange? {
        guard index > text.startIndex else { return nil }
        return NSRange(text.index(before: index)..<index, in: text)
    }

    private static func followingCharacterRange(
        at index: String.Index,
        in text: String
    ) -> NSRange? {
        guard index < text.endIndex else { return nil }
        return NSRange(index..<text.index(after: index), in: text)
    }

    private static func currentParagraphRange(
        before index: String.Index,
        in text: String
    ) -> Range<String.Index> {
        let paragraphPrefix = text[..<index]
        let start = paragraphPrefix.lastIndex(where: { $0.isNewline }).map {
            text.index(after: $0)
        } ?? text.startIndex
        return start..<index
    }

    private static func firstCharacterRange(
        in range: Range<String.Index>,
        text: String
    ) -> NSRange? {
        guard range.lowerBound < range.upperBound else { return nil }
        return NSRange(
            range.lowerBound..<text.index(after: range.lowerBound),
            in: text
        )
    }

    // MARK: - Paragraph metrics

    private struct ParagraphMetricsResolution {
        let metrics: ActiveFieldParagraphMetrics?
        let failureReason: ActiveFieldParagraphMetricsFailureReason?

        static func available(_ metrics: ActiveFieldParagraphMetrics) -> ParagraphMetricsResolution {
            ParagraphMetricsResolution(metrics: metrics, failureReason: nil)
        }

        static func unavailable(
            _ reason: ActiveFieldParagraphMetricsFailureReason
        ) -> ParagraphMetricsResolution {
            ParagraphMetricsResolution(metrics: nil, failureReason: reason)
        }
    }

    private static func nativeParagraphMetrics<ParagraphReader: AccessibilityReading>(
        paragraphRange: Range<String.Index>,
        text: String,
        element: AccessibilityElement,
        reader: ParagraphReader,
        direction: CaretWritingDirection?,
        paragraphStartBounds: CGRect?,
        inputFrame: CGRect?,
        caretBounds: CGRect?,
        geometryQuality: GeometryQuality,
        textStyle: ActiveFieldTextStyle?
    ) -> ParagraphMetricsResolution {
        let range = NSRange(paragraphRange, in: text)
        guard range.length > 0 else { return .unavailable(.empty) }
        guard range.length <= 2_000 else { return .unavailable(.tooLong) }
        guard let direction else { return .unavailable(.directionUnavailable) }
        guard let paragraphStartBounds else {
            return .unavailable(.paragraphStartUnavailable)
        }
        guard let inputFrame else { return .unavailable(.inputFrameUnavailable) }
        guard let caretBounds else { return .unavailable(.caretUnavailable) }
        guard paragraphStartBounds.height.isFinite,
              paragraphStartBounds.height > 0,
              caretBounds.height.isFinite,
              caretBounds.height > 0
        else { return .unavailable(.lineHeightInvalid) }
        guard abs(paragraphStartBounds.height - caretBounds.height) <= 1 else {
            return .unavailable(.lineHeightMismatch)
        }

        // Once the host paragraph has wrapped, small differences between
        // the host's private text shaping and TextKit accumulate across the whole
        // prefix. The caret and both paragraph edges are already measured by
        // Accessibility, so make those the canonical inputs: lay out only the
        // completion with its first line indented to the current caret. This
        // preserves native wrapping without reconstructing an unverifiable
        // width for every preceding glyph.
        if abs(paragraphStartBounds.minY - caretBounds.minY) > 1 {
            return lineFillMetrics(
                direction: direction,
                leftEdge: direction == .leftToRight
                    ? paragraphStartBounds.minX
                    : inputFrame.minX,
                rightEdge: direction == .leftToRight
                    ? inputFrame.maxX
                    : paragraphStartBounds.maxX,
                lineTop: caretBounds.maxY,
                lineHeight: caretBounds.height,
                caretBounds: caretBounds,
                inputFrame: inputFrame,
                style: textStyle
            )
        }

        let exact = exactNativeMetrics(
            range: range,
            text: text,
            paragraphRange: paragraphRange,
            element: element,
            reader: reader,
            direction: direction,
            paragraphStartBounds: paragraphStartBounds,
            inputFrame: inputFrame
        )
        if let metrics = exact.metrics {
            // A derived caret is reconstructed from an adjacent measured
            // glyph. Re-laying the whole host prefix can wrap that insertion
            // boundary onto a different line, especially for bidi text. Keep
            // the Accessibility caret and paragraph edges canonical instead.
            if geometryQuality == .derived {
                return lineFillMetrics(
                    direction: direction,
                    leftEdge: direction == .leftToRight
                        ? paragraphStartBounds.minX
                        : inputFrame.minX,
                    rightEdge: direction == .leftToRight
                        ? inputFrame.maxX
                        : paragraphStartBounds.maxX,
                    lineTop: caretBounds.maxY,
                    lineHeight: caretBounds.height,
                    caretBounds: caretBounds,
                    inputFrame: inputFrame,
                    style: metrics.textStyle
                )
            }
            return .available(metrics)
        }
        switch exact.failureReason {
        case .styleRunsUnavailable, .paragraphAttributesUnavailable, .styleCoverageInvalid:
            // The host exposes glyph geometry but no complete typography for
            // the prefix. Lay out the completion alone from the measured
            // caret and paragraph edges.
            return lineFillMetrics(
                direction: direction,
                leftEdge: direction == .leftToRight ? paragraphStartBounds.minX : inputFrame.minX,
                rightEdge: direction == .leftToRight ? inputFrame.maxX : paragraphStartBounds.maxX,
                lineTop: caretBounds.maxY,
                lineHeight: caretBounds.height,
                caretBounds: caretBounds,
                inputFrame: inputFrame,
                style: textStyle
            )
        default:
            return exact
        }
    }

    private static func exactNativeMetrics<ParagraphReader: AccessibilityReading>(
        range: NSRange,
        text: String,
        paragraphRange: Range<String.Index>,
        element: AccessibilityElement,
        reader: ParagraphReader,
        direction: CaretWritingDirection,
        paragraphStartBounds: CGRect,
        inputFrame: CGRect
    ) -> ParagraphMetricsResolution {
        guard let styleRuns = reader.textStyleRuns(for: range, in: element) else {
            return .unavailable(.styleRunsUnavailable)
        }
        guard Self.coversParagraph(styleRuns, length: range.length),
              let style = styleRuns.last?.style
        else { return .unavailable(.styleCoverageInvalid) }
        guard let attributes = reader.paragraphAttributes(for: range, in: element) else {
            return .unavailable(.paragraphAttributesUnavailable)
        }
        guard attributes.listMarker == nil, attributes.listLevel == nil else {
            return .unavailable(.listUnsupported)
        }
        let originX: CGFloat
        let width: CGFloat
        switch direction {
        case .leftToRight:
            originX = paragraphStartBounds.minX - attributes.firstLineHeadIndent
            width = inputFrame.maxX - originX
        case .rightToLeft:
            originX = inputFrame.minX
            width = paragraphStartBounds.maxX - originX
        }
        guard originX.isFinite,
              width.isFinite,
              width > 0,
              paragraphStartBounds.minX >= inputFrame.minX,
              paragraphStartBounds.maxX <= inputFrame.maxX,
              paragraphStartBounds.minY >= inputFrame.minY,
              paragraphStartBounds.maxY <= inputFrame.maxY,
              originX >= inputFrame.minX,
              originX < inputFrame.maxX
        else { return .unavailable(.boundsInvalid) }
        return .available(ActiveFieldParagraphMetrics(
            textBeforeCaret: String(text[paragraphRange]),
            origin: CGPoint(x: originX, y: paragraphStartBounds.maxY),
            width: width,
            lineHeight: paragraphStartBounds.height,
            writingDirection: direction,
            textStyle: style,
            prefixStyleRuns: styleRuns,
            attributes: attributes
        ))
    }

    private static func webParagraphMetrics(
        context: WebTextContext,
        direction: DirectionState,
        paragraphBounds: CGRect?,
        lineBounds: CGRect?,
        inputFrame: CGRect?,
        caretBounds: CGRect?
    ) -> ParagraphMetricsResolution {
        guard !direction.isAmbiguous else { return .unavailable(.directionUnavailable) }
        guard let inputFrame else { return .unavailable(.inputFrameUnavailable) }
        guard let caretBounds else { return .unavailable(.caretUnavailable) }
        guard caretBounds.height.isFinite, caretBounds.height > 0 else {
            return .unavailable(.lineHeightInvalid)
        }
        guard context.paragraphTextBefore.utf16.count <= 2_000,
              context.paragraphTextBeforeIsComplete
        else { return .unavailable(.tooLong) }
        let resolvedDirection = direction.resolved ?? .leftToRight

        // AX paragraph bounds are the tight glyph union, not the paragraph's
        // CSS content box. A right-to-left run can therefore sit against
        // either physical edge (for example inside a left-aligned textarea).
        // Infer the shared content inset from the measured edge nearest the
        // field boundary; writing direction only controls where the caret
        // indent is measured from.
        // Validate measurements before choosing their priority. Some hosts
        // publish detached paragraph ranges while the current text line is
        // correctly measured. An invalid paragraph must not discard that line.
        let visibleFrame = inputFrame.insetBy(dx: -1, dy: -1)
        guard let measuredBounds = [paragraphBounds, lineBounds, caretBounds]
            .compactMap({ $0 })
            .first(where: { bounds in
                bounds.minX.isFinite && bounds.minY.isFinite
                    && bounds.width.isFinite && bounds.height.isFinite
                    && bounds.width >= 0 && bounds.height > 0
                    && visibleFrame.contains(bounds)
            })
        else { return .unavailable(.boundsInvalid) }
        let horizontalInset = max(
            0,
            min(
                measuredBounds.minX - inputFrame.minX,
                inputFrame.maxX - measuredBounds.maxX
            )
        )
        return lineFillMetrics(
            direction: resolvedDirection,
            leftEdge: inputFrame.minX + horizontalInset,
            rightEdge: inputFrame.maxX - horizontalInset,
            lineTop: caretBounds.maxY,
            lineHeight: caretBounds.height,
            caretBounds: caretBounds,
            inputFrame: inputFrame,
            style: context.caretTextStyle ?? context.paragraphStyleRuns?.last?.style
        )
    }

    /// Measured line geometry with the completion laid out on its own: the
    /// first ghost line starts at the caret through a first-line indent and
    /// continuation lines fill the paragraph width at the host's line pitch.
    private static func lineFillMetrics(
        direction: CaretWritingDirection,
        leftEdge: CGFloat,
        rightEdge: CGFloat,
        lineTop: CGFloat,
        lineHeight: CGFloat,
        caretBounds: CGRect,
        inputFrame: CGRect,
        style: ActiveFieldTextStyle?
    ) -> ParagraphMetricsResolution {
        guard let style else { return .unavailable(.styleRunsUnavailable) }
        let originX: CGFloat
        let width: CGFloat
        let indent: CGFloat
        switch direction {
        case .leftToRight:
            originX = leftEdge
            width = rightEdge - originX
            indent = caretBounds.maxX - originX
        case .rightToLeft:
            originX = leftEdge
            width = rightEdge - originX
            indent = rightEdge - caretBounds.minX
        }
        guard originX.isFinite, width.isFinite, indent.isFinite,
              width > 0, indent >= 0, indent <= width,
              originX >= inputFrame.minX - 1, originX + width <= inputFrame.maxX + 1
        else { return .unavailable(.boundsInvalid) }
        return .available(ActiveFieldParagraphMetrics(
            textBeforeCaret: "",
            origin: CGPoint(x: originX, y: lineTop),
            width: width,
            lineHeight: lineHeight,
            writingDirection: direction,
            textStyle: style,
            prefixStyleRuns: [],
            attributes: .plain,
            typographyIsEstimated: style.isEstimated,
            insertionLineHeadIndent: indent
        ))
    }

    private static func coversParagraph(
        _ runs: [ActiveFieldTextStyleRun],
        length: Int
    ) -> Bool {
        guard length > 0, !runs.isEmpty else { return false }
        var nextLocation = 0
        for run in runs {
            guard run.range.location == nextLocation,
                  run.range.length > 0,
                  run.style.fontSize.isFinite,
                  run.style.fontSize > 0,
                  !run.style.fontName.isEmpty
            else { return false }
            nextLocation = NSMaxRange(run.range)
        }
        return nextLocation == length
    }

    // MARK: - Writing direction

    private static func caretWritingDirection(
        at index: String.Index,
        in text: String
    ) -> CaretWritingDirectionResolution {
        let immediatelyBefore: CaretWritingDirection?
        if let character = characterBefore(index, in: text) {
            immediatelyBefore = strongDirection(character)
        } else {
            immediatelyBefore = nil
        }

        let immediatelyAfter: CaretWritingDirection?
        if let character = characterAfter(index, in: text) {
            immediatelyAfter = strongDirection(character)
        } else {
            immediatelyAfter = nil
        }

        switch (immediatelyBefore, immediatelyAfter) {
        case let (before?, after?) where before != after:
            return .ambiguous
        case let (before?, _):
            return .resolved(before)
        case let (_, after?):
            return .resolved(after)
        case (nil, nil):
            break
        }

        let nearestBefore = nearestStrongDirection(before: index, in: text)
        let nearestAfter = nearestStrongDirection(after: index, in: text)
        switch (nearestBefore, nearestAfter) {
        case let (before?, after?) where before != after:
            return .ambiguous
        case let (before?, _):
            return .resolved(before)
        case let (_, after?):
            return .resolved(after)
        case (nil, nil):
            return .neutral
        }
    }

    private static func nearestStrongDirection(
        before index: String.Index,
        in text: String
    ) -> CaretWritingDirection? {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            let character = text[previous]
            guard character != "\n" else { return nil }
            if let direction = strongDirection(character) {
                return direction
            }
            cursor = previous
        }
        return nil
    }

    private static func nearestStrongDirection(
        after index: String.Index,
        in text: String
    ) -> CaretWritingDirection? {
        var cursor = index
        while cursor < text.endIndex {
            let character = text[cursor]
            guard character != "\n" else { return nil }
            if let direction = strongDirection(character) {
                return direction
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func characterBefore(
        _ index: String.Index,
        in text: String
    ) -> Character? {
        guard index > text.startIndex else { return nil }
        let character = text[text.index(before: index)]
        return character == "\n" ? nil : character
    }

    private static func characterAfter(
        _ index: String.Index,
        in text: String
    ) -> Character? {
        guard index < text.endIndex else { return nil }
        let character = text[index]
        return character == "\n" ? nil : character
    }

    private static func strongDirection(
        _ character: Character
    ) -> CaretWritingDirection? {
        for scalar in character.unicodeScalars {
            let value = Int(scalar.value)
            if (0x0590...0x08FF).contains(value)
                || (0xFB1D...0xFEFC).contains(value) {
                return .rightToLeft
            }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter:
                return .leftToRight
            default:
                continue
            }
        }
        return nil
    }

    static func prefix(_ text: Substring, maximumUTF16Units: Int) -> String {
        BoundedText.prefix(text, maximumUTF16Units: maximumUTF16Units)
    }

    static func suffix(_ text: Substring, maximumUTF16Units: Int) -> String {
        BoundedText.suffix(text, maximumUTF16Units: maximumUTF16Units)
    }
}

/// Grapheme-safe bounds on captured text. Truncation never splits a
/// character and counts UTF-16 units, which is what the host protocol and
/// Accessibility ranges use.
enum BoundedText {
    static func prefix(
        _ text: Substring,
        maximumUTF16Units: Int
    ) -> String {
        var result = ""
        var usedUTF16Units = 0
        for character in text {
            let characterUTF16Units = String(character).utf16.count
            guard usedUTF16Units + characterUTF16Units <= maximumUTF16Units else {
                break
            }
            result.append(character)
            usedUTF16Units += characterUTF16Units
        }
        return result
    }

    static func suffix(
        _ text: Substring,
        maximumUTF16Units: Int
    ) -> String {
        var reversedCharacters: [Character] = []
        var usedUTF16Units = 0
        for character in text.reversed() {
            let characterUTF16Units = String(character).utf16.count
            guard usedUTF16Units + characterUTF16Units <= maximumUTF16Units else {
                break
            }
            reversedCharacters.append(character)
            usedUTF16Units += characterUTF16Units
        }
        return String(reversedCharacters.reversed())
    }
}
