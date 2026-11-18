import Foundation

struct CaptureConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let clipboardContextEnabled: Bool
    var learningEnabled: Bool = false
    var contextEnabled: Bool = false
    var contextImagesEnabled: Bool = false
    var excludedApplications: Set<String> = []
    var automaticSuggestions: Bool = true
    var quietPeriodMs: Int = 300
    var ghostAlpha: Double = 0.30
    var acceptShortcut: InteractionKeyBinding = .acceptDefault
    var dismissShortcut: InteractionKeyBinding = .dismissDefault

    func allows(_ appId: String) -> Bool { isEnabled && !excludedApplications.contains(appId) }

    static let disabled = CaptureConfiguration(
        isEnabled: false,
        clipboardContextEnabled: false
    )
    static let enabled = CaptureConfiguration(
        isEnabled: true,
        clipboardContextEnabled: false
    )
}

enum HelperCommand: Equatable, Sendable {
    case transformConfigure([TransformShortcut])
    case transformResult(TransformResultCommand)
    case configure(CaptureConfiguration)
    case contextRequestScreenPermission
    case contextInvalidate([String])
    case requestSuggestion
    case suggestionFinal(SuggestionFinalCommand)
    case requestFailed(RequestFailedCommand)
}

enum SuggestionFinalResult: Equatable, Sendable {
    case text(String)
    case silence(String)
}

struct SuggestionFinalCommand: Equatable, Sendable {
    let identity: SuggestionRequestMessage.Identity
    let result: SuggestionFinalResult
}

enum RequestFailureCode: String, Decodable, Equatable, Sendable {
    case unauthorized
    case network
    case timeout
    case server
}

struct RequestFailedCommand: Equatable, Sendable {
    let identity: SuggestionRequestMessage.Identity
    let code: RequestFailureCode
    let retryable: Bool
}

struct HelperCommandDecoder {
    private struct ContextInvalidatePayload: Decodable { let requestIds: [String] }
    private struct Header: Decodable {
        let protocolVersion: Int
        let type: String
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let protocolVersion: Int
        let type: String
        let identity: SuggestionRequestMessage.Identity?
        let payload: Payload
    }

    private struct TransformConfigurationPayload: Decodable { let shortcuts: [TransformShortcut] }
    private struct TransformResultPayload: Decodable { let text: String?; let error: String? }

    private struct ConfigurePayload: Decodable {
        let enabled: Bool
        let excludedApplications: [String]
        let automaticSuggestions: Bool
        let quietPeriodMs: Int
        let ghostAlpha: Double
        let acceptShortcut: InteractionKeyBinding
        let dismissShortcut: InteractionKeyBinding
        let clipboardContextEnabled: Bool
        let learningEnabled: Bool
        let contextEnabled: Bool
        let contextImagesEnabled: Bool
    }

    private struct RequestPayload: Decodable {
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            guard container.decodeNil() else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected null request payload")
            }
        }
    }

    private struct FinalPayload: Decodable {
        let text: String?
        let silenceReason: String?
    }

    private struct FailurePayload: Decodable {
        let code: RequestFailureCode
        let retryable: Bool
    }

    func decode(_ line: String) -> HelperCommand? {
        guard
            let data = line.data(using: .utf8),
            let header = try? JSONDecoder().decode(Header.self, from: data),
            header.protocolVersion == 5
        else {
            return nil
        }

        switch header.type {
        case "transform_configure":
            guard let envelope = try? JSONDecoder().decode(Envelope<TransformConfigurationPayload>.self, from: data),
                  envelope.identity == nil,
                  envelope.payload.shortcuts.count <= 9,
                  Set(envelope.payload.shortcuts.map { $0.id }).count == envelope.payload.shortcuts.count,
                  Set(envelope.payload.shortcuts.map { $0.key }).count == envelope.payload.shortcuts.count,
                  envelope.payload.shortcuts.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.name.isEmpty && $0.name.utf16.count <= 60 && (1...9).contains($0.key) })
            else { return nil }
            return .transformConfigure(envelope.payload.shortcuts)
        case "transform_result":
            guard let envelope = try? JSONDecoder().decode(Envelope<TransformResultPayload>.self, from: data),
                  let identity = envelope.identity else { return nil }
            switch (envelope.payload.text, envelope.payload.error) {
            case let (.some(text), .none) where TransformPolicy.validOutput(text, singleLine: false):
                return .transformResult(.init(identity: identity, text: text))
            case let (.none, .some(error)) where ["unavailable", "cancelled"].contains(error):
                return .transformResult(.init(identity: identity, text: nil))
            default: return nil
            }
        case "context_request_screen_permission":
            guard let envelope = try? JSONDecoder().decode(Envelope<RequestPayload>.self, from: data), envelope.identity == nil else { return nil }
            return .contextRequestScreenPermission
        case "context_invalidate":
            guard let envelope = try? JSONDecoder().decode(Envelope<ContextInvalidatePayload>.self, from: data),
                envelope.identity == nil, envelope.payload.requestIds.count <= 256,
                envelope.payload.requestIds.allSatisfy({ UUID(uuidString: $0) != nil }) else { return nil }
            return .contextInvalidate(envelope.payload.requestIds)
        case "configure":
            return decodeConfiguration(data)
        case "request_suggestion":
            guard let envelope = try? JSONDecoder().decode(Envelope<RequestPayload>.self, from: data),
                  envelope.identity == nil else { return nil }
            return .requestSuggestion
        case "suggestion_final":
            return decodeFinal(data)
        case "request_failed":
            return decodeFailure(data)
        default:
            return nil
        }
    }

    private func decodeConfiguration(_ data: Data) -> HelperCommand? {
        guard
            let envelope = try? JSONDecoder().decode(
                Envelope<ConfigurePayload>.self,
                from: data
            ),
            envelope.type == "configure",
            envelope.identity == nil
        else {
            return nil
        }
        guard [0, 150, 300, 700].contains(envelope.payload.quietPeriodMs),
              envelope.payload.acceptShortcut.isValid,
              envelope.payload.dismissShortcut.isValid,
              envelope.payload.acceptShortcut != envelope.payload.dismissShortcut,
              [0.30, 0.45].contains(envelope.payload.ghostAlpha),
              envelope.payload.excludedApplications.count <= 500,
              envelope.payload.excludedApplications.allSatisfy(Self.validAppId) else { return nil }
        return .configure(.init(
            isEnabled: envelope.payload.enabled,
            clipboardContextEnabled: envelope.payload.enabled && envelope.payload.clipboardContextEnabled,
            learningEnabled: envelope.payload.enabled && envelope.payload.learningEnabled,
            contextEnabled: envelope.payload.enabled && envelope.payload.contextEnabled,
            contextImagesEnabled: envelope.payload.enabled && envelope.payload.contextEnabled && envelope.payload.contextImagesEnabled,
            excludedApplications: Set(envelope.payload.excludedApplications),
            automaticSuggestions: envelope.payload.automaticSuggestions,
            quietPeriodMs: envelope.payload.quietPeriodMs,
            ghostAlpha: envelope.payload.ghostAlpha,
            acceptShortcut: envelope.payload.acceptShortcut,
            dismissShortcut: envelope.payload.dismissShortcut
        ))
    }

    private static func validAppId(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    private func decodeFinal(_ data: Data) -> HelperCommand? {
        guard
            let envelope = try? JSONDecoder().decode(
                Envelope<FinalPayload>.self,
                from: data
            ),
            envelope.type == "suggestion_final",
            let identity = envelope.identity
        else {
            return nil
        }
        let result: SuggestionFinalResult
        switch (envelope.payload.text, envelope.payload.silenceReason) {
        case let (.some(text), .none)
            where !text.isEmpty && text.utf16.count <= 12_000:
            result = .text(text)
        case let (.none, .some(reason))
            where ["not_useful", "not_grounded", "unsafe", "timeout", "cancelled"]
                .contains(reason):
            result = .silence(reason)
        default:
            return nil
        }
        return .suggestionFinal(
            SuggestionFinalCommand(identity: identity, result: result)
        )
    }

    private func decodeFailure(_ data: Data) -> HelperCommand? {
        guard
            let envelope = try? JSONDecoder().decode(
                Envelope<FailurePayload>.self,
                from: data
            ),
            envelope.type == "request_failed",
            let identity = envelope.identity
        else {
            return nil
        }
        return .requestFailed(
            RequestFailedCommand(
                identity: identity,
                code: envelope.payload.code,
                retryable: envelope.payload.retryable
            )
        )
    }
}
