import XCTest
@testable import AutocompleteHelper

final class RecentWritingContextTests: XCTestCase {
    @MainActor
    func testNonASCIIPhysicalEditKeepsPreviouslyAuthoredWritingAfterCapture() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("")), timestampMs: 0)
        context.noteUserEdit(timestampMs: 1)
        context.observe(.captured(snapshot("Mañana en Espa")), timestampMs: 2)
        let monitor = KeyboardMonitor(sessionProvider: { .inactive }, actionHandler: { _ in false }, onUserEdit: { context.noteUserEdit(timestampMs: 500) })
        let classifier = KeyboardInputCommitmentClassifier { .init(isASCIICapable: true, isNonComposingKeyboardLayout: true) }
        _ = monitor.process(.init(keyCode: 41, textInput: classifier.classify("ñ")), phase: .keyDown)
        XCTAssertEqual(context.artifacts(for: snapshot(""), timestampMs: 501).map(\.text), ["Mañana en Espa"], "A key alone never creates captured writing")
        context.observe(.captured(snapshot("Mañana en Españ")), timestampMs: 502)
        XCTAssertEqual(context.artifacts(for: snapshot(""), timestampMs: 503).map(\.text), ["Mañana en Españ"])
    }

    func testReusedComposerDoesNotRecallWritingFromChangedConversation() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        var first = snapshot("Project A ships Tuesday.")
        first.fieldContext = ActiveFieldContext(shape: .multiline, sources: [
            FieldSource(id: "reused-message", containerId: "reused-chat", relation: .sharedContainer, text: "When does project A ship?")
        ])
        context.recordAcceptance(text: first.textBefore, snapshot: first, timestampMs: 0)
        XCTAssertEqual(context.artifacts(for: first, timestampMs: 1).count, 1)
        var second = first
        second.fieldContext = ActiveFieldContext(shape: .multiline, sources: [
            FieldSource(id: "reused-message", containerId: "reused-chat", relation: .sharedContainer, text: "Can you review this recipe?")
        ])
        // Same AX identities and draft: source evidence alone changes.
        XCTAssertTrue(context.artifacts(for: second, timestampMs: 2).isEmpty)
        context.observe(.captured(second), timestampMs: 3)
        XCTAssertTrue(context.artifacts(for: second, timestampMs: 4).isEmpty)
        context.observe(.captured(first), timestampMs: 5)
        XCTAssertTrue(context.artifacts(for: first, timestampMs: 6).isEmpty, "A context switch must discard old recall, not resurrect it")
    }

    func testExcludingAnAppPurgesPriorContextAndRejectsItsLateCaptures() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        let source = snapshot("Private source")
        context.recordAcceptance(text: "Private source", snapshot: source, timestampMs: 0)
        XCTAssertFalse(context.artifacts(for: snapshot(""), timestampMs: 1).isEmpty)
        context.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false, excludedApplications: [source.applicationBundleIdentifier]))
        context.observe(.captured(source), timestampMs: 2)
        context.noteUserEdit(timestampMs: 3)
        context.recordAcceptance(text: "Private source", snapshot: source, timestampMs: 4)
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 5).isEmpty)
    }

    func testReturningToSourceKeepsTheCorrectedFactWhole() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("Preexisting introduction. ")), timestampMs: 0)
        context.noteUserEdit(timestampMs: 1)
        context.observe(.captured(snapshot("Preexisting introduction. Jacaranda entrega el martes 17.")), timestampMs: 2)
        let id = context.artifacts(for: snapshot(""), timestampMs: 3).first?.id
        context.observe(.captured(snapshot("Hola, sobre Jacaranda", field: "email")), timestampMs: 4)
        context.observe(.captured(snapshot("Preexisting introduction. Jacaranda entrega el martes 17.")), timestampMs: 5)
        context.noteUserEdit(timestampMs: 6)
        context.observe(.captured(snapshot("Preexisting introduction. Jacaranda entrega el martes 18.")), timestampMs: 7)
        let corrected = context.artifacts(for: snapshot(""), timestampMs: 8)
        XCTAssertEqual(corrected.map(\.text), ["Jacaranda entrega el martes 18."])
        XCTAssertEqual(corrected.first?.id, id)
    }

    func testReturningToExternallyChangedSourceInvalidatesOldFact() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("")), timestampMs: 0)
        context.noteUserEdit(timestampMs: 1)
        context.observe(.captured(snapshot("Entrega el 17.")), timestampMs: 2)
        context.observe(.captured(snapshot("", field: "email")), timestampMs: 3)
        context.observe(.captured(snapshot("Changed while unobserved")), timestampMs: 4)
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 5).isEmpty)
    }

    func testReturningToSourceDoesNotRenewItsExpiry() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.recordAcceptance(text: "Entrega el 17.", snapshot: snapshot("Entrega el 17."), timestampMs: 0)
        context.observe(.captured(snapshot("", field: "email")), timestampMs: 10)
        context.observe(.captured(snapshot("Entrega el 17.")), timestampMs: 299_990)
        context.noteUserEdit(timestampMs: 300_001)
        context.observe(.captured(snapshot("Entrega el 17. Otro asunto.")), timestampMs: 300_002)
        XCTAssertEqual(context.artifacts(for: snapshot(""), timestampMs: 300_003).map(\.text), [" Otro asunto."])
    }

    func testReturningToLongSourceRestoresOnlyBoundedAuthoredSuffix() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        let source = String(repeating: "界", count: 2_100) + " 🚀 Entrega el 17."
        context.recordAcceptance(text: source, snapshot: snapshot("Preexisting. " + source), timestampMs: 0)
        context.observe(.captured(snapshot("", field: "email")), timestampMs: 1)
        context.observe(.captured(snapshot("Preexisting. " + source)), timestampMs: 2)
        context.noteUserEdit(timestampMs: 3)
        context.observe(.captured(snapshot("Preexisting. " + source.replacingOccurrences(of: "17", with: "18"))), timestampMs: 4)
        let corrected = context.artifacts(for: snapshot(""), timestampMs: 5)
        XCTAssertEqual(corrected.count, 1)
        XCTAssertTrue(corrected[0].text.hasSuffix("🚀 Entrega el 18."))
        XCTAssertLessThanOrEqual(corrected[0].text.utf16.count, 2_000)
        XCTAssertFalse(corrected[0].text.contains("Preexisting"))
    }

    func testBriefReadFailurePreservesAuthorshipButLongGapDoesNot() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("")), timestampMs: 0)
        context.noteUserEdit(timestampMs: 10)
        context.observe(.captured(snapshot("Entrega")), timestampMs: 20)
        context.noteUserEdit(timestampMs: 30)
        context.observe(.skipped(.markerReadFailed), timestampMs: 40)
        context.observe(.captured(snapshot("Entrega el viernes.")), timestampMs: 50)
        XCTAssertEqual(context.artifacts(for: snapshot(""), timestampMs: 60).map(\.text), ["Entrega el viernes."])

        context.observe(.skipped(.markerReadFailed), timestampMs: 100)
        context.noteUserEdit(timestampMs: 1_500)
        context.observe(.captured(snapshot("Unattributed replacement")), timestampMs: 1_510)
        XCTAssertFalse(context.artifacts(for: snapshot(""), timestampMs: 1_520).contains { $0.text == "Unattributed replacement" })
    }

    func testOnlyRetainsObservedEditsAndBindsThemToTheirField() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("Existing document. ")), timestampMs: 0)
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 0).isEmpty)
        context.noteUserEdit(timestampMs: 10)
        // A host may publish the unchanged value before publishing the edit.
        context.observe(.captured(snapshot("Existing document. ")), timestampMs: 12)
        context.observe(.captured(snapshot("Existing document. Entrega el viernes.")), timestampMs: 20)
        let artifacts = context.artifacts(for: snapshot(""), timestampMs: 30)
        XCTAssertEqual(artifacts.map(\.text), ["Entrega el viernes."])
        XCTAssertEqual(artifacts.first?.sourceSurface, "text_editor")
        XCTAssertTrue(context.artifacts(for: snapshot("", field: "unrelated"), timestampMs: 30).isEmpty)
    }

    func testUpdatesCorrectionsAndRemovesDeletedWriting() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("")), timestampMs: 0)
        context.noteUserEdit(timestampMs: 1)
        context.observe(.captured(snapshot("Entrega el jueves.")), timestampMs: 2)
        let originalID = context.artifacts(for: snapshot(""), timestampMs: 3).first?.id
        context.noteUserEdit(timestampMs: 4)
        context.observe(.captured(snapshot("Entrega el viernes.")), timestampMs: 5)
        let corrected = context.artifacts(for: snapshot(""), timestampMs: 6)
        XCTAssertEqual(corrected.map(\.text), ["Entrega el viernes."])
        XCTAssertEqual(corrected.first?.id, originalID)
        context.noteUserEdit(timestampMs: 7)
        context.observe(.captured(snapshot("")), timestampMs: 8)
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 9).isEmpty)
    }

    func testUnobservedHostChangesCannotBecomeAuthoredMemory() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("Old content")), timestampMs: 0)
        context.observe(.captured(snapshot("Programmatic replacement")), timestampMs: 10)
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 20).isEmpty)
        context.noteUserEdit(timestampMs: 30)
        context.observe(.captured(snapshot("New focus must not count as typing", field: "other")), timestampMs: 40)
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 50).isEmpty)
    }

    func testSecureSkipBreaksEditAttributionAndDisableClearsHistory() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("")), timestampMs: 0)
        context.noteUserEdit(timestampMs: 1)
        context.observe(.captured(snapshot("Safe note")), timestampMs: 2)
        context.observe(.skipped(.secureField), timestampMs: 3)
        context.noteUserEdit(timestampMs: 4)
        context.observe(.captured(snapshot("Never attribute this new field", field: "new")), timestampMs: 5)
        XCTAssertEqual(context.artifacts(for: snapshot(""), timestampMs: 6).map(\.text), ["Safe note"])
        context.updateConfiguration(.disabled)
        context.updateConfiguration(.enabled)
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 7).isEmpty)
    }

    func testVerifiedAcceptancePreservesMultilineUnicodeAndExpires() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        let text = "\n明日の計画 🚀\nمرحبا"
        context.recordAcceptance(text: text, snapshot: snapshot("Old" + text), timestampMs: 100)
        let artifacts = context.artifacts(for: snapshot(""), timestampMs: 101)
        XCTAssertEqual(artifacts.map(\.text), [text])
        XCTAssertEqual(artifacts.first?.kind, "accepted_completion")
        XCTAssertTrue(context.artifacts(for: snapshot(""), timestampMs: 300_101).isEmpty)
    }

    func testTypingAfterExpiryDoesNotResurrectOldWriting() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        context.observe(.captured(snapshot("")), timestampMs: 0)
        context.noteUserEdit(timestampMs: 1)
        context.observe(.captured(snapshot("Expired detail. ")), timestampMs: 2)
        context.noteUserEdit(timestampMs: 300_003)
        context.observe(.captured(snapshot("Expired detail. New idea.")), timestampMs: 300_004)
        XCTAssertEqual(context.artifacts(for: snapshot(""), timestampMs: 300_005).map(\.text), ["New idea."])
    }

    func testDeduplicatesAndBoundsTheWholeRecentWindow() {
        let context = RecentWritingContext()
        context.updateConfiguration(.enabled)
        for i in 0..<5 {
            let text = String(repeating: "界", count: 1_500) + "\(i)"
            context.recordAcceptance(text: text, snapshot: snapshot(text, field: "\(i)"), timestampMs: Int64(i))
        }
        let destination = snapshot("", field: "4")
        let artifacts = context.artifacts(for: destination, timestampMs: 10)
        XCTAssertLessThanOrEqual(artifacts.count, 3)
        XCTAssertLessThanOrEqual(artifacts.reduce(0) { $0 + $1.text.utf16.count }, 4_000)
        XCTAssertTrue(artifacts.first?.text.hasSuffix("4") == true)
        let duplicate = artifacts[0].text
        context.recordAcceptance(text: duplicate, snapshot: snapshot(duplicate, field: "duplicate"), timestampMs: 11)
        XCTAssertEqual(context.artifacts(for: snapshot("", field: "duplicate"), timestampMs: 12).filter { $0.text == duplicate }.count, 1)
    }

    private func snapshot(_ text: String, field: String = "source") -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: "test.application",
            elementIdentifier: field,
            focusGeneration: 1,
            textBefore: text,
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            caretBounds: nil,
            geometryQuality: .unavailable
        )
    }
}
