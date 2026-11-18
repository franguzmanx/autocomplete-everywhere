import Foundation

enum PreferenceDimension: String, Codable, Sendable, CaseIterable {
    case concision, formality, structure

    var values: [String] {
        switch self {
        case .concision: ["concise", "balanced", "detailed"]
        case .formality: ["casual", "neutral", "formal"]
        case .structure: ["paragraphs", "lists"]
        }
    }
}

enum PreferenceOrigin: String, Codable, Sendable { case learned, explicit }

struct StylePreference: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var dimension: PreferenceDimension
    var value: String
    var appId: String?
    var origin: PreferenceOrigin

    private enum CodingKeys: String, CodingKey { case id, dimension, value, appId, origin }
    init(id: String, dimension: PreferenceDimension, value: String, appId: String?, origin: PreferenceOrigin) {
        self.id = id; self.dimension = dimension; self.value = value; self.appId = appId; self.origin = origin
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dimension = try container.decode(PreferenceDimension.self, forKey: .dimension)
        value = try container.decode(String.self, forKey: .value)
        origin = try container.decode(PreferenceOrigin.self, forKey: .origin)
        // A missing scope must never turn a malformed preference into a global one.
        guard container.contains(.appId) else {
            throw DecodingError.keyNotFound(CodingKeys.appId, .init(codingPath: decoder.codingPath, debugDescription: "Missing scope"))
        }
        appId = try container.decodeIfPresent(String.self, forKey: .appId)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(dimension, forKey: .dimension)
        try container.encode(value, forKey: .value)
        try container.encode(appId, forKey: .appId)
        try container.encode(origin, forKey: .origin)
    }

    var isValid: Bool {
        UUID(uuidString: id) != nil && dimension.values.contains(value)
        && (appId.map { $0.count <= 255 && $0.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil } ?? (origin == .explicit))
    }
}

struct PersonalizationSnapshot: Codable, Equatable, Sendable {
    var enabled: Bool
    var revision: Int
    var preferences: [StylePreference]
    static let empty = Self(enabled: false, revision: 0, preferences: [])

    var isValid: Bool {
        revision >= 0 && preferences.count <= 24 && preferences.allSatisfy(\.isValid)
        && Set(preferences.map(\.id)).count == preferences.count
    }
}

struct PersonalizationEdit: Codable, Equatable, Sendable {
    var accountSubject: String
    var enabled: Bool
    var edits: [StylePreference] = []
    var forgetIds: [String] = []
    var reset = false
}

struct WritingSaveResult: Decodable {
    var personalization: PersonalizationSnapshot
}
