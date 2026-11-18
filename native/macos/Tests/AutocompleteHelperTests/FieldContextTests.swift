import Foundation
import XCTest
@testable import AutocompleteHelper

final class FieldContextTests: XCTestCase {
    func testKeepsConversationFragmentsBeyondSixLabelsWithinTotalBudget() {
        let fragments = (0..<24).map { FieldSource(id: "node-\($0)", containerId: "thread", relation: .sharedContainer, text: "Fragment \($0)") }
        XCTAssertEqual(FieldSource.strongestUnique(fragments).count, 24)
        let long = (0..<24).map { FieldSource(id: "node-\($0)", containerId: "thread", relation: .sharedContainer, text: String(repeating: "😀", count: 1000)) }
        XCTAssertEqual(FieldSource.strongestUnique(long).reduce(0) { $0 + $1.text.utf16.count }, 12_000)
    }

    func testSourceBodyRefreshPreservesInsertionIdentityButSourceMembershipDoesNot() throws {
        func snapshot(_ source: String, id: String = "node") -> ActiveFieldSnapshot {
            ActiveFieldSnapshot(applicationBundleIdentifier: "test", elementIdentifier: "field", focusGeneration: 1, textBefore: "Reply", selectedText: "", textAfter: "", selectionRange: NSRange(location: 5, length: 0), caretBounds: nil, geometryQuality: .unavailable, fieldContext: ActiveFieldContext(shape: .multiline, sources: [.init(id: id, containerId: "parent", relation: .sharedContainer, text: source)]))
        }
        XCTAssertEqual(snapshot("One").contentSignature, snapshot("Two").contentSignature)
        XCTAssertNotEqual(snapshot("One").contentSignature, snapshot("One", id: "different-target").contentSignature)
        let source = FieldSource(id: "node", containerId: "parent", relation: .sharedContainer, text: String(repeating: "😀", count: 2000))
        XCTAssertLessThanOrEqual(source.text.utf16.count, 2000)
        XCTAssertTrue(SuggestionRequestMessage(snapshot: snapshot("One"), explicit: true).payload.explicit)
        let data = try JSONEncoder().encode(ActiveFieldContext(shape: .multiline))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["sources"] as? [String], [])
    }

    func testSharedSourcesReachModelForRelevanceJudgmentInEmptyField() {
        let context = ActiveFieldContext(shape: .multiline, sources: [
            .init(id: "one", containerId: "group", relation: .sharedContainer, text: "Post one"),
            .init(id: "two", containerId: "group", relation: .sharedContainer, text: "Post two")
        ])
        XCTAssertTrue(SuggestionRequestEligibility.shouldRequest(textBefore: "", selectedText: "", textAfter: "", fieldContext: context))
    }

    func testSourcesDeduplicateLabelAlsoExposedAsStaticSiblingUsingStrongestRelation() {
        let context = ActiveFieldContext(shape: .multiline, sources: [
            .init(id: "label", containerId: "group", relation: .sharedContainer, text: "Recipient"),
            .init(id: "label", containerId: "field", relation: .describedBy, text: "Recipient"),
            .init(id: "label", containerId: "field", relation: .labelledBy, text: "Recipient")
        ])
        XCTAssertEqual(context.sources.count, 1)
        XCTAssertEqual(context.sources.first?.relation, .labelledBy)
        XCTAssertEqual(context.sources.first?.containerId, "field")
    }

    func testEveryGenerationMetadataChangeRevisesInsertionIdentity() {
        func snapshot(_ context: ActiveFieldContext) -> ActiveFieldSnapshot {
            ActiveFieldSnapshot(applicationBundleIdentifier: "mail", elementIdentifier: "body", focusGeneration: 1, textBefore: "Draft", selectedText: "", textAfter: "", selectionRange: NSRange(location: 5, length: 0), caretBounds: nil, geometryQuality: .unavailable, fieldContext: context)
        }
        let original = snapshot(.init(shape: .multiline, label: "Body", placeholder: "Reply"))
        for context in [
            ActiveFieldContext(shape: .singleLine, label: "Body", placeholder: "Reply"),
            ActiveFieldContext(shape: .multiline, label: "Subject", placeholder: "Reply"),
            ActiveFieldContext(shape: .multiline, label: "Body", placeholder: "New message"),
        ] {
            let changed = snapshot(context)
            XCTAssertEqual(original.textBefore, changed.textBefore)
            XCTAssertNotEqual(original.contentSignature, changed.contentSignature)
            XCTAssertEqual(changed.requestSignature, changed.contentSignature)
        }
    }

    func testPreservesRawSemanticMetadataWithoutClassifyingItsLanguage() {
        let context = ActiveFieldContext(
            shape: .singleLine,
            label: "Objet",
            placeholder: "Écrivez un objet"
        )

        XCTAssertEqual(context.shape, .singleLine)
        XCTAssertEqual(context.label, "Objet")
        XCTAssertEqual(context.placeholder, "Écrivez un objet")
    }

    func testEmptyFieldRequiresRealNearbyTextBeforeRequesting() {
        let noSource = ActiveFieldContext(
            shape: .singleLine,
            placeholder: "Subject"
        )
        let withSource = ActiveFieldContext(
            shape: .singleLine,
            placeholder: "Subject",
            relatedFields: [
                RelatedFieldContext(
                    shape: .multiline,
                    label: "Message Body",
                    placeholder: nil,
                    text: "Hola Dana, te comparto la propuesta."
                )
            ]
        )

        XCTAssertFalse(
            SuggestionRequestEligibility.shouldRequest(
                textBefore: "",
                selectedText: "",
                textAfter: "",
                fieldContext: noSource
            )
        )
        XCTAssertTrue(
            SuggestionRequestEligibility.shouldRequest(
                textBefore: "",
                selectedText: "",
                textAfter: "",
                fieldContext: withSource
            )
        )
    }
}
