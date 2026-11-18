import ApplicationServices
import Foundation

enum AccessibilityInsertionAttempt: Equatable, Sendable {
    case inserted
    case unsupported
    case failed
}

protocol NotesInsertionAccessibility: AnyObject {
    func capture() -> ActiveFieldCaptureResult
    func selectedTextInsertionIsSupported(
        expectedSnapshot: ActiveFieldSnapshot
    ) -> Bool
    func insertSelectedText(
        _ text: String,
        expectedSnapshot: ActiveFieldSnapshot,
        isCurrent: () -> Bool
    ) -> AccessibilityInsertionAttempt
}

protocol UnicodeTextPosting: AnyObject {
    var isAvailable: Bool { get }
    func post(_ text: String) -> Bool
}

enum NotesInsertionMethod: Equatable, Sendable {
    case accessibility
    case syntheticUnicode
}

struct PreparedNotesInsertion: Equatable, Sendable {
    let method: NotesInsertionMethod
    let expectedSnapshot: ActiveFieldSnapshot
}

enum NotesInsertionPreparation: Equatable, Sendable {
    case prepared(PreparedNotesInsertion)
    case staleField
    case fieldUnavailable
    case unsupportedSelection
    case safeMethodUnavailable
}

enum NotesInsertionReadiness: Equatable, Sendable {
    case ready(NotesInsertionMethod)
    case staleField
    case fieldUnavailable
    case unsupportedSelection
    case safeMethodUnavailable
}

enum NotesInsertionResult: Equatable, Sendable {
    case inserted(method: NotesInsertionMethod, snapshot: ActiveFieldSnapshot)
    case staleField
    case fieldUnavailable
    case unsupportedSelection
    case safeMethodUnavailable
    case writeFailed
    case verificationFailed
}

final class NotesTextInserter<Accessibility: NotesInsertionAccessibility, Poster: UnicodeTextPosting>: @unchecked Sendable {
    private let accessibility: Accessibility
    private let unicodePoster: Poster
    private let verificationAttempts: Int
    private let verificationDelay: () -> Void

    init(
        accessibility: Accessibility,
        unicodePoster: Poster,
        verificationAttempts: Int = 10,
        verificationDelay: @escaping () -> Void = {}
    ) {
        self.accessibility = accessibility
        self.unicodePoster = unicodePoster
        self.verificationAttempts = max(1, verificationAttempts)
        self.verificationDelay = verificationDelay
    }

    func prepareReplacement(for expectedSnapshot: ActiveFieldSnapshot) -> NotesInsertionPreparation {
        guard TransformPolicy.eligible(expectedSnapshot) else { return .unsupportedSelection }
        return prepareValidated(for: expectedSnapshot)
    }

    func prepare(
        for expectedSnapshot: ActiveFieldSnapshot
    ) -> NotesInsertionPreparation {
        guard
            expectedSnapshot.selectedText.isEmpty,
            expectedSnapshot.selectionRange.length == 0
        else {
            return .unsupportedSelection
        }
        return prepareValidated(for: expectedSnapshot)
    }

    private func prepareValidated(for expectedSnapshot: ActiveFieldSnapshot) -> NotesInsertionPreparation {
        guard case let .captured(current) = accessibility.capture() else {
            return .fieldUnavailable
        }
        guard insertionStateMatches(current, expectedSnapshot) else {
            return .staleField
        }
        if expectedSnapshot.surface.isWebContent {
            return unicodePoster.isAvailable
                ? .prepared(.init(
                    method: .syntheticUnicode,
                    expectedSnapshot: expectedSnapshot
                ))
                : .safeMethodUnavailable
        }
        if accessibility.selectedTextInsertionIsSupported(
            expectedSnapshot: expectedSnapshot
        ) {
            return .prepared(.init(
                method: .accessibility,
                expectedSnapshot: expectedSnapshot
            ))
        }
        if unicodePoster.isAvailable {
            return .prepared(.init(
                method: .syntheticUnicode,
                expectedSnapshot: expectedSnapshot
            ))
        }
        return .safeMethodUnavailable
    }

    func readiness(
        for expectedSnapshot: ActiveFieldSnapshot
    ) -> NotesInsertionReadiness {
        switch prepare(for: expectedSnapshot) {
        case let .prepared(prepared): .ready(prepared.method)
        case .staleField: .staleField
        case .fieldUnavailable: .fieldUnavailable
        case .unsupportedSelection: .unsupportedSelection
        case .safeMethodUnavailable: .safeMethodUnavailable
        }
    }

    func insert(
        _ text: String,
        expectedSnapshot: ActiveFieldSnapshot
    ) -> NotesInsertionResult {
        switch prepare(for: expectedSnapshot) {
        case let .prepared(prepared):
            return insert(text, prepared: prepared)
        case .staleField:
            return .staleField
        case .fieldUnavailable:
            return .fieldUnavailable
        case .unsupportedSelection:
            return .unsupportedSelection
        case .safeMethodUnavailable:
            return .safeMethodUnavailable
        }
    }

    func insert(
        _ text: String,
        prepared: PreparedNotesInsertion,
        isCurrent: () -> Bool = { true }
    ) -> NotesInsertionResult {
        guard !text.isEmpty else { return .writeFailed }
        let method = prepared.method
        let expectedSnapshot = prepared.expectedSnapshot

        guard isCurrent() else { return .staleField }
        switch method {
        case .accessibility:
            guard accessibility.insertSelectedText(
                text,
                expectedSnapshot: expectedSnapshot,
                isCurrent: isCurrent
            ) == .inserted else {
                return .writeFailed
            }
        case .syntheticUnicode:
            guard case let .captured(current) = accessibility.capture() else {
                return .fieldUnavailable
            }
            guard insertionStateMatches(current, expectedSnapshot) else {
                return .staleField
            }
            guard isCurrent() else { return .staleField }
            guard unicodePoster.post(text) else { return .writeFailed }
        }

        for attempt in 0..<verificationAttempts {
            if case let .captured(updated) = accessibility.capture(),
               Self.isExpectedResult(
                   updated,
                   from: expectedSnapshot,
                   insertedText: text
               )
            {
                return .inserted(method: method, snapshot: updated)
            }
            if attempt + 1 < verificationAttempts {
                verificationDelay()
            }
        }
        return .verificationFailed
    }

    private static func isExpectedResult(
        _ current: ActiveFieldSnapshot,
        from expected: ActiveFieldSnapshot,
        insertedText: String
    ) -> Bool {
        current.applicationBundleIdentifier == expected.applicationBundleIdentifier
            && current.elementIdentifier == expected.elementIdentifier
            && current.focusGeneration == expected.focusGeneration
            && Self.canonicalAccessibilityText(current.textBefore)
                == Self.canonicalAccessibilityText(Self.suffix(
                    expected.textBefore + insertedText,
                    maximumUTF16Units: 8_000
                ))
            && current.selectedText.isEmpty
            && Self.canonicalAccessibilityText(current.textAfter)
                == Self.canonicalAccessibilityText(expected.textAfter)
            && current.selectionRange == NSRange(
                location: expected.selectionRange.location + insertedText.utf16.count,
                length: 0
            )
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

    private static func canonicalAccessibilityText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

final class SystemNotesInsertionAccessibility: NotesInsertionAccessibility {
    private let reader: SystemAccessibilityReader
    private let captureHandler: () -> ActiveFieldCaptureResult

    init(
        reader: SystemAccessibilityReader,
        capture: @escaping () -> ActiveFieldCaptureResult
    ) {
        self.reader = reader
        captureHandler = capture
    }

    func capture() -> ActiveFieldCaptureResult {
        captureHandler()
    }

    func selectedTextInsertionIsSupported(
        expectedSnapshot: ActiveFieldSnapshot
    ) -> Bool {
        guard
            let rawElement = currentRawElement(matching: expectedSnapshot)
        else {
            return false
        }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            rawElement,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    func insertSelectedText(
        _ text: String,
        expectedSnapshot: ActiveFieldSnapshot,
        isCurrent: () -> Bool
    ) -> AccessibilityInsertionAttempt {
        guard
            case let .captured(current) = captureHandler(),
            insertionStateMatches(current, expectedSnapshot),
            let rawElement = currentRawElement(matching: expectedSnapshot)
        else {
            return .failed
        }

        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(
                rawElement,
                kAXSelectedTextAttribute as CFString,
                &settable
            ) == .success,
            settable.boolValue
        else {
            return .unsupported
        }

        guard isCurrent() else { return .failed }
        return AXUIElementSetAttributeValue(
            rawElement,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success ? .inserted : .failed
    }

    private func currentRawElement(
        matching snapshot: ActiveFieldSnapshot
    ) -> AXUIElement? {
        guard
            let element = reader.focusedElement(),
            element.identifier == snapshot.elementIdentifier,
            reader.applicationBundleIdentifier(for: element)
                == snapshot.applicationBundleIdentifier
        else {
            return nil
        }
        return element.rawValue
    }

}

private func insertionStateMatches(
    _ current: ActiveFieldSnapshot,
    _ expected: ActiveFieldSnapshot
) -> Bool {
    if expected.selectionRange.length > 0 { return TransformPolicy.matches(current, expected) }
    guard current.applicationBundleIdentifier == expected.applicationBundleIdentifier,
          current.surface == expected.surface,
          current.elementIdentifier == expected.elementIdentifier,
          current.focusGeneration == expected.focusGeneration,
          current.contentSignature == expected.contentSignature,
          current.recentWritingContextSignature == expected.recentWritingContextSignature,
          current.captureSequence >= expected.captureSequence,
          current.geometryQuality != .unavailable,
          expected.geometryQuality != .unavailable,
          current.geometryQuality == expected.geometryQuality,
          current.geometrySource != nil,
          current.geometrySource == expected.geometrySource,
          let currentRect = current.caretBounds,
          let expectedRect = expected.caretBounds
    else { return false }
    return abs(currentRect.midX - expectedRect.midX) <= 2
        && abs(currentRect.midY - expectedRect.midY) <= 2
        && abs(currentRect.height - expectedRect.height) <= 1
}

final class SystemUnicodeTextPoster: UnicodeTextPosting {
    var isAvailable: Bool {
        CGPreflightPostEventAccess()
    }

    func post(_ text: String) -> Bool {
        guard isAvailable else { return false }
        let units = Array(text.utf16)
        guard
            !units.isEmpty,
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
            )
        else {
            return false
        }

        units.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: baseAddress
            )
        }
        SyntheticInsertionEvent.mark(keyDown)
        SyntheticInsertionEvent.mark(keyUp)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
