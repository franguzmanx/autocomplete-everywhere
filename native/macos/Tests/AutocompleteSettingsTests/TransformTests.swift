import Foundation
import XCTest
@testable import AutocompleteSettings

final class TransformTests: XCTestCase {
    func testValidationRejectsDuplicateShortcutsAndEmptyInstructions() {
        let first = WritingTransform(id: UUID().uuidString, name: "Polish", shortcut: 1,
                                     rules: [.clarity], prompt: "", examples: [])
        var second = first
        second.id = UUID().uuidString
        XCTAssertFalse(TransformSettings(enabled: true, transforms: [first, second]).isValid)
        second.shortcut = 2
        XCTAssertTrue(TransformSettings(enabled: true, transforms: [first, second]).isValid)
        second.rules = []
        XCTAssertFalse(second.isValid)
        second.prompt = "Preserve meaning."
        XCTAssertTrue(second.isValid)
        second.examples = [""]
        XCTAssertFalse(second.isValid)
    }

    func testTransformActionsPreserveStrictPayloadAndPreviewText() throws {
        let transform = WritingTransform(id: UUID().uuidString, name: "Polish", shortcut: 1,
                                         rules: [.clarity, .tone], prompt: "", examples: ["Example"])
        let settings = TransformSettings(enabled: true, transforms: [transform])
        let data = try JSONEncoder().encode(RequestEnvelope(id: "save", action: .saveTransforms(settings)))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(value["action"] as? String, "saveTransforms")
        let payload = try XCTUnwrap(value["payload"] as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["enabled", "transforms"])
        let preview = TransformInput(text: "A draft", transform: transform, singleLine: false)
        let previewData = try JSONEncoder().encode(RequestEnvelope(id: "preview", action: .previewTransform(preview)))
        let previewValue = try XCTUnwrap(JSONSerialization.jsonObject(with: previewData) as? [String: Any])
        let previewPayload = try XCTUnwrap(previewValue["payload"] as? [String: Any])
        XCTAssertEqual(Set(previewPayload.keys), ["text", "transform", "singleLine"])
        XCTAssertEqual(previewPayload["text"] as? String, "A draft")
        XCTAssertEqual(previewPayload["singleLine"] as? Bool, false)
    }
}
