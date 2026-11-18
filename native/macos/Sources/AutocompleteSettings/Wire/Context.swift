import Foundation
struct ContextState: Decodable, Equatable, Sendable {
    struct Entry: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let detail: String
        let excerpt: String
    }
    enum VisualStatus: String, Decodable, Sendable { case disabled, permission_required, ready, unverified }
    enum SemanticStatus: String, Decodable, Sendable { case not_prepared, ready, unavailable }
    let semanticStatus: SemanticStatus
    let historyPage: Int
    let visualStatus: VisualStatus
    let visualEnabled: Bool
    let enabled: Bool
    let history: [Entry]
    let connections: [Entry]
    let references: [Entry]
    let used: [Entry]
    static let empty = ContextState(semanticStatus: .not_prepared, historyPage: 0, visualStatus: .disabled, visualEnabled: false, enabled: false, history: [], connections: [], references: [], used: [])
}
