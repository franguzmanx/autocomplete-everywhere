import Foundation

/// A small RAM-only window. Field keys never leave this process.
struct RecentWritingStore {
    typealias Artifact = SuggestionRequestMessage.Payload.Artifact
    private struct Entry {
        let field: String
        let artifact: Artifact
        let documentRange: NSRange
    }
    private var entries: [Entry] = []

    mutating func expire(at timestampMs: Int64) {
        entries.removeAll {
            !ContextArtifactFreshness.isFresh($0.artifact, at: timestampMs)
        }
    }

    mutating func remove(field: String) {
        entries.removeAll { $0.field == field }
    }

    mutating func put(field: String, text: String, documentLocation: Int, kind: String, surface: String, timestampMs: Int64) {
        expire(at: timestampMs)
        let id = entries.first { $0.field == field }?.artifact.id ?? "writing-\(UUID().uuidString)"
        remove(field: field)
        let bounded = BoundedText.suffix(text[...], maximumUTF16Units: 2_000)
        guard !bounded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.removeAll { $0.artifact.text == bounded }
        entries.insert(Entry(field: field, artifact: Artifact(
            id: id,
            kind: kind,
            text: bounded,
            capturedAtMs: timestampMs,
            sourceSurface: surface
        ), documentRange: NSRange(
            location: documentLocation + text.utf16.count - bounded.utf16.count,
            length: bounded.utf16.count
        )), at: 0)
        while entries.count > 3 || entries.reduce(0, { $0 + $1.artifact.text.utf16.count }) > 4_000 {
            entries.removeLast()
        }
    }

    /// Reuse only the bounded fragment we actually observed, at its original
    /// document position. Never retain a second copy of the source document.
    mutating func authorship(field: String, text: String, windowStart: Int, at timestampMs: Int64) -> (range: NSRange, timestampMs: Int64)? {
        expire(at: timestampMs)
        guard let entry = entries.first(where: { $0.field == field }) else { return nil }
        let range = NSRange(
            location: entry.documentRange.location - windowStart,
            length: entry.documentRange.length
        )
        guard range.location >= 0, NSMaxRange(range) <= text.utf16.count,
              let indices = Range(range, in: text), String(text[indices]) == entry.artifact.text else {
            // The known fact changed while unobserved or is no longer available
            // for validation. Do not keep offering its old version elsewhere.
            remove(field: field)
            return nil
        }
        return (range, entry.artifact.capturedAtMs)
    }

    mutating func artifacts(for field: String, at timestampMs: Int64) -> [Artifact] {
        expire(at: timestampMs)
        return entries.filter { $0.field == field }.map(\.artifact)
    }
}
