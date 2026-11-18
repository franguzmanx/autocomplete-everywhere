import Foundation

enum PauseDuration: String, Sendable, CaseIterable, Identifiable {
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case tomorrow

    var id: String { rawValue }
}

enum MacPermissionKind: String, Sendable {
    case accessibility
    case inputMonitoring = "input_monitoring"
}

/// Every request the native UI can send. The wire name and payload are defined here and nowhere else.
enum SettingsAction: Sendable, Equatable {
    case contextRequestScreenPermission
    case contextSetEnabled(Bool)
    case contextSetVisualEnabled(Bool)
    case contextDelete(String)
    case contextAddReference(String)
    case contextClear
    case contextPin(String)
    case contextConnect(String)
    case contextDisconnect(String)
    case contextUnpin(String)
    case contextSearch(String)
    case contextHistoryPrevious
    case contextHistoryMore
    case contextRefresh
    case ready
    case saveTransforms(TransformSettings)
    case previewTransform(TransformInput)
    case getDefaultTransforms
    case resume
    case beginSignIn
    case signOut
    case openManageAccount
    case restartHelper
    case requestExerciseSuggestion
    case pause(PauseDuration)
    case saveWriting(WritingPreferences)
    case setUiLanguage(AppLanguage)
    case setShortcut(SuggestionKeyBinding?)
    case setShortcutRecording(Bool)
    case setInteractionShortcut(kind: SuggestionShortcutKind, shortcut: SuggestionKeyBinding)
    case setAppEnabled(appId: String, enabled: Bool)
    case openMacPermissionSettings(MacPermissionKind)
    case librarySave(LibraryInput)
    case libraryDelete(id: String, revision: Int)
    case libraryImport(LibraryInput)
    case setExerciseActive(Bool)

    var name: String {
        switch self {
        case .saveTransforms: "saveTransforms"
        case .previewTransform: "previewTransform"
        case .getDefaultTransforms: "getDefaultTransforms"
        case .contextRequestScreenPermission: "context_request_screen_permission"
        case .contextSetVisualEnabled: "context_set_visual_enabled"
        case .contextSetEnabled: "context_set_enabled"
        case .contextDelete: "context_delete"
        case .contextAddReference: "context_add_reference"
        case .contextClear: "context_clear"
        case .contextPin: "context_pin"
        case .contextConnect: "context_connect"
        case .contextDisconnect: "context_disconnect"
        case .contextUnpin: "context_unpin"
        case .contextSearch: "context_search"
        case .contextHistoryPrevious: "context_history_previous"
        case .contextHistoryMore: "context_history_more"
        case .contextRefresh: "context_refresh"
        case .ready: "ready"
        case .resume: "resume"
        case .beginSignIn: "beginSignIn"
        case .signOut: "signOut"
        case .openManageAccount: "openManageAccount"
        case .restartHelper: "restartHelper"
        case .requestExerciseSuggestion: "requestExerciseSuggestion"
        case .pause: "pause"
        case .saveWriting: "saveWriting"
        case .setUiLanguage: "setUiLanguage"
        case .setShortcut: "setShortcut"
        case .setShortcutRecording: "setShortcutRecording"
        case .setInteractionShortcut: "setInteractionShortcut"
        case .setAppEnabled: "setAppEnabled"
        case .openMacPermissionSettings: "openMacPermissionSettings"
        case .librarySave: "librarySave"
        case .libraryDelete: "libraryDelete"
        case .libraryImport: "libraryImport"
        case .setExerciseActive: "setExerciseActive"
        }
    }

    fileprivate func encodePayload(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .contextSetEnabled(let enabled), .contextSetVisualEnabled(let enabled): try container.encode(["enabled": enabled])
        case .contextDelete(let id), .contextPin(let id), .contextUnpin(let id): try container.encode(["id": id])
        case .contextSearch(let query): try container.encode(["query": query])
        case .contextAddReference(let text): try container.encode(["text": text])
        case .contextConnect(let provider), .contextDisconnect(let provider): try container.encode(["provider": provider])
        case .contextHistoryPrevious, .contextHistoryMore, .contextRequestScreenPermission, .contextClear, .contextRefresh: try container.encodeNil()
        case .getDefaultTransforms, .ready, .resume, .beginSignIn, .signOut, .openManageAccount, .restartHelper,
             .requestExerciseSuggestion:
            try container.encodeNil()
        case .pause(let duration):
            try container.encode(duration.rawValue)
        case .setExerciseActive(let value), .setShortcutRecording(let value):
            try container.encode(value)
        case .setUiLanguage(let language):
            try container.encode(language.rawValue)
        case .setInteractionShortcut(let kind, let shortcut):
            try container.encode(InteractionShortcutPayload(action: kind, shortcut: shortcut))
        case .setShortcut(let shortcut):
            try container.encode(shortcut)
        case .saveTransforms(let settings):
            try container.encode(settings)
        case .previewTransform(let input):
            try container.encode(input)
        case .saveWriting(let writing):
            try container.encode(writing)
        case .setAppEnabled(let appId, let enabled):
            try container.encode(AppEnabledPayload(appId: appId, enabled: enabled))
        case .openMacPermissionSettings(let kind):
            try container.encode(kind.rawValue)
        case .librarySave(let input):
            try container.encode(input)
        case .libraryDelete(let id, let revision):
            try container.encode(LibraryDeletePayload(id: id, revision: revision))
        case .libraryImport(let input):
            try container.encode(input.withoutText)
        }
    }
}

private struct InteractionShortcutPayload: Encodable {
    let action: SuggestionShortcutKind
    let shortcut: SuggestionKeyBinding
}

private struct AppEnabledPayload: Encodable {
    let appId: String
    let enabled: Bool
}

private struct LibraryDeletePayload: Encodable {
    let id: String
    let revision: Int
}

/// One outgoing JSON line: `{ "id": "UUID", "action": "name", "payload": value }`.
struct RequestEnvelope: Encodable, Sendable {
    let id: String
    let action: SettingsAction

    private enum CodingKeys: String, CodingKey {
        case id
        case action
        case payload
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(action.name, forKey: .action)
        try action.encodePayload(to: container.superEncoder(forKey: .payload))
    }
}
