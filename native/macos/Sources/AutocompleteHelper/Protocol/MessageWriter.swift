import Foundation

struct HelloMessage: Encodable {
    let protocolVersion = 5
    let type = "hello"
    let payload = Payload()

    struct Payload: Encodable {
        let platform = "macos"
        let helperVersion = "0.0.1"
        let capabilities = [
            "lifecycle",
            "permission_state",
            "notes_capture",
            "ghost_text",
            "notes_insertion",
        ]
    }
}

final class MessageWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let encoder = JSONEncoder()

    func writeContextScreenPermission(granted: Bool) throws {
        struct State: Encodable {
            let protocolVersion = 5
            let type = "context_screen_permission"
            let payload: [String: Bool]
        }
        try write(State(payload: ["granted": granted]))
    }

    func writeContextObservation(_ message: ContextObservationMessage) throws { try write(message) }

    func writeHello() throws {
        try write(HelloMessage())
    }

    func writeApplicationState(_ payload: ApplicationStateMessage.Payload) throws {
        try write(ApplicationStateMessage(payload: payload))
    }

    func writePermissionState(_ state: NativePermissionState) throws {
        try write(PermissionStateMessage(state: state))
    }

    func writeTransformRequest(_ message: TransformRequestMessage) throws { try write(message) }

    func writeSuggestionRequest(_ message: SuggestionRequestMessage) throws {
        try write(message)
    }

    func writeUserActivity() throws {
        try write(UserActivityMessage())
    }

    /// Dedicated private pipe message. Never pass this payload to diagnostics
    /// or timeline tracing; only its content-free interaction is observable.
    func writeCorrectionObserved(_ message: CorrectionObservedMessage) throws {
        try write(message)
    }

    func writeCancelRequest(_ message: CancelRequestMessage) throws {
        try write(message)
    }

    func writeInteraction(
        identity: SuggestionRequestMessage.Identity,
        outcome: InteractionOutcome,
        acceptedCharacters: Int
    ) throws {
        try write(
            InteractionMessage(
                identity: identity,
                payload: .init(
                    outcome: outcome,
                    acceptedCharacters: acceptedCharacters
                )
            )
        )
    }

    private func write<T: Encodable>(_ message: T) throws {
        var data = try encoder.encode(message)
        data.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardOutput.write(data)
    }

    func writeDiagnostic(_ code: String) {
        guard let data = "helper:\(code)\n".data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardError.write(data)
    }
}

enum InteractionOutcome: String, Encodable {
    case shown
    case acceptedFull = "accepted_full"
    case acceptedPartial = "accepted_partial"
    case dismissed
    case editedAfterAcceptance = "edited_after_acceptance"
    case removedAfterAcceptance = "removed_after_acceptance"
    case observationUnavailable = "observation_unavailable"
    case typedThrough = "typed_through"
    case stale
    case failed
}

struct InteractionMessage: Encodable {
    let protocolVersion = 5
    let type = "interaction"
    let identity: SuggestionRequestMessage.Identity
    let payload: Payload

    struct Payload: Encodable {
        let outcome: InteractionOutcome
        let acceptedCharacters: Int
    }
}

struct CorrectionObservedMessage: Encodable, Equatable, Sendable {
    let protocolVersion = 5
    let type = "correction_observed"
    let identity: SuggestionRequestMessage.Identity
    let payload: Payload

    struct Payload: Encodable, Equatable, Sendable {
        let appId: String
        let sessionId: String
        let before: String
        let after: String
        let observedAtMs: Int64
    }
}

struct UserActivityMessage: Encodable {
    let protocolVersion = 5
    let type = "user_activity"
    let payload = NullPayload()

    struct NullPayload: Encodable {
        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}
