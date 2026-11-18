import Foundation

// Frozen wire model. Mirrors `ProductStatus` in docs/product-intelligence/native-settings-contract.md.
// Timestamps are milliseconds since 1970 as sent by the Electron main process.

enum PermissionState: String, Codable, Sendable, Equatable {
    case unknown
    case required
    case granted
}

struct PermissionStatus: Codable, Sendable, Equatable {
    var accessibility: PermissionState
    var inputMonitoring: PermissionState

    var allGranted: Bool {
        accessibility == .granted && inputMonitoring == .granted
    }
}

enum AccountState: String, Codable, Sendable, Equatable {
    case signedOut = "signed_out"
    case signedIn = "signed_in"
    case expired
}

struct AccountIdentity: Codable, Sendable, Equatable {
    var subject: String
    var name: String
    var email: String
}

/// How the product is authorized. Absent for a hosted account sign-in.
enum AccountKind: String, Codable, Sendable, Equatable {
    case apiKey = "api_key"
}

struct AccountStatus: Codable, Sendable, Equatable {
    var state: AccountState
    var identity: AccountIdentity?
    var kind: AccountKind? = nil
    /// Model that answers suggestions.
    var model: String? = nil

    /// The credential is the user's own AI Gateway key, entered in this window.
    var usesApiKey: Bool { kind == .apiKey }
}

enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case en
    case es

    var id: String { rawValue }
}

enum SuggestionTiming: String, Codable, Sendable, CaseIterable, Identifiable {
    case instant
    case quick
    case balanced
    case deliberate

    var id: String { rawValue }
}

enum SuggestionVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    case subtle
    case clear

    var id: String { rawValue }
}

struct ObservedApplication: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
}

enum HelperState: String, Codable, Sendable, Equatable {
    case starting
    case running
    case unavailable
}

enum ConnectionState: String, Codable, Sendable, Equatable {
    case ready
    case offline
    case error
}

enum ExerciseState: String, Codable, Sendable, Equatable {
    case idle
    case waiting
    case shown
    case accepted
    case dismissed
    case unavailable
}

struct ProductStatus: Codable, Sendable, Equatable {
    var activity: SuggestionActivitySummary
    var permissions: PermissionStatus
    var account: AccountStatus
    var enabled: Bool
    var pausedUntil: Double?
    var automaticSuggestions: Bool
    var uiLanguage: AppLanguage
    var timing: SuggestionTiming
    var visibility: SuggestionVisibility
    var apps: [String: Bool]
    var applications: [ObservedApplication]
    var currentApplication: String?
    var helperState: HelperState
    var shortcut: SuggestionKeyBinding?
    var acceptShortcut: SuggestionKeyBinding
    var dismissShortcut: SuggestionKeyBinding
    var shortcutRegistered: Bool
    var libraryAvailable: Bool
    var connection: ConnectionState
    var exercise: ExerciseState
    var personalization: PersonalizationSnapshot

    var pausedUntilDate: Date? {
        pausedUntil.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var isSignedIn: Bool {
        account.state == .signedIn
    }

    /// Library editing requires a live session and a usable store.
    var canEditLibrary: Bool {
        isSignedIn && libraryAvailable
    }

    func isApplicationEnabled(_ id: String) -> Bool {
        apps[id] ?? true
    }
}
