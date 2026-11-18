import Foundation

enum ActiveFieldShape: String, Codable, Equatable, Sendable {
    case singleLine = "single_line"
    case multiline
}

struct RelatedFieldContext: Codable, Equatable, Sendable {
    let shape: ActiveFieldShape
    let label: String?
    let placeholder: String?
    let text: String
}

struct RelatedFieldCandidate: Equatable, Sendable {
    let role: String
    let subrole: String?
    let label: String?
    let placeholder: String?
    let identifier: String?
    let text: String
    let frame: CGRect?
}

struct FieldSource: Codable, Equatable, Sendable {
    enum Relation: String, Codable, Sendable {
        case labelledBy = "labelled_by"
        case describedBy = "described_by"
        case sharedContainer = "shared_container"
        var priority: Int {
            switch self {
            case .labelledBy: 0
            case .describedBy: 1
            case .sharedContainer: 2
            }
        }
    }
    static let maximumCount = 24
    static let maximumTotalUTF16 = 12_000

    static func strongestUnique(_ sources: [FieldSource]) -> [FieldSource] {
        var order: [String] = []
        var strongest: [String: FieldSource] = [:]
        for source in sources {
            if let existing = strongest[source.id] {
                guard source.relation.priority < existing.relation.priority else { continue }
            } else {
                order.append(source.id)
            }
            strongest[source.id] = source
        }
        var remaining = maximumTotalUTF16
        var result: [FieldSource] = []
        for id in order.prefix(maximumCount) {
            guard remaining > 0, let source = strongest[id] else { break }
            let text = BoundedText.prefix(source.text[...], maximumUTF16Units: remaining)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result.append(FieldSource(id: source.id, containerId: source.containerId, relation: source.relation, text: text))
            remaining -= text.utf16.count
        }
        return result
    }

    let id: String
    let containerId: String
    let relation: Relation
    let text: String
    init(id: String, containerId: String, relation: Relation, text: String) {
        self.id = String(id.prefix(64))
        self.containerId = String(containerId.prefix(64))
        self.relation = relation
        self.text = BoundedText.prefix(text[...], maximumUTF16Units: 2_000)
    }
}

struct ActiveFieldContext: Codable, Equatable, Sendable {
    let shape: ActiveFieldShape
    let label: String?
    let placeholder: String?
    let relatedFields: [RelatedFieldContext]
    let sources: [FieldSource]

    init(
        shape: ActiveFieldShape,
        label: String? = nil,
        placeholder: String? = nil,
        relatedFields: [RelatedFieldContext] = [],
        sources: [FieldSource] = []
    ) {
        self.shape = shape
        self.label = Self.bounded(label)
        self.placeholder = Self.bounded(placeholder)
        self.relatedFields = relatedFields
        self.sources = FieldSource.strongestUnique(sources)
    }

    private static func bounded(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(160))
    }
}

enum SuggestionRequestEligibility {
    static func shouldRequest(
        textBefore: String,
        selectedText: String,
        textAfter: String,
        fieldContext: ActiveFieldContext
    ) -> Bool {
        if !textBefore.isEmpty || !selectedText.isEmpty || !textAfter.isEmpty {
            return true
        }
        return fieldContext.sources.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } || fieldContext.relatedFields.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
