import Foundation
import XCTest
@testable import AutocompleteHelper

final class LearningMessageTests: XCTestCase {
    func testActivityCarriesOnlyProtocolTypeAndNullPayload() throws {
        let data = try JSONEncoder().encode(UserActivityMessage())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["protocolVersion", "type", "payload"])
        XCTAssertEqual(json["protocolVersion"] as? Int, 5)
        XCTAssertEqual(json["type"] as? String, "user_activity")
        XCTAssertTrue(json["payload"] is NSNull)
    }

    func testCorrectionUsesPrivateMessageWhileInteractionIsContentFree() throws {
        let identity = SuggestionRequestMessage.Identity(requestId: UUID().uuidString, focusSequence: 1, contentSignature: String(repeating: "a", count: 64), timestampMs: 0)
        let message = CorrectionObservedMessage(identity: identity, payload: .init(appId: "app", sessionId: UUID().uuidString, before: "PRIVATE BEFORE", after: "PRIVATE AFTER", observedAtMs: 30_000))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "correction_observed")
        XCTAssertEqual((json["payload"] as? [String: Any])?["before"] as? String, "PRIVATE BEFORE")
        let interaction = InteractionMessage(identity: identity, payload: .init(outcome: .editedAfterAcceptance, acceptedCharacters: 0))
        let encoded = String(decoding: try JSONEncoder().encode(interaction), as: UTF8.self)
        XCTAssertTrue(encoded.contains("edited_after_acceptance"))
        XCTAssertFalse(encoded.contains("PRIVATE"))
        XCTAssertFalse(encoded.contains("before"))
        XCTAssertFalse(encoded.contains("after\":"))
    }
}
