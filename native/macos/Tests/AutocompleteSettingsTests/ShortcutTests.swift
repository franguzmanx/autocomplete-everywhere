import XCTest
import KeyboardShortcuts
@testable import AutocompleteSettings

@MainActor
final class ShortcutTests: XCTestCase {
    func testLocalInteractionRecorderAcceptsNavigationKeysButNotOrdinaryTyping() {
        for key in [KeyboardShortcuts.Key.tab, .escape, .return, .rightArrow] {
            XCTAssertNotNil(SuggestionKeyBinding(.init(key), kind: .accept))
            XCTAssertNil(SuggestionKeyBinding(.init(key), kind: .request))
        }
        XCTAssertNil(SuggestionKeyBinding(.init(.a), kind: .accept))
        XCTAssertNil(SuggestionKeyBinding(.init(.space), kind: .dismiss))
    }
    func testDefaultAndCustomChordRoundTrip() throws {
        let original = try XCTUnwrap(SuggestionKeyBinding(.init(.space, modifiers: [.command, .shift])))
        XCTAssertEqual(original.accelerator, "Command+Shift+Space")
        XCTAssertEqual(original.native, .init(.space, modifiers: [.command, .shift]))
        let custom = try XCTUnwrap(SuggestionKeyBinding(.init(.k, modifiers: [.control, .option])))
        XCTAssertEqual(custom.accelerator, "Control+Alt+K")
        XCTAssertEqual(custom.native, .init(.k, modifiers: [.control, .option]))
    }
    func testFixedOptionActionsCannotBeRecordedButExtraModifiersCan() {
        for key in [KeyboardShortcuts.Key.tab, .upArrow, .downArrow, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine] {
            for kind in SuggestionShortcutKind.allCases {
                let reserved = SuggestionKeyBinding(.init(key, modifiers: [.option]), kind: kind)
                XCTAssertTrue(reserved?.isReserved == true)
                XCTAssertFalse(SuggestionKeyBinding(.init(key, modifiers: [.option, .shift]), kind: kind)?.isReserved ?? true)
            }
        }
    }
    func testTypingKeysAreNotGlobalShortcuts() {
        XCTAssertNil(SuggestionKeyBinding(.init(.k)))
        XCTAssertNil(SuggestionKeyBinding(.init(.k, modifiers: [.shift])))
    }
    func testHelpUsesTheActualShortcutAndSupportsNoShortcut() {
        XCTAssertTrue(L10n(language: .en, shortcut: "⌃⌥K")[.modeOnRequestFooter].contains("⌃⌥K"))
        XCTAssertFalse(L10n(language: .en, shortcut: nil)[.modeOnRequestFooter].contains("press"))
    }
    func testInteractionHelpAndWirePayloadUseTheChosenKeys() throws {
        let custom = try XCTUnwrap(SuggestionKeyBinding(.init(.return, modifiers: [.command])))
        let help = L10n(language: .en, acceptShortcut: custom.display, dismissShortcut: "⌃D")
        XCTAssertTrue(help[.exerciseKeys].contains(custom.display))
        XCTAssertTrue(help[.exerciseKeys].contains("⌃D"))
        XCTAssertFalse(help[.exerciseKeys].contains("Tab"))
        let encoded = try JSONEncoder().encode(RequestEnvelope(id: "test", action: .setInteractionShortcut(kind: .accept, shortcut: custom)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "setInteractionShortcut")
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["action"] as? String, "accept")
        XCTAssertEqual((payload["shortcut"] as? [String: Any])?["keyCode"] as? Int, 36)
        XCTAssertEqual(SuggestionShortcutKind.accept.defaultBinding?.keyCode, 48)
        XCTAssertEqual(SuggestionShortcutKind.dismiss.defaultBinding?.keyCode, 53)
    }
}
