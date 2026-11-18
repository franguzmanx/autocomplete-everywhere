import Foundation

// Mirrors LibraryEntry / LibraryInput / LibraryImportInput from apps/desktop/src/shared/contracts.ts
// and knowledgeCandidateSchema from packages/protocol/src/knowledge.ts.

enum LibraryKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case knowledge
    case memory
    case style

    var id: String { rawValue }
}

struct LibraryScope: Codable, Sendable, Equatable {
    var appIds: [String]
    var anchor: String
}

enum LibraryProvenance: Sendable, Equatable {
    case user
    case file(name: String)
}

extension LibraryProvenance: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "user":
            self = .user
        case "file":
            self = .file(name: try container.decode(String.self, forKey: .name))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown provenance kind"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user:
            try container.encode("user", forKey: .kind)
        case .file(let name):
            try container.encode("file", forKey: .kind)
            try container.encode(name, forKey: .name)
        }
    }
}

struct LibraryEntry: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var kind: LibraryKind
    var text: String
    var revision: Int
    var updatedAt: Double
    var expiresAt: Double?
    var scope: LibraryScope
    var createdAt: Double
    var provenance: LibraryProvenance

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
    var createdDate: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    var expiryDate: Date? { expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    func isExpired(at now: Date) -> Bool {
        guard let expiryDate else { return false }
        return expiryDate <= now
    }
}

/// Outgoing save/import payload. `expiresAt` is always present (null when unset) because the
/// backend schema requires the key; `id`, `expectedRevision` and `text` are omitted when absent.
struct LibraryInput: Sendable, Equatable {
    var id: String?
    var expectedRevision: Int?
    var title: String
    var kind: LibraryKind
    var text: String?
    var scope: LibraryScope
    var expiresAt: Double?

    static let titleLimit = 120
    static let anchorLimit = 200
    static let textLimit = 12_000
    static let applicationLimit = 20

    /// Same input without text, as expected by `libraryImport`.
    var withoutText: LibraryInput {
        var copy = self
        copy.text = nil
        return copy
    }
}

extension LibraryInput: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case expectedRevision
        case title
        case kind
        case text
        case scope
        case expiresAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(expectedRevision, forKey: .expectedRevision)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encode(scope, forKey: .scope)
        if let expiresAt {
            try container.encode(Int64(expiresAt), forKey: .expiresAt)
        } else {
            try container.encodeNil(forKey: .expiresAt)
        }
    }
}
