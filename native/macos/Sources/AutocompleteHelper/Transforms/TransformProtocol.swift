import Foundation
import ShortcutRules

struct TransformShortcut: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let key: Int
}

struct TransformResultCommand: Equatable, Sendable {
    let identity: SuggestionRequestMessage.Identity
    let text: String?
}

struct TransformRequestMessage: Encodable {
    let protocolVersion = 5
    let type = "transform_request"
    let identity: SuggestionRequestMessage.Identity
    let payload: Payload
    struct Payload: Encodable {
        let appId: String
        let transformId: String
        let text: String
        let singleLine: Bool
    }
}

enum TransformPolicy {
    static func shortcut(for input: KeyboardInput, shortcuts: [TransformShortcut]) -> TransformShortcut? {
        guard input.modifiers == [.option], !input.isRepeat else { return nil }
        guard let key = ShortcutReservation.transformNumber(keyCode: Int(input.keyCode)) else { return nil }
        return shortcuts.first { $0.key == key }
    }

    static func eligible(_ snapshot: ActiveFieldSnapshot) -> Bool {
        let text = snapshot.selectedText
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.utf16.count <= 2_000
            && text.utf16.count == snapshot.selectionRange.length
    }

    static func matches(_ current: ActiveFieldSnapshot, _ expected: ActiveFieldSnapshot) -> Bool {
        eligible(current) && eligible(expected)
            && current.applicationBundleIdentifier == expected.applicationBundleIdentifier
            && current.elementIdentifier == expected.elementIdentifier
            && current.surface == expected.surface
            && current.focusGeneration == expected.focusGeneration
            && current.contentSignature == expected.contentSignature
            && current.selectionRange == expected.selectionRange
            && current.selectedText == expected.selectedText
            && current.textBefore == expected.textBefore
            && current.textAfter == expected.textAfter
            && current.captureSequence >= expected.captureSequence
    }

    static func validOutput(_ text: String, singleLine: Bool) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf16.count <= 8_000 else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            if singleLine && [10, 13, 0x2028, 0x2029].contains(code) { return false }
            return code >= 32 && code != 127 || [9, 10, 13].contains(code)
        }
    }
}
