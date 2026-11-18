import Foundation
import XCTest
@testable import AutocompleteHelper

final class SuggestionRequestMessageTests: XCTestCase {
    func testBuildsTheBoundedNotesProtocolMessageWithoutGeometryOrElementIdentity() throws {
        let snapshot = ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Notes",
            elementIdentifier: "internal-element-id",
            focusGeneration: 7,
            textBefore: "Hello ",
            selectedText: "world",
            textAfter: "!",
            selectionRange: NSRange(location: 6, length: 5),
            caretBounds: CGRect(x: 10, y: 20, width: 1, height: 18),
            geometryQuality: .exact
        )
        let requestID = UUID(uuidString: "DA2F74CE-C1DA-4E2E-85C7-B6D3C4069B63")!
        let message = SuggestionRequestMessage(
            snapshot: snapshot,
            requestID: requestID,
            timestampMs: 1_788_000_000_000
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any]
        )
        let identity = try XCTUnwrap(object["identity"] as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertEqual(object["protocolVersion"] as? Int, 5)
        XCTAssertEqual(object["type"] as? String, "suggestion_request")
        XCTAssertEqual(identity["requestId"] as? String, requestID.uuidString)
        XCTAssertEqual(identity["focusSequence"] as? Int, 7)
        XCTAssertEqual(identity["timestampMs"] as? Int64, 1_788_000_000_000)
        XCTAssertTrue(
            (identity["contentSignature"] as? String)?.range(
                of: #"^[a-f0-9]{64}$"#,
                options: .regularExpression
            ) != nil
        )
        XCTAssertEqual(payload["appId"] as? String, "com.apple.Notes")
        XCTAssertEqual(payload["surface"] as? String, "text_editor")
        XCTAssertEqual(payload["textBefore"] as? String, "Hello ")
        XCTAssertEqual(payload["selectedText"] as? String, "world")
        XCTAssertEqual(payload["textAfter"] as? String, "!")
        XCTAssertEqual(payload["explicit"] as? Bool, false)
        XCTAssertNil(payload["alternativeTo"])
        let alternative = SuggestionRequestMessage(snapshot: snapshot, explicit: true, alternativeTo: ["Another version"])
        let alternativeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(alternative)) as? [String: Any])
        let alternativePayload = try XCTUnwrap(alternativeJSON["payload"] as? [String: Any])
        XCTAssertEqual(alternativePayload["alternativeTo"] as? [String], ["Another version"])
        XCTAssertEqual(alternativePayload["explicit"] as? Bool, true)
        XCTAssertEqual((payload["artifacts"] as? [Any])?.count, 0)
        let fieldContext = try XCTUnwrap(payload["fieldContext"] as? [String: Any])
        XCTAssertEqual(fieldContext["shape"] as? String, "multiline")
        XCTAssertNil(payload["elementIdentifier"])
        XCTAssertNil(payload["caretBounds"])
    }

    func testHelloAdvertisesNotesCaptureCapability() {
        XCTAssertTrue(HelloMessage().payload.capabilities.contains("notes_capture"))
        XCTAssertTrue(HelloMessage().payload.capabilities.contains("ghost_text"))
        XCTAssertTrue(HelloMessage().payload.capabilities.contains("notes_insertion"))
    }

    func testClassifiesTextEditAsATextEditorSurface() throws {
        let snapshot = ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.TextEdit",
            elementIdentifier: "document",
            focusGeneration: 1,
            textBefore: "Draft",
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: 5, length: 0),
            caretBounds: CGRect(x: 10, y: 20, width: 1, height: 18),
            geometryQuality: .exact
        )

        let data = try JSONEncoder().encode(
            SuggestionRequestMessage(snapshot: snapshot)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertEqual(payload["surface"] as? String, "text_editor")
    }

    func testClassifiesSafariAsAWebTextareaSurface() throws {
        let snapshot = ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            elementIdentifier: "textarea",
            focusGeneration: 1,
            textBefore: "Draft",
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: 5, length: 0),
            caretBounds: CGRect(x: 10, y: 20, width: 1, height: 18),
            geometryQuality: .exact
        )

        let data = try JSONEncoder().encode(
            SuggestionRequestMessage(snapshot: snapshot)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertEqual(payload["surface"] as? String, "web_textarea")
    }

    func testProtocolSurfaceDependsOnHostFamilyNotOnAnAllowlist() {
        XCTAssertEqual(
            WritingSurface.web.protocolValue,
            "web_textarea"
        )
        XCTAssertEqual(
            WritingSurface.web.protocolValue,
            "web_textarea"
        )
        XCTAssertEqual(
            WritingSurface.native.protocolValue,
            "text_editor"
        )
        XCTAssertEqual(
            WritingSurface.native.protocolValue,
            "text_editor"
        )
    }

    func testInteractionOutcomesMatchTheSharedProtocol() {
        XCTAssertEqual(InteractionOutcome.acceptedPartial.rawValue, "accepted_partial")
        XCTAssertEqual(InteractionOutcome.typedThrough.rawValue, "typed_through")
    }
}
