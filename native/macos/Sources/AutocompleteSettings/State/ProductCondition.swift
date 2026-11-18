import Foundation
import SwiftUI

/// The single most actionable thing to tell the user about the product right now.
enum ProductCondition: Equatable, Sendable {
    case helperUnavailable
    case helperStarting
    case apiKeyMissing
    case signedOut
    case sessionExpired
    case permissionsRequired
    case paused(until: Date?)
    case offline
    case serviceError
    case readyAutomatic
    case readyOnRequest

    enum Tone: Sendable {
        case positive
        case attention
        case problem
        case neutral
    }

    init(status: ProductStatus) {
        if status.helperState == .unavailable {
            self = .helperUnavailable
        } else if status.account.usesApiKey, status.account.state != .signedIn {
            self = .apiKeyMissing
        } else if status.account.state == .signedOut {
            self = .signedOut
        } else if status.account.state == .expired {
            self = .sessionExpired
        } else if !status.permissions.allGranted {
            self = .permissionsRequired
        } else if status.helperState == .starting {
            self = .helperStarting
        } else if !status.enabled {
            self = .paused(until: status.pausedUntilDate)
        } else if status.connection == .offline {
            self = .offline
        } else if status.connection == .error {
            self = .serviceError
        } else if status.automaticSuggestions {
            self = .readyAutomatic
        } else {
            self = .readyOnRequest
        }
    }

    var tone: Tone {
        switch self {
        case .readyAutomatic, .readyOnRequest: .positive
        case .paused, .permissionsRequired, .apiKeyMissing, .signedOut, .sessionExpired, .offline: .attention
        case .helperUnavailable, .serviceError: .problem
        case .helperStarting: .neutral
        }
    }

    var color: Color {
        switch tone {
        case .positive: .green
        case .attention: .orange
        case .problem: .red
        case .neutral: .secondary
        }
    }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .helperUnavailable: l10n[.statusHelperUnavailable]
        case .helperStarting: l10n[.statusHelperStarting]
        case .apiKeyMissing: l10n[.statusApiKeyMissing]
        case .signedOut: l10n[.statusSignedOut]
        case .sessionExpired: l10n[.statusExpired]
        case .permissionsRequired: l10n[.statusPermissions]
        case .paused: l10n[.statusPaused]
        case .offline: l10n[.statusOffline]
        case .serviceError: l10n[.statusServiceError]
        case .readyAutomatic, .readyOnRequest: l10n[.statusReady]
        }
    }

    func detail(_ l10n: L10n, now: Date = Date()) -> String {
        switch self {
        case .helperUnavailable: l10n[.statusHelperUnavailableDetail]
        case .helperStarting: l10n[.statusHelperStartingDetail]
        case .apiKeyMissing: l10n[.statusApiKeyMissingDetail]
        case .signedOut: l10n[.statusSignedOutDetail]
        case .sessionExpired: l10n[.statusExpiredDetail]
        case .permissionsRequired: l10n[.statusPermissionsDetail]
        case .paused(let until):
            if let until {
                l10n.format(.statusPausedUntilDetail, l10n.returnMoment(until, now: now))
            } else {
                l10n[.statusPausedDetail]
            }
        case .offline: l10n[.statusOfflineDetail]
        case .serviceError: l10n[.statusServiceErrorDetail]
        case .readyAutomatic: l10n[.statusReadyAutomaticDetail]
        case .readyOnRequest: l10n[.statusReadyOnRequestDetail]
        }
    }
}
