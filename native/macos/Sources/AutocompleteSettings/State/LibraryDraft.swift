import Foundation

/// Editable projection of a library entry. Kept separate from the wire model so an unsaved draft
/// survives state updates and validation matches the backend schema before a request is sent.
struct LibraryDraft: Equatable, Sendable {
    var id: String?
    var expectedRevision: Int?
    var title: String
    var kind: LibraryKind
    var text: String
    var appIds: [String]
    var anchor: String
    var expiryDate: Date?

    init(kind: LibraryKind = .knowledge) {
        id = nil
        expectedRevision = nil
        title = ""
        self.kind = kind
        text = ""
        appIds = []
        anchor = ""
        expiryDate = nil
    }

    init(entry: LibraryEntry) {
        id = entry.id
        expectedRevision = entry.revision
        title = entry.title
        kind = entry.kind
        text = entry.text
        appIds = entry.scope.appIds
        anchor = entry.scope.anchor
        expiryDate = entry.expiryDate
    }

    var isNew: Bool { id == nil }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedAnchor: String { anchor.trimmingCharacters(in: .whitespacesAndNewlines) }

    enum ValidationIssue: Equatable, Sendable {
        case missingTitle
        case invalidAnchor
        case missingApplications
        case missingText
        case textTooLong
    }

    /// Issues that block saving text. Import ignores text issues.
    var issues: [ValidationIssue] {
        var issues = metadataIssues
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            issues.append(.missingText)
        } else if text.count > LibraryInput.textLimit {
            issues.append(.textTooLong)
        }
        return issues
    }

    /// Issues that block both save and import.
    var metadataIssues: [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if trimmedTitle.isEmpty {
            issues.append(.missingTitle)
        }
        if kind != .style {
            if !LibraryDraft.hasUsableAnchor(trimmedAnchor) {
                issues.append(.invalidAnchor)
            }
            if appIds.isEmpty {
                issues.append(.missingApplications)
            }
        }
        return issues
    }

    var canSave: Bool { issues.isEmpty }
    var canImport: Bool { metadataIssues.isEmpty }

    /// Same rule as the desktop editor: at least three consecutive letters or digits.
    static func hasUsableAnchor(_ anchor: String) -> Bool {
        anchor.range(of: #"[\p{L}\p{N}]{3}"#, options: .regularExpression) != nil
    }

    func input(includeText: Bool = true) -> LibraryInput {
        LibraryInput(
            id: id,
            expectedRevision: expectedRevision,
            title: String(trimmedTitle.prefix(LibraryInput.titleLimit)),
            kind: kind,
            text: includeText ? text : nil,
            scope: LibraryScope(
                appIds: Array(appIds.prefix(LibraryInput.applicationLimit)),
                anchor: String(trimmedAnchor.prefix(LibraryInput.anchorLimit))
            ),
            expiresAt: expiryDate.map { ($0.timeIntervalSince1970 * 1000).rounded() }
        )
    }

    mutating func setApplication(_ appId: String, included: Bool) {
        if included {
            if !appIds.contains(appId) { appIds.append(appId) }
        } else {
            appIds.removeAll { $0 == appId }
        }
    }
}
