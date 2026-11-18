import Foundation

struct SuggestionRequestMessage: Encodable {
    let protocolVersion = 5
    let type = "suggestion_request"
    let identity: Identity
    let payload: Payload

    struct Identity: Codable, Equatable, Sendable {
        let requestId: String
        let focusSequence: UInt64
        let contentSignature: String
        let timestampMs: Int64

        init(
            requestId: String,
            focusSequence: UInt64,
            contentSignature: String,
            timestampMs: Int64
        ) {
            self.requestId = requestId
            self.focusSequence = focusSequence
            self.contentSignature = contentSignature
            self.timestampMs = timestampMs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let requestId = try container.decode(String.self, forKey: .requestId)
            let focusSequence = try container.decode(UInt64.self, forKey: .focusSequence)
            let contentSignature = try container.decode(String.self, forKey: .contentSignature)
            let timestampMs = try container.decode(Int64.self, forKey: .timestampMs)
            guard
                UUID(uuidString: requestId) != nil,
                contentSignature.range(
                    of: #"^[a-f0-9]{64}$"#,
                    options: .regularExpression
                ) != nil,
                timestampMs >= 0
            else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid identity")
                )
            }
            self.init(
                requestId: requestId,
                focusSequence: focusSequence,
                contentSignature: contentSignature,
                timestampMs: timestampMs
            )
        }
    }

    struct Payload: Encodable {
        let appId: String
        let surface: String
        let textBefore: String
        let textAfter: String
        let selectedText: String
        let explicit: Bool
        let alternativeTo: [String]?
        let artifacts: [Artifact]
        let fieldContext: ActiveFieldContext

        struct Artifact: Encodable, Equatable, Sendable {
            let id: String
            let kind: String
            let text: String
            let capturedAtMs: Int64
            let sourceSurface: String?

            init(id: String, kind: String, text: String, capturedAtMs: Int64, sourceSurface: String? = nil) {
                self.id = id
                self.kind = kind
                self.text = text
                self.capturedAtMs = capturedAtMs
                self.sourceSurface = sourceSurface
            }
        }
    }

    init(
        snapshot: ActiveFieldSnapshot,
        requestID: UUID = UUID(),
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
        artifacts: [Payload.Artifact] = [],
        explicit: Bool = false,
        alternativeTo: [String]? = nil
    ) {
        identity = Identity(
            requestId: requestID.uuidString,
            focusSequence: snapshot.focusGeneration,
            contentSignature: snapshot.contentSignature,
            timestampMs: timestampMs
        )
        payload = Payload(
            appId: snapshot.applicationBundleIdentifier,
            surface: snapshot.surface.protocolValue,
            textBefore: snapshot.textBefore,
            textAfter: snapshot.textAfter,
            selectedText: snapshot.selectedText,
            explicit: explicit,
            alternativeTo: explicit ? alternativeTo : nil,
            artifacts: artifacts,
            fieldContext: snapshot.fieldContext
        )
    }
}

enum CancelRequestReason: String, Encodable, Equatable, Sendable {
    case contentChanged = "content_changed"
    case focusChanged = "focus_changed"
    case dismissed
    case shutdown
}

struct CancelRequestMessage: Encodable, Equatable, Sendable {
    let protocolVersion = 5
    let type = "cancel_request"
    let identity: SuggestionRequestMessage.Identity
    let payload: Payload

    struct Payload: Encodable, Equatable, Sendable {
        let reason: CancelRequestReason
    }
}
