import Foundation

enum TransformRule: String, Codable, Sendable, CaseIterable, Identifiable {
    case concise, clarity, reorder, structure, tone
    var id: String { rawValue }

}

struct WritingTransform: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var shortcut: Int
    var rules: [TransformRule]
    var prompt: String
    var examples: [String]

    var isValid: Bool {
        UUID(uuidString: id) != nil && (1...9).contains(shortcut)
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.utf16.count <= 60 && prompt.utf16.count <= 4_000
            && (rules.count > 0 || !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && rules.count <= 5 && examples.count <= 3
            && examples.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 4_000 }
    }
}

struct TransformSettings: Codable, Sendable, Equatable {
    var enabled: Bool
    var transforms: [WritingTransform]

    var isValid: Bool {
        transforms.count <= 9 && transforms.allSatisfy(\.isValid)
            && Set(transforms.map(\.id)).count == transforms.count
            && Set(transforms.map(\.shortcut)).count == transforms.count
    }
}

struct TransformInput: Codable, Sendable, Equatable {
    let text: String
    let transform: WritingTransform
    let singleLine: Bool
}
