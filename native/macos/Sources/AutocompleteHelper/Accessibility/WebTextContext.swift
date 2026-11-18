import Foundation

/// Text owned by the focused editable itself. Web text markers remain useful
/// for caret geometry, but some hosts scope their marker range to the entire
/// document. AXValue plus AXSelectedTextRange is the field boundary.
struct FocusedEditableText: Equatable, Sendable {
    let textBefore: String
    let selectedText: String
    let textAfter: String
    let selectionLocation: Int
    let selectionLength: Int

    init?(value: String, selection: NSRange) {
        guard selection.location >= 0,
              selection.length >= 0,
              let range = Range(selection, in: value)
        else { return nil }
        textBefore = String(value[..<range.lowerBound])
        selectedText = String(value[range])
        textAfter = String(value[range.upperBound...])
        selectionLocation = selection.location
        selectionLength = selection.length
    }

    static let empty = FocusedEditableText(
        textBefore: "",
        selectedText: "",
        textAfter: "",
        selectionLocation: 0,
        selectionLength: 0
    )

    private init(
        textBefore: String,
        selectedText: String,
        textAfter: String,
        selectionLocation: Int,
        selectionLength: Int
    ) {
        self.textBefore = textBefore
        self.selectedText = selectedText
        self.textAfter = textAfter
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
    }
}

/// Everything the capture needs from an editable element inside an
/// `AXWebArea`. Field content is bounded by the focused element's AXValue;
/// text markers provide selection-relative geometry and typography only.
///
/// Web hosts (WebKit, Chromium, Electron) do not expose reliable index-based
/// geometry APIs for rich editors: Chromium reports hypertext offsets, and its
/// `AXIndexForTextMarker` can be zero for every marker. Text markers anchored
/// at the selection avoid geometry index arithmetic. All rectangles are in
/// Accessibility screen coordinates.
struct WebTextContext: Equatable, Sendable {
    /// Stable identity of the editable root (process + element token).
    let editableIdentifier: String
    let role: String
    let subrole: String?
    let textBefore: String
    let selectedText: String
    let textAfter: String
    /// UTF-16 offset of the selection start within the editable's full text.
    let selectionLocation: Int
    let selectionLength: Int
    let frame: CGRect?
    /// Candidate caret rectangles the reader could measure. Grapheme
    /// candidates come from single-character marker ranges; line-edge
    /// candidates are the fallback when a host exposes only line boxes.
    let caretCandidates: [CaretGeometryCandidate]
    /// Box of the line containing the selection start, when the host reports
    /// one.
    let lineBounds: CGRect?
    /// Union box of the paragraph containing the selection start.
    let paragraphBounds: CGRect?
    /// Text from the paragraph start to the selection start (bounded suffix).
    let paragraphTextBefore: String
    let paragraphTextBeforeIsComplete: Bool
    /// Font runs covering `paragraphTextBefore` when the host publishes font
    /// information in its attributed strings (WebKit does; Chromium does not).
    let paragraphStyleRuns: [ActiveFieldTextStyleRun]?
    /// Style measured at the caret boundary when the paragraph itself is
    /// empty, including hosts that publish their placeholder as synthetic text.
    let caretTextStyle: ActiveFieldTextStyle?
    /// Tight screen-space bounds occupied by a synthetic host placeholder.
    /// Nil for real text and for empty fields whose host does not publish a
    /// placeholder as text.
    let hostPlaceholderBounds: CGRect?
    let paragraphAttributes: ActiveFieldParagraphAttributes?
    /// Semantic metadata belongs to the field, not to its editable value.
    /// In particular, `placeholder` must never be folded into `textBefore` or
    /// `textAfter`.
    let label: String?
    let placeholder: String?
    let semanticIdentifier: String?
    let relatedFields: [RelatedFieldContext]

    init(
        editableIdentifier: String,
        role: String,
        subrole: String? = nil,
        textBefore: String,
        selectedText: String = "",
        textAfter: String = "",
        selectionLocation: Int? = nil,
        selectionLength: Int? = nil,
        frame: CGRect?,
        caretCandidates: [CaretGeometryCandidate] = [],
        lineBounds: CGRect? = nil,
        paragraphBounds: CGRect? = nil,
        paragraphTextBefore: String? = nil,
        paragraphTextBeforeIsComplete: Bool = true,
        paragraphStyleRuns: [ActiveFieldTextStyleRun]? = nil,
        caretTextStyle: ActiveFieldTextStyle? = nil,
        hostPlaceholderBounds: CGRect? = nil,
        paragraphAttributes: ActiveFieldParagraphAttributes? = nil,
        label: String? = nil,
        placeholder: String? = nil,
        semanticIdentifier: String? = nil,
        relatedFields: [RelatedFieldContext] = []
    ) {
        self.editableIdentifier = editableIdentifier
        self.role = role
        self.subrole = subrole
        self.textBefore = textBefore
        self.selectedText = selectedText
        self.textAfter = textAfter
        self.selectionLocation = selectionLocation ?? textBefore.utf16.count
        self.selectionLength = selectionLength ?? selectedText.utf16.count
        self.frame = frame
        self.caretCandidates = caretCandidates
        self.lineBounds = lineBounds
        self.paragraphBounds = paragraphBounds
        self.paragraphTextBefore = paragraphTextBefore
            ?? Self.currentParagraph(of: textBefore)
        self.paragraphTextBeforeIsComplete = paragraphTextBeforeIsComplete
        self.paragraphStyleRuns = paragraphStyleRuns
        self.caretTextStyle = caretTextStyle
        self.hostPlaceholderBounds = hostPlaceholderBounds
        self.paragraphAttributes = paragraphAttributes
        self.label = label
        self.placeholder = placeholder
        self.semanticIdentifier = semanticIdentifier
        self.relatedFields = relatedFields
    }

    private static func currentParagraph(of text: String) -> String {
        guard let newline = text.lastIndex(where: { $0.isNewline }) else {
            return text
        }
        return String(text[text.index(after: newline)...])
    }
}
