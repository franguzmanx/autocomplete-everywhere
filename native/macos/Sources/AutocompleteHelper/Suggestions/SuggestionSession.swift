import Foundation

enum SuggestionSessionState: Equatable {
    case idle
    case requesting(identity: SuggestionRequestMessage.Identity)
    case ready(
        identity: SuggestionRequestMessage.Identity,
        text: String,
        snapshot: ActiveFieldSnapshot
    )
    case accepting(
        identity: SuggestionRequestMessage.Identity,
        text: String,
        snapshot: ActiveFieldSnapshot
    )
}

struct ReservedSuggestion: Equatable {
    let identity: SuggestionRequestMessage.Identity
    let text: String
    let snapshot: ActiveFieldSnapshot
    let typedThroughCharacters: Int
    let remainingText: String
    let isPartialAcceptance: Bool
}

struct SuggestionPresentation: Equatable {
    let identity: SuggestionRequestMessage.Identity
    let text: String
    let snapshot: ActiveFieldSnapshot
}

enum SuggestionTypeThroughResult: Equatable {
    case ignored
    case advanced(
        presentation: SuggestionPresentation,
        acceptedCharacters: Int,
        typedText: String
    )
    case completed(
        identity: SuggestionRequestMessage.Identity,
        snapshot: ActiveFieldSnapshot,
        acceptedCharacters: Int
    )
    case cancelled(CancelRequestMessage)
}

enum SuggestionInputPreviewResult: Equatable {
    case ignored
    case advanced(
        presentation: SuggestionPresentation,
        acceptedCharacters: Int
    )
    case completed(
        identity: SuggestionRequestMessage.Identity,
        acceptedCharacters: Int
    )
    case cancelled(CancelRequestMessage)
}

enum SuggestionResponseDisposition: Equatable {
    case accepted
    case ignoredStale
    case rejectedCurrent
}

final class SuggestionSession: @unchecked Sendable {
    private let lock = NSLock()
    private var storedState: SuggestionSessionState = .idle
    private var requestSnapshot: ActiveFieldSnapshot?
    private var exactReferences: [String] = []
    private var consumedSuggestionPrefix = ""
    private var typedThroughUTF16Count = 0
    private var pendingTypedText = ""
    private var pendingSuggestionPrefix = ""

    var state: SuggestionSessionState {
        lock.withLock { storedState }
    }

    var currentIdentity: SuggestionRequestMessage.Identity? {
        lock.withLock { activeIdentity }
    }

    func snapshotForRequest(_ identity: SuggestionRequestMessage.Identity) -> ActiveFieldSnapshot? {
        lock.withLock { activeIdentity == identity ? requestSnapshot : nil }
    }

    var protectedText: [String] { lock.withLock { exactReferences } }

    /// The ready text is the insertion authority. The discarded tail cannot
    /// return on a geometry refresh, type-through or acceptance.
    func selectVisiblePrefix(_ text: String, identity: SuggestionRequestMessage.Identity) -> Bool {
        lock.withLock {
            guard case let .ready(current, original, snapshot) = storedState,
                  current == identity, pendingTypedText.isEmpty,
                  !text.isEmpty, original.hasPrefix(text),
                  VisibleSuggestionPrefix.select(original, maximumUTF16Count: text.utf16.count,
                      protectedText: exactReferences) == text
            else { return false }
            storedState = .ready(identity: identity, text: text, snapshot: snapshot)
            return true
        }
    }

    var hasReadySuggestion: Bool {
        lock.withLock {
            if case .ready = storedState { return true }
            return false
        }
    }

    func isAccepting(identity: SuggestionRequestMessage.Identity) -> Bool {
        lock.withLock {
            guard case let .accepting(current, _, _) = storedState else { return false }
            return current == identity
        }
    }

    /// True when locally typed text was previewed but the host still reports
    /// the pre-typing content: the keystroke did not reach this field.
    func hasUnconfirmedPreview(against snapshot: ActiveFieldSnapshot) -> Bool {
        lock.withLock {
            guard !pendingTypedText.isEmpty else { return false }
            switch storedState {
            case let .ready(_, _, stored):
                return stored.contentSignature == snapshot.contentSignature
            default:
                return false
            }
        }
    }

    @discardableResult
    func begin(
        _ message: SuggestionRequestMessage,
        snapshot: ActiveFieldSnapshot
    ) -> CancelRequestMessage? {
        lock.withLock {
            let cancellation = activeIdentity.map { identity in
                let reason: CancelRequestReason =
                    snapshot.focusGeneration == identity.focusSequence
                    ? .contentChanged
                    : .focusChanged
                return CancelRequestMessage(
                    identity: identity,
                    payload: .init(reason: reason)
                )
            }
            consumedSuggestionPrefix = ""
            typedThroughUTF16Count = 0
            pendingTypedText = ""
            pendingSuggestionPrefix = ""
            requestSnapshot = snapshot
            exactReferences = message.payload.artifacts.map(\.text)
            storedState = .requesting(identity: message.identity)
            return cancellation
        }
    }

    @discardableResult
    func handle(_ command: HelperCommand) -> SuggestionResponseDisposition {
        switch command {
        case let .suggestionFinal(final):
            return acceptFinal(final)
        case let .requestFailed(failure):
            return acceptFailure(failure)
        case .contextInvalidate, .contextRequestScreenPermission, .configure, .requestSuggestion, .transformConfigure, .transformResult:
            return .ignoredStale
        }
    }

    @discardableResult
    func dismiss(
        reason: CancelRequestReason = .dismissed
    ) -> CancelRequestMessage? {
        lock.withLock {
            guard let identity = activeIdentity else { return nil }
            resetState()
            return CancelRequestMessage(
                identity: identity,
                payload: .init(reason: reason)
            )
        }
    }

    @discardableResult
    func invalidate(
        with snapshot: ActiveFieldSnapshot?
    ) -> CancelRequestMessage? {
        lock.withLock {
            guard let identity = activeIdentity else { return nil }
            let reason: CancelRequestReason =
                snapshot?.focusGeneration == identity.focusSequence
                ? .contentChanged
                : .focusChanged
            resetState()
            return CancelRequestMessage(
                identity: identity,
                payload: .init(reason: reason)
            )
        }
    }

    func canAccept(
        visibleIdentity: SuggestionRequestMessage.Identity,
        visibleText: String?,
        stabilizedSnapshot: ActiveFieldSnapshot?
    ) -> Bool {
        return lock.withLock {
            guard case let .ready(identity, text, storedSnapshot) = storedState,
                  identity == visibleIdentity,
                  visibleText == text,
                  pendingTypedText.isEmpty,
                  let stabilizedSnapshot,
                  isValidAcceptanceSnapshot(
                    stabilizedSnapshot,
                    for: identity,
                    storedSnapshot: storedSnapshot
                  )
            else {
                if activeIdentity == visibleIdentity { resetState() }
                return false
            }
            storedState = .ready(
                identity: identity,
                text: text,
                snapshot: stabilizedSnapshot
            )
            return true
        }
    }

    func reserveAcceptance(
        visibleIdentity: SuggestionRequestMessage.Identity,
        visibleText: String?,
        stabilizedSnapshot: ActiveFieldSnapshot?,
        nextWordOnly: Bool = false
    ) -> ReservedSuggestion? {
        return lock.withLock {
            guard case let .ready(identity, text, storedSnapshot) = storedState,
                  identity == visibleIdentity,
                  visibleText == text,
                  pendingTypedText.isEmpty,
                  let stabilizedSnapshot,
                  isValidAcceptanceSnapshot(
                    stabilizedSnapshot,
                    for: identity,
                    storedSnapshot: storedSnapshot
                  )
            else {
                if activeIdentity == visibleIdentity { resetState() }
                return nil
            }
            let insertionText = nextWordOnly ? Self.nextWordPrefix(text) : text
            guard !insertionText.isEmpty else { return nil }
            storedState = .accepting(
                identity: identity,
                text: text,
                snapshot: stabilizedSnapshot
            )
            return ReservedSuggestion(
                identity: identity,
                text: insertionText,
                snapshot: stabilizedSnapshot,
                typedThroughCharacters: typedThroughUTF16Count,
                remainingText: String(text.dropFirst(insertionText.count)),
                isPartialAcceptance: nextWordOnly || !consumedSuggestionPrefix.isEmpty
            )
        }
    }

    /// Restore only the uninserted suffix, anchored to the verified host
    /// result. A cancelled session or a changed field must never reappear.
    func resumeAfterPartialAcceptance(
        _ reserved: ReservedSuggestion,
        snapshot: ActiveFieldSnapshot
    ) -> Bool {
        lock.withLock {
            guard case let .accepting(identity, text, previous) = storedState,
                  identity == reserved.identity
            else { return false }
            guard !reserved.remainingText.isEmpty,
                  text == reserved.text + reserved.remainingText,
                  snapshot.applicationBundleIdentifier == previous.applicationBundleIdentifier,
                  snapshot.surface == previous.surface,
                  snapshot.elementIdentifier == previous.elementIdentifier,
                  snapshot.focusGeneration == previous.focusGeneration,
                  snapshot.captureSequence >= previous.captureSequence,
                  let match = Self.typedMatch(from: previous, to: snapshot, visibleSuggestion: text),
                  match.typedText == reserved.text
            else {
                resetState()
                return false
            }
            consumedSuggestionPrefix.append(contentsOf: reserved.text)
            // These characters are reported by this acceptance. Future
            // acceptances report only their own additional characters.
            typedThroughUTF16Count = 0
            storedState = .ready(identity: identity, text: reserved.remainingText, snapshot: snapshot)
            return true
        }
    }

    /// A whitespace-delimited word, including its adjacent separators.
    /// Character indices preserve accents, emoji and joined graphemes.
    private static func nextWordPrefix(_ text: String) -> String {
        var end = text.startIndex
        while end < text.endIndex && text[end].isWhitespace { text.formIndex(after: &end) }
        while end < text.endIndex && !text[end].isWhitespace { text.formIndex(after: &end) }
        while end < text.endIndex && text[end].isWhitespace { text.formIndex(after: &end) }
        return String(text[..<end])
    }

    func presentation(
        for identity: SuggestionRequestMessage.Identity
    ) -> SuggestionPresentation? {
        presentationFromLastValidatedSnapshot(for: identity)
    }

    func presentationFromLastValidatedSnapshot(
        for identity: SuggestionRequestMessage.Identity
    ) -> SuggestionPresentation? {
        lock.withLock {
            switch storedState {
            case let .ready(currentIdentity, text, snapshot)
                where currentIdentity == identity:
                return makePresentation(
                    identity: currentIdentity,
                    text: text,
                    snapshot: snapshot
                )
            default:
                return nil
            }
        }
    }

    func previewTypeThrough(
        _ typedText: String
    ) -> SuggestionInputPreviewResult {
        lock.withLock {
            let current: (
                identity: SuggestionRequestMessage.Identity,
                text: String,
                snapshot: ActiveFieldSnapshot
            )
            switch storedState {
            case let .ready(identity, text, snapshot):
                current = (identity, text, snapshot)
            default:
                return .ignored
            }

            guard
                let visibleText = visibleSuggestionText(current.text),
                let consumed = Self.consumedSuggestionText(
                    for: typedText,
                    in: visibleText
                )
            else {
                resetState()
                return .cancelled(
                    CancelRequestMessage(
                        identity: current.identity,
                        payload: .init(reason: .contentChanged)
                    )
                )
            }

            pendingTypedText.append(contentsOf: typedText)
            pendingSuggestionPrefix.append(contentsOf: consumed)
            let acceptedCharacters = typedThroughUTF16Count
                + pendingTypedText.utf16.count
            guard let remaining = visibleSuggestionText(current.text),
                  !remaining.isEmpty
            else {
                return .completed(
                    identity: current.identity,
                    acceptedCharacters: acceptedCharacters
                )
            }
            return .advanced(
                presentation: SuggestionPresentation(
                    identity: current.identity,
                    text: remaining,
                    snapshot: current.snapshot
                ),
                acceptedCharacters: acceptedCharacters
            )
        }
    }

    func reconcileTypeThrough(
        with snapshot: ActiveFieldSnapshot
    ) -> SuggestionTypeThroughResult {
        lock.withLock {
            let current: (
                identity: SuggestionRequestMessage.Identity,
                text: String,
                snapshot: ActiveFieldSnapshot
            )
            switch storedState {
            case let .ready(identity, text, storedSnapshot):
                current = (identity, text, storedSnapshot)
            default:
                return .ignored
            }

            guard
                snapshot.applicationBundleIdentifier
                    == current.snapshot.applicationBundleIdentifier,
                snapshot.elementIdentifier == current.snapshot.elementIdentifier,
                snapshot.focusGeneration == current.snapshot.focusGeneration
            else {
                return cancelTypeThrough(
                    identity: current.identity,
                    reason: .focusChanged
                )
            }
            guard !pendingTypedText.isEmpty else {
                return cancelTypeThrough(
                    identity: current.identity,
                    reason: .contentChanged
                )
            }
            guard let match = Self.typedMatch(
                from: current.snapshot,
                to: snapshot,
                visibleSuggestion: current.text
            ) else {
                return cancelTypeThrough(
                    identity: current.identity,
                    reason: .contentChanged
                )
            }

            if !pendingTypedText.isEmpty || !pendingSuggestionPrefix.isEmpty {
                guard
                    pendingTypedText.hasPrefix(match.typedText),
                    pendingSuggestionPrefix.hasPrefix(
                        match.consumedSuggestionText
                    )
                else {
                    return cancelTypeThrough(
                        identity: current.identity,
                        reason: .contentChanged
                    )
                }
                pendingTypedText.removeFirst(match.typedText.count)
                pendingSuggestionPrefix.removeFirst(
                    match.consumedSuggestionText.count
                )
            }

            consumedSuggestionPrefix.append(contentsOf: match.consumedSuggestionText)
            typedThroughUTF16Count += match.typedText.utf16.count
            let confirmedRemaining = String(
                current.text.dropFirst(match.consumedSuggestionText.count)
            )
            let acceptedCharacters = typedThroughUTF16Count
            guard !confirmedRemaining.isEmpty else {
                let identity = current.identity
                resetState()
                return .completed(
                    identity: identity,
                    snapshot: snapshot,
                    acceptedCharacters: acceptedCharacters
                )
            }

            storedState = .ready(
                identity: current.identity,
                text: confirmedRemaining,
                snapshot: snapshot
            )
            let visibleRemaining = visibleSuggestionText(confirmedRemaining) ?? ""
            return .advanced(
                presentation: SuggestionPresentation(
                    identity: current.identity,
                    text: visibleRemaining,
                    snapshot: snapshot
                ),
                acceptedCharacters: acceptedCharacters,
                typedText: match.typedText
            )
        }
    }

    func completeAcceptance(identity: SuggestionRequestMessage.Identity) {
        lock.withLock {
            guard case let .accepting(currentIdentity, _, _) = storedState,
                  currentIdentity == identity
            else {
                return
            }
            resetState()
        }
    }

    private func acceptFinal(
        _ final: SuggestionFinalCommand
    ) -> SuggestionResponseDisposition {
        lock.withLock {
            guard activeIdentity == final.identity else {
                return .ignoredStale
            }
            let snapshot: ActiveFieldSnapshot
            switch storedState {
            case .requesting:
                guard let requestSnapshot else {
                    resetState()
                    return .rejectedCurrent
                }
                snapshot = requestSnapshot
            default:
                resetState()
                return .rejectedCurrent
            }
            switch final.result {
            case .silence:
                resetState()
                return .accepted
            case let .text(text):
                guard
                    text.hasPrefix(consumedSuggestionPrefix),
                    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    text.utf16.count <= 12_000
                else {
                    resetState()
                    return .rejectedCurrent
                }
                let confirmedText = String(
                    text.dropFirst(consumedSuggestionPrefix.count)
                )
                guard !confirmedText.isEmpty,
                      visibleSuggestionText(confirmedText) != nil
                else {
                    resetState()
                    return .rejectedCurrent
                }
                storedState = .ready(
                    identity: final.identity,
                    text: confirmedText,
                    snapshot: snapshot
                )
                return .accepted
            }
        }
    }

    private func acceptFailure(
        _ failure: RequestFailedCommand
    ) -> SuggestionResponseDisposition {
        lock.withLock {
            guard activeIdentity == failure.identity else {
                return .ignoredStale
            }
            resetState()
            return .accepted
        }
    }

    private var activeIdentity: SuggestionRequestMessage.Identity? {
        switch storedState {
        case .idle:
            nil
        case let .requesting(identity),
             let .ready(identity, _, _),
             let .accepting(identity, _, _):
            identity
        }
    }

    private func cancelTypeThrough(
        identity: SuggestionRequestMessage.Identity,
        reason: CancelRequestReason
    ) -> SuggestionTypeThroughResult {
        resetState()
        return .cancelled(
            CancelRequestMessage(
                identity: identity,
                payload: .init(reason: reason)
            )
        )
    }

    private func resetState() {
        storedState = .idle
        consumedSuggestionPrefix = ""
        typedThroughUTF16Count = 0
        pendingTypedText = ""
        pendingSuggestionPrefix = ""
        requestSnapshot = nil
        exactReferences = []
    }

    private func isValidAcceptanceSnapshot(
        _ snapshot: ActiveFieldSnapshot,
        for identity: SuggestionRequestMessage.Identity,
        storedSnapshot: ActiveFieldSnapshot
    ) -> Bool {
        snapshot.geometryQuality != .unavailable
            && snapshot.geometrySource != nil
            && snapshot.caretBounds != nil
            && snapshot.applicationBundleIdentifier
                == storedSnapshot.applicationBundleIdentifier
            && snapshot.elementIdentifier == storedSnapshot.elementIdentifier
            && snapshot.focusGeneration == identity.focusSequence
            && snapshot.contentSignature == storedSnapshot.contentSignature
            && snapshot.recentWritingContextSignature == storedSnapshot.recentWritingContextSignature
            && snapshot.captureSequence >= storedSnapshot.captureSequence
    }

    private func visibleSuggestionText(_ text: String) -> String? {
        guard text.hasPrefix(pendingSuggestionPrefix) else { return nil }
        return String(text.dropFirst(pendingSuggestionPrefix.count))
    }

    private func makePresentation(
        identity: SuggestionRequestMessage.Identity,
        text: String,
        snapshot: ActiveFieldSnapshot
    ) -> SuggestionPresentation? {
        guard let visibleText = visibleSuggestionText(text),
              !visibleText.isEmpty
        else { return nil }
        return SuggestionPresentation(
            identity: identity,
            text: visibleText,
            snapshot: snapshot
        )
    }

    private struct TypedMatch {
        let typedText: String
        let consumedSuggestionText: String
    }

    private static func typedMatch(
        from previous: ActiveFieldSnapshot,
        to current: ActiveFieldSnapshot,
        visibleSuggestion: String
    ) -> TypedMatch? {
        guard
            previous.recentWritingContextSignature == current.recentWritingContextSignature,
            previous.selectedText.isEmpty,
            current.selectedText.isEmpty,
            previous.selectionRange.length == 0,
            current.selectionRange.length == 0,
            current.textAfter == previous.textAfter,
            current.selectionRange.location > previous.selectionRange.location
        else {
            return nil
        }

        let insertedUTF16Count = current.selectionRange.location
            - previous.selectionRange.location
        guard
            insertedUTF16Count <= visibleSuggestion.utf16.count,
            insertedUTF16Count <= current.textBefore.utf16.count
        else {
            return nil
        }
        let typedRange = NSRange(
            location: current.textBefore.utf16.count - insertedUTF16Count,
            length: insertedUTF16Count
        )
        guard
            let swiftRange = Range(typedRange, in: current.textBefore)
        else {
            return nil
        }
        let typedText = String(current.textBefore[swiftRange])
        guard
            !typedText.isEmpty,
            current.textBefore == suffix(
                previous.textBefore + typedText,
                maximumUTF16Units: 8_000
            )
        else {
            return nil
        }

        guard let consumedSuggestionText = consumedSuggestionText(
            for: typedText,
            in: visibleSuggestion
        ) else { return nil }
        return TypedMatch(
            typedText: typedText,
            consumedSuggestionText: consumedSuggestionText
        )
    }

    private static func consumedSuggestionText(
        for typedText: String,
        in visibleSuggestion: String
    ) -> String? {
        guard !typedText.isEmpty else { return nil }
        return exactPrefix(typedText, in: visibleSuggestion)
    }

    private static func exactPrefix(
        _ typedText: String,
        in suggestion: String
    ) -> String? {
        let prefix = String(suggestion.prefix(typedText.count))
        guard
            prefix.count == typedText.count,
            prefix == typedText
        else {
            return nil
        }
        return prefix
    }

    private static func suffix(
        _ text: String,
        maximumUTF16Units: Int
    ) -> String {
        var reversedCharacters: [Character] = []
        var usedUTF16Units = 0
        for character in text.reversed() {
            let characterUTF16Units = String(character).utf16.count
            guard usedUTF16Units + characterUTF16Units <= maximumUTF16Units else {
                break
            }
            reversedCharacters.append(character)
            usedUTF16Units += characterUTF16Units
        }
        return String(reversedCharacters.reversed())
    }
}
