import Foundation

/// Safe, human-readable failure reported by the parent for a request.
struct RequestFailure: Error, Sendable, Equatable {
    let message: String
}

enum IncomingMessage: Sendable, Equatable {
    case state(ProductStatus, entries: [LibraryEntry], transforms: TransformSettings, context: ContextState = .empty)
    case result(id: String, outcome: Result<JSONValue, RequestFailure>)
    case show

    private struct Envelope: Decodable {
        let type: String
    }

    private struct StateEnvelope: Decodable {
        let status: ProductStatus
        let entries: [LibraryEntry]
        let transforms: TransformSettings
        let context: ContextState
    }

    private struct ResultEnvelope: Decodable {
        let id: String
        let ok: Bool
        let value: JSONValue?
        let error: String?
    }

    enum DecodeError: Error, Equatable {
        case notUTF8
        case unknownType(String)
    }

    static func decode(line: String) throws -> IncomingMessage {
        guard let data = line.data(using: .utf8) else { throw DecodeError.notUTF8 }
        return try decode(data: data)
    }

    static func decode(data: Data) throws -> IncomingMessage {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: data)
        switch envelope.type {
        case "state":
            let state = try decoder.decode(StateEnvelope.self, from: data)
            return .state(state.status, entries: state.entries, transforms: state.transforms, context: state.context)
        case "result":
            let result = try decoder.decode(ResultEnvelope.self, from: data)
            if result.ok {
                return .result(id: result.id, outcome: .success(result.value ?? .null))
            }
            let message = result.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .result(id: result.id, outcome: .failure(RequestFailure(message: message)))
        case "show":
            return .show
        default:
            throw DecodeError.unknownType(envelope.type)
        }
    }
}
