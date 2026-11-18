import Foundation

struct LatencySummary: Codable, Sendable, Equatable {
    var p50: Double?
    var p95: Double?
    var samples: Int
}

/// Session counters only; never the text typed or suggested.
struct SuggestionActivitySummary: Codable, Sendable, Equatable {
    var since: String
    var requested: Int
    var generated: Int
    var suppressed: Int
    var failed: Int
    var cancelled: Int
    var shown: Int
    var accepted: Int
    var typedThrough: Int
    var dismissed: Int
    var stale: Int
    var acceptedCharacters: Int
    var requestToVisibleMs: LatencySummary
    var requestToFinalMs: LatencySummary
    var lastOutcome: String?

    var sinceDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: since)
    }
}
