import Foundation

/// Attributes bounded Accessibility edits to recent user input. Keyboard input
/// only marks an opportunity; its characters are never retained here.
final class RecentWritingContext: @unchecked Sendable {
    private struct Observation {
        let field: String
        let target: String
        let focus: UInt64
        let text: String
        let windowStart: Int
    }
    private let lock = NSLock()
    private var enabled = false
    private var excludedApplications: Set<String> = []
    private var previous: Observation?
    private var authoredRange: NSRange?
    private var lastAuthoredMs: Int64?
    private var editDeadlineMs: Int64?
    private var readFailureStartedMs: Int64?
    private var store = RecentWritingStore()

    func updateConfiguration(_ configuration: CaptureConfiguration) {
        lock.withLock {
            let exclusionsChanged = excludedApplications != configuration.excludedApplications
            excludedApplications = configuration.excludedApplications
            enabled = configuration.isEnabled
            if !enabled || exclusionsChanged {
                previous = nil
                authoredRange = nil
                editDeadlineMs = nil
                readFailureStartedMs = nil
                store = RecentWritingStore()
            }
        }
    }

    func noteUserEdit(timestampMs: Int64) {
        lock.withLock {
            guard enabled, previous != nil else { return }
            expireAuthorship(at: timestampMs)
            editDeadlineMs = timestampMs + 1_000
        }
    }

    func observe(_ result: ActiveFieldCaptureResult, timestampMs: Int64) {
        lock.withLock {
            guard enabled else { return }
            store.expire(at: timestampMs)
            guard case let .captured(snapshot) = result else {
                if case let .skipped(reason) = result, reason.isTransientReadFailure {
                    let started = readFailureStartedMs ?? timestampMs
                    readFailureStartedMs = started
                    // Keep the last safe baseline through a brief AX publication
                    // gap. Field identity and the input deadline still gate edits.
                    if timestampMs >= started, timestampMs - started < 1_000 { return }
                }
                previous = nil
                authoredRange = nil
                editDeadlineMs = nil
                return
            }
            guard !excludedApplications.contains(snapshot.applicationBundleIdentifier) else { return }
            if let started = readFailureStartedMs,
               timestampMs < started || timestampMs - started >= 1_000 {
                previous = nil
                authoredRange = nil
                editDeadlineMs = nil
            }
            readFailureStartedMs = nil
            observe(snapshot, timestampMs: timestampMs)
        }
    }

    func recordAcceptance(text: String, snapshot: ActiveFieldSnapshot, timestampMs: Int64) {
        lock.withLock {
            guard enabled, !excludedApplications.contains(snapshot.applicationBundleIdentifier), !text.isEmpty, snapshot.textBefore.hasSuffix(text) else { return }
            expireAuthorship(at: timestampMs)
            let current = observation(snapshot)
            // The inserter has already verified these exact bytes in this field.
            let insertedRange = NSRange(
                location: snapshot.textBefore.utf16.count - text.utf16.count,
                length: text.utf16.count
            )
            var range = insertedRange
            if let old = previous, old.field == current.field, old.focus == current.focus,
               old.windowStart == current.windowStart, let owned = authoredRange,
               NSMaxRange(owned) == insertedRange.location {
                range = NSRange(location: owned.location, length: owned.length + insertedRange.length)
            }
            previous = current
            authoredRange = range
            editDeadlineMs = nil
            retain(current, range: range, kind: "accepted_completion", surface: snapshot.surface.protocolValue, at: timestampMs)
        }
    }

    /// Automatic recall is bound to the same app and physical field. Cross-field
    /// reuse requires explicit selection/clipboard or the scoped library.
    func artifacts(for snapshot: ActiveFieldSnapshot, timestampMs: Int64) -> [SuggestionRequestMessage.Payload.Artifact] {
        lock.withLock {
            guard enabled else { return [] }
            return store.artifacts(for: fieldKey(snapshot), at: timestampMs)
        }
    }

    private func observe(_ snapshot: ActiveFieldSnapshot, timestampMs: Int64) {
        let current = observation(snapshot)
        defer { previous = current }
        if let old = previous, old.target == current.target, old.field != current.field {
            store.remove(field: old.field)
            authoredRange = nil
            lastAuthoredMs = nil
            editDeadlineMs = nil
        }
        guard let old = previous, old.field == current.field, old.focus == current.focus else {
            let remembered = store.authorship(
                field: current.field, text: current.text,
                windowStart: current.windowStart, at: timestampMs
            )
            authoredRange = remembered?.range
            lastAuthoredMs = remembered?.timestampMs
            editDeadlineMs = nil
            return
        }
        guard old.text != current.text || old.windowStart != current.windowStart else { return }
        guard let deadline = editDeadlineMs, timestampMs <= deadline else {
            // Unattributed host replacements must not leave a known stale version.
            store.remove(field: current.field)
            authoredRange = nil
            editDeadlineMs = nil
            return
        }
        editDeadlineMs = nil
        let commonStart = max(old.windowStart, current.windowStart)
        let oldSkip = commonStart - old.windowStart
        let newSkip = commonStart - current.windowStart
        guard oldSkip <= old.text.utf16.count, newSkip <= current.text.utf16.count,
              let oldSlice = Range(NSRange(location: oldSkip, length: old.text.utf16.count - oldSkip), in: old.text),
              let newSlice = Range(NSRange(location: newSkip, length: current.text.utf16.count - newSkip), in: current.text)
        else {
            authoredRange = nil
            store.remove(field: current.field)
            return
        }
        let before = Array(old.text[oldSlice])
        let after = Array(current.text[newSlice])
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
        let start = String(before.prefix(prefix)).utf16.count
        let removed = String(before[prefix..<(before.count - suffix)]).utf16.count
        let inserted = String(after[prefix..<(after.count - suffix)]).utf16.count
        var range = NSRange(location: start + newSkip, length: inserted)
        if let owned = authoredRange, owned.location >= oldSkip {
            let ownedStart = owned.location - oldSkip
            let ownedEnd = NSMaxRange(owned) - oldSkip
            if start <= ownedEnd, start + removed >= ownedStart {
                let mergedStart = min(start, ownedStart)
                let mergedEnd = max(start + removed, ownedEnd) + inserted - removed
                range = NSRange(location: mergedStart + newSkip, length: mergedEnd - mergedStart)
            } else if inserted == 0 {
                range = NSRange(
                    location: ownedStart + newSkip + (start < ownedStart ? -removed : 0),
                    length: owned.length
                )
            }
        }
        authoredRange = range.length > 0 ? range : nil
        retain(current, range: range, kind: "recent_writing", surface: snapshot.surface.protocolValue, at: timestampMs)
    }

    private func retain(_ current: Observation, range: NSRange, kind: String, surface: String, at timestampMs: Int64) {
        guard range.length > 0, let indices = Range(range, in: current.text) else {
            store.remove(field: current.field)
            return
        }
        lastAuthoredMs = timestampMs
        store.put(
            field: current.field, text: String(current.text[indices]),
            documentLocation: current.windowStart + range.location,
            kind: kind, surface: surface, timestampMs: timestampMs
        )
    }

    private func expireAuthorship(at timestampMs: Int64) {
        if let lastAuthoredMs,
           timestampMs < lastAuthoredMs || timestampMs - lastAuthoredMs >= 300_000 {
            authoredRange = nil
            self.lastAuthoredMs = nil
        }
    }

    private func observation(_ snapshot: ActiveFieldSnapshot) -> Observation {
        Observation(
            field: fieldKey(snapshot),
            target: physicalFieldKey(snapshot),
            focus: snapshot.focusGeneration,
            text: snapshot.textBefore + snapshot.selectedText + snapshot.textAfter,
            windowStart: snapshot.selectionRange.location - snapshot.textBefore.utf16.count
        )
    }

    private func fieldKey(_ snapshot: ActiveFieldSnapshot) -> String {
        physicalFieldKey(snapshot) + "\u{0}" + snapshot.recentWritingContextSignature
    }

    private func physicalFieldKey(_ snapshot: ActiveFieldSnapshot) -> String {
        snapshot.applicationBundleIdentifier + "\u{0}" + snapshot.elementIdentifier
    }
}
