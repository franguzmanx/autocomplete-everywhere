import Foundation

/// Original capture time owns expiry, including when a new alternative is
/// requested. Reusing a snapshot must never renew its supporting evidence.
enum ContextArtifactFreshness {
    static func isFresh(_ artifact: SuggestionRequestMessage.Payload.Artifact, at timestampMs: Int64) -> Bool {
        guard artifact.capturedAtMs >= 0, timestampMs >= artifact.capturedAtMs else { return false }
        let lifetime: Int64
        switch artifact.kind {
        case "selection": lifetime = 60_000
        case "recent_writing", "accepted_completion": lifetime = 300_000
        case "clipboard": lifetime = 600_000
        case "saved": return true
        default: return false
        }
        return timestampMs - artifact.capturedAtMs < lifetime
    }
}
