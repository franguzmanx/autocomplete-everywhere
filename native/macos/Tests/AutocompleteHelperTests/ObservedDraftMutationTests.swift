import XCTest
@testable import AutocompleteHelper

final class ObservedDraftMutationTests: XCTestCase {
    func testInsertionAndReplacementAreValueMutations() {
        XCTAssertTrue(ObservedDraftMutation.changed(from: snapshot("Hello"), to: snapshot("Hello world")))
        XCTAssertTrue(ObservedDraftMutation.changed(from: snapshot("Hello"), to: snapshot("Hallo")))
        XCTAssertTrue(ObservedDraftMutation.changed(from: snapshot(""), to: snapshot("Dictated text")))
    }
    func testSelectionCaretMetadataAndDifferentFieldAreNotValueMutations() {
        let original = snapshot("Hello", after: " world")
        XCTAssertFalse(ObservedDraftMutation.changed(from: original, to: snapshot("Hello ", after: "world")))
        XCTAssertFalse(ObservedDraftMutation.changed(from: original, to: snapshot("Hello", selected: " world")))
        XCTAssertFalse(ObservedDraftMutation.changed(from: original, to: snapshot("Hello", after: " world", label: "Other label")))
        XCTAssertFalse(ObservedDraftMutation.changed(from: original, to: snapshot("Unrelated draft", field: "other")))
    }
    func testBoundedWindowMovementIsNotAnEditButAppendAtLongFieldEndIs() {
        let text = String(repeating: "a", count: 9000)
        let old = snapshot(String(text.prefix(8000)), after: String(text.suffix(1000)))
        let moved = snapshot(String(text.suffix(8000)), location: 9000)
        XCTAssertFalse(ObservedDraftMutation.changed(from: old, to: moved))
        XCTAssertTrue(ObservedDraftMutation.changed(from: moved, to: snapshot(String(repeating: "a", count: 7999) + "b", location: 9001)))
    }
    private func snapshot(_ before: String, selected: String = "", after: String = "", field: String = "field", location: Int? = nil, label: String? = nil) -> ActiveFieldSnapshot {
        .init(applicationBundleIdentifier: "app", elementIdentifier: field, focusGeneration: 1, textBefore: before, selectedText: selected, textAfter: after, selectionRange: NSRange(location: location ?? before.utf16.count, length: selected.utf16.count), caretBounds: nil, geometryQuality: .unavailable, fieldContext: .init(shape: .multiline, label: label))
    }
}
