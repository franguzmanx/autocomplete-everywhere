import Foundation
import XCTest
@testable import AutocompleteHelper

final class TransformTests: XCTestCase {
    func testRewriteTracksTheSelectedFieldNotChangingSourceMessageText() {
        func snapshot(source: String, container: String = "chat", selection: String = "Original") -> ActiveFieldSnapshot {
            ActiveFieldSnapshot(applicationBundleIdentifier: "synthetic.chat", surface: .native,
                elementIdentifier: "composer", focusGeneration: 1, textBefore: "", selectedText: selection, textAfter: "",
                selectionRange: NSRange(location: 0, length: selection.utf16.count), caretBounds: nil, geometryQuality: .unavailable,
                fieldContext: .init(shape: .multiline, sources: [
                    .init(id: "message", containerId: container, relation: .sharedContainer, text: source)
                ]))
        }
        let original = snapshot(source: "Earlier source text")
        XCTAssertTrue(TransformPolicy.matches(snapshot(source: "Updated source text"), original))
        XCTAssertFalse(TransformPolicy.matches(snapshot(source: "Updated source text", container: "different-chat"), original))
        XCTAssertFalse(TransformPolicy.matches(snapshot(source: "Earlier source text", selection: "Changed"), original))
    }

    func testOnlyExactOptionNumberTriggersAndRepeatDoesNotStartMoreWork() {
        let shortcut = TransformShortcut(id: UUID().uuidString, name: "Polish", key: 1)
        XCTAssertEqual(TransformPolicy.shortcut(for: KeyboardInput(keyCode: 18, modifiers: [.option]), shortcuts: [shortcut]), shortcut)
        XCTAssertNil(TransformPolicy.shortcut(for: KeyboardInput(keyCode: 18, modifiers: [.option, .command]), shortcuts: [shortcut]))
        XCTAssertNil(TransformPolicy.shortcut(for: KeyboardInput(keyCode: 18, modifiers: [.option], isRepeat: true), shortcuts: [shortcut]))
    }

    func testDecoderRejectsIncompleteResultAndDuplicateShortcuts() {
        let decoder = HelperCommandDecoder()
        let id = UUID().uuidString
        XCTAssertNil(decoder.decode("{\"protocolVersion\":5,\"type\":\"transform_configure\",\"payload\":{\"shortcuts\":[{\"id\":\"\(id)\",\"name\":\"A\",\"key\":1},{\"id\":\"\(id)\",\"name\":\"B\",\"key\":2}]}}"))
        let identity = "\"identity\":{\"requestId\":\"\(id)\",\"focusSequence\":1,\"contentSignature\":\"\(String(repeating: "a", count: 64))\",\"timestampMs\":1}"
        XCTAssertNil(decoder.decode("{\"protocolVersion\":5,\"type\":\"transform_result\",\(identity),\"payload\":{\"text\":\"\"}}"))
        XCTAssertNotNil(decoder.decode("{\"protocolVersion\":5,\"type\":\"transform_result\",\(identity),\"payload\":{\"text\":\"Hello\"}}"))
    }

    func testRejectsControlCharactersAndMultilineInSingleLineFields() {
        XCTAssertFalse(TransformPolicy.validOutput("a\nb", singleLine: true))
        XCTAssertFalse(TransformPolicy.validOutput("\0bad", singleLine: false))
        XCTAssertFalse(TransformPolicy.validOutput(String(repeating: "a", count: 8001), singleLine: false))
        XCTAssertTrue(TransformPolicy.validOutput("Hola 👋\n¿Cómo estás?", singleLine: false))
    }
}
