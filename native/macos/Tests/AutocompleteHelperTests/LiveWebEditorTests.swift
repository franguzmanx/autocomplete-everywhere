import AppKit
import ApplicationServices
import XCTest
@testable import AutocompleteHelper

/// Read-only, opt-in acceptance check for an empty LinkedIn comment editor.
/// Does not type, submit, or record page/editor contents.
final class LiveWebEditorTests: XCTestCase {
    func testEmptyCommentExposesCaret() throws {
        let (reader, _) = try emptyComment()
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)
        guard case let .captured(snapshot) = capture.capture() else { return XCTFail("Capture must succeed") }
        XCTAssertNotNil(snapshot.caretBounds, "An empty reply must expose a usable insertion anchor")
        XCTAssertNotEqual(snapshot.geometryQuality, .unavailable)
    }

    func testEmptyCommentDoesNotBecomeAuthoredPlaceholderText() throws {
        let (_, context) = try emptyComment()
        // An independent acceptance gate: resolving geometry does not prove
        // that generated placeholder content is distinguished from a draft.
        XCTAssertTrue(context.textBefore.isEmpty && context.textAfter.isEmpty && context.selectedText.isEmpty,
                      "Generated placeholder text is not an authored draft")
    }

    private func emptyComment() throws -> (SystemAccessibilityReader, WebTextContext) {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_EMPTY_COMMENT_QA"] == "1" else {
            throw XCTSkip("Focus an empty LinkedIn comment in Chrome")
        }
        let chrome = try XCTUnwrap(NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.google.Chrome"
        ).first)
        let root = AXUIElementCreateApplication(chrome.processIdentifier)
        let window = try XCTUnwrap(attribute("AXFocusedWindow", from: root))
        XCTAssertEqual(CFGetTypeID(window), AXUIElementGetTypeID())
        guard CFGetTypeID(window) == AXUIElementGetTypeID(),
              (attribute("AXTitle", from: window as! AXUIElement) as? String)?.contains("LinkedIn") == true
        else { throw XCTSkip("Chrome must show LinkedIn") }
        let reader = SystemAccessibilityReader(focusedApplicationProvider: { root })
        reader.prepareFrontmostWebContent()
        let field = try XCTUnwrap(reader.focusedElement())
        let raw = try XCTUnwrap(field.rawValue)
        guard attribute("AXDescription", from: raw) as? String == "Text editor for creating comment",
              ["", "Add a comment...", "Add a comment...\n"].contains(reader.stringValue(for: field) ?? "missing")
        else { throw XCTSkip("Focus an empty comment; no existing draft may be read") }
        let prepared = reader.prepareWebContent(for: field)
        let context = try XCTUnwrap(reader.webTextContext(for: prepared))
        print("Empty comment: before=\(context.textBefore.utf16.count), after=\(context.textAfter.utf16.count), selection=\(context.selectionLocation), candidates=\(context.caretCandidates), frame=\(String(describing: context.frame)), line=\(String(describing: context.lineBounds)), hasStyle=\(context.caretTextStyle != nil)")
        return (reader, context)
    }

    private func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }
}
