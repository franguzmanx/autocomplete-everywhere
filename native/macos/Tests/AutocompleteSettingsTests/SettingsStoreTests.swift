import Foundation
import XCTest
@testable import AutocompleteSettings

final class FakeTransport: SettingsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sentData: [Data] = []
    private(set) var readingStarted = false
    var failSend = false

    func send(_ envelope: RequestEnvelope) throws {
        if failSend { throw TransportClosed.closed }
        let data = try JSONEncoder().encode(envelope)
        lock.lock()
        sentData.append(data)
        lock.unlock()
    }

    func startReading(
        onLine: @escaping @Sendable (String) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        readingStarted = true
        lock.unlock()
    }

    var sent: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return sentData.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    var sentActions: [String] {
        sent.compactMap { $0["action"] as? String }
    }
}

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var transport = FakeTransport()
    private var counter = 0

    private func makeStore() -> SettingsStore {
        transport = FakeTransport()
        let ids = IdentifierSequence()
        return SettingsStore(transport: transport, makeIdentifier: { ids.next() })
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(condition(), "Condition never became true")
    }

    private func lastRequestID() throws -> String {
        try XCTUnwrap(transport.sent.last?["id"] as? String)
    }

    func testTransformDraftSurvivesStateRefreshAndSaveWaitsForAcknowledgement() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.editTransforms { $0.enabled = true }
        XCTAssertTrue(store.hasUnsavedTransformChanges)
        XCTAssertTrue(store.hasUnsavedChanges)
        store.receive(line: Fixtures.stateLine)
        XCTAssertEqual(store.transforms?.enabled, true, "Activity updates must not discard edits")
        store.saveTransforms()
        await waitUntil { self.transport.sentActions == ["saveTransforms"] }
        XCTAssertTrue(store.transformsSaving)
        XCTAssertFalse(store.transformsSaved)
        XCTAssertTrue(store.hasUnsavedTransformChanges)
        let saved = TransformSettings(enabled: true, transforms: [])
        let result = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(saved))
        store.apply(.result(id: try lastRequestID(), outcome: .success(result)))
        await waitUntil { store.transformsSaved }
        XCTAssertFalse(store.hasUnsavedTransformChanges)
        XCTAssertEqual(store.transforms, saved)
    }

    func testDefaultTransformsAreARevertibleDraft() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.restoreTransformDefaults()
        await waitUntil { self.transport.sentActions == ["getDefaultTransforms"] }
        let defaults = TransformSettings(enabled: false, transforms: [
            WritingTransform(id: UUID().uuidString, name: "Polish", shortcut: 1, rules: [.clarity], prompt: "", examples: [])
        ])
        let result = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(defaults))
        store.apply(.result(id: try lastRequestID(), outcome: .success(result)))
        await waitUntil { !store.transformsSaving }
        XCTAssertTrue(store.hasUnsavedTransformChanges)
        XCTAssertEqual(store.transforms, defaults)
        XCTAssertEqual(transport.sentActions, ["getDefaultTransforms"], "Defaults must not save automatically")
        store.discardTransformChanges()
        XCTAssertEqual(store.transforms, Fixtures.transforms)
        XCTAssertFalse(store.hasUnsavedTransformChanges)
    }

    func testStartSendsReadyAndAppliesState() async throws {
        let store = makeStore()
        store.start()
        XCTAssertTrue(transport.readingStarted)
        await waitUntil { self.transport.sentActions == ["ready"] }
        XCTAssertNil(store.status)
        XCTAssertEqual(store.language, .en)

        store.receive(line: Fixtures.stateLine)
        XCTAssertEqual(store.status?.uiLanguage, .es)
        XCTAssertEqual(store.language, .es)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.condition, .permissionsRequired)
    }

    func testFailedReadyWithoutStateShowsRetryableFailure() async throws {
        let store = makeStore()
        store.requestInitialState()
        await waitUntil { self.transport.sentActions.count == 1 }
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .failure(RequestFailure(message: "Main is busy"))))
        await waitUntil { store.initialLoadFailure != nil }
        XCTAssertEqual(store.initialLoadFailure, "Main is busy")
        XCTAssertTrue(store.inFlight.isEmpty)
    }

    func testResultRoutesToRequestAndClearsBusy() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        let task = Task { try await store.request(.resume) }
        await waitUntil { self.transport.sentActions == ["resume"] }
        XCTAssertTrue(store.isBusy(.resume))
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .success(.null)))
        let value = try await task.value
        XCTAssertTrue(value.isNull)
        XCTAssertFalse(store.isBusy(.resume))
    }

    func testFailedResultPresentsAlertAndClearsBusy() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.perform(.restartHelper)
        await waitUntil { self.transport.sentActions == ["restartHelper"] }
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .failure(RequestFailure(message: "Helper is locked"))))
        await waitUntil { store.alert != nil }
        XCTAssertEqual(store.alert?.message, "Helper is locked")
        XCTAssertEqual(store.alert?.title, "No se pudo completar el cambio")
        XCTAssertFalse(store.isBusy(.restartHelper))
    }

    func testEmptyErrorMessageFallsBackToLocalizedGeneric() async throws {
        let store = makeStore()
        store.perform(.resume)
        await waitUntil { self.transport.sentActions == ["resume"] }
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .failure(RequestFailure(message: "  "))))
        await waitUntil { store.alert != nil }
        XCTAssertEqual(store.alert?.message, "The request failed.")
    }

    func testWritingEditsDoNotApplyBeforeSave() async {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.setTiming(.quick)
        store.setVisibility(.clear)
        store.setAutomatic(false)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(transport.sentActions.isEmpty, "Writing edits must wait for Save")
        XCTAssertEqual(store.effectiveTiming, .deliberate, "Runtime stays on saved settings")
    }

    func testWritingSaveKeepsDraftOnFailureAndConfirmsOnlyAfterAcknowledgement() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.setTiming(.quick)
        store.setVisibility(.clear)
        store.setAutomatic(false)
        XCTAssertTrue(store.hasUnsavedChanges)
        store.navigate(.section(.applications))
        store.receive(line: Fixtures.stateLine)
        XCTAssertEqual(store.writing.timing, .quick, "Navigation and status updates preserve edits")
        XCTAssertFalse(store.writingSaved)

        store.saveWriting()
        store.saveWriting()
        await waitUntil { self.transport.sentActions.count == 1 }
        XCTAssertEqual(transport.sentActions, ["saveWriting"])
        let payload = try XCTUnwrap(transport.sent.last?["payload"] as? [String: Any])
        XCTAssertEqual(payload["automaticSuggestions"] as? Bool, false)
        XCTAssertEqual(payload["timing"] as? String, "quick")
        XCTAssertEqual(payload["visibility"] as? String, "clear")
        XCTAssertTrue(store.writingSaving)
        XCTAssertFalse(store.writingSaved)
        store.apply(.result(id: try lastRequestID(), outcome: .failure(RequestFailure(message: "Disk full"))))
        await waitUntil { !store.writingSaving }
        XCTAssertEqual(store.alert?.message, "Disk full")
        XCTAssertEqual(store.writing.timing, .quick)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.effectiveTiming, .deliberate)

        store.saveWriting()
        await waitUntil { self.transport.sentActions.count == 2 }
        store.apply(.result(id: try lastRequestID(), outcome: .success(.object(["personalization": .object(["enabled": .bool(false), "revision": .number(0), "preferences": .array([])])]))))
        await waitUntil { !store.writingSaving }
        XCTAssertTrue(store.writingSaved)
        XCTAssertFalse(store.hasUnsavedWritingChanges)
        XCTAssertEqual(store.effectiveTiming, .quick)
        XCTAssertEqual(store.effectiveVisibility, .clear)
        XCTAssertFalse(store.effectiveAutomatic)
    }

    func testMalformedWritingAcknowledgementDoesNotClaimSaved() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.setTiming(.quick)
        store.saveWriting()
        await waitUntil { self.transport.sentActions.count == 1 }
        store.apply(.result(id: try lastRequestID(), outcome: .success(.null)))
        await waitUntil { !store.writingSaving }
        XCTAssertFalse(store.writingSaved)
        XCTAssertTrue(store.hasUnsavedWritingChanges)
        XCTAssertNotNil(store.alert)
    }

    func testLearningDraftSurvivesAutomaticUpdatesAndSavesPatch() async throws {
        let store = makeStore()
        var status = try Fixtures.status()
        status.personalization = .init(enabled: true, revision: 1, preferences: [learningPreference])
        store.apply(.state(status, entries: [], transforms: Fixtures.transforms))
        store.editPreference(id: learningPreference.id, value: "detailed")
        var second = learningPreference
        second.id = "22222222-2222-4222-8222-222222222222"
        second.dimension = .structure
        second.value = "lists"
        status.personalization.preferences.append(second)
        status.personalization.revision = 2
        store.apply(.state(status, entries: [], transforms: Fixtures.transforms))
        XCTAssertEqual(store.displayedPreferences.count, 2)
        XCTAssertEqual(store.displayedPreferences.first?.value, "detailed")
        store.saveWriting()
        await waitUntil { self.transport.sentActions.count == 1 }
        let payload = try XCTUnwrap(transport.sent.last?["payload"] as? [String: Any])
        let learning = try XCTUnwrap(payload["personalization"] as? [String: Any])
        XCTAssertEqual((learning["edits"] as? [Any])?.count, 1)
        var saved = status.personalization
        saved.preferences[0].value = "detailed"
        saved.preferences[0].origin = .explicit
        let result = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(["personalization": saved]))
        store.apply(.result(id: try lastRequestID(), outcome: .success(result)))
        await waitUntil { !store.writingSaving }
        XCTAssertTrue(store.writingSaved)
        XCTAssertEqual(store.displayedPreferences.count, 2)
        XCTAssertFalse(store.hasUnsavedWritingChanges)
    }

    func testLearningResetRevertAndAccountSwitch() async throws {
        let store = makeStore()
        var status = try Fixtures.status()
        status.personalization = .init(enabled: true, revision: 1, preferences: [learningPreference])
        store.apply(.state(status, entries: [], transforms: Fixtures.transforms))
        store.resetLearning()
        XCTAssertTrue(store.displayedPreferences.isEmpty)
        XCTAssertTrue(store.hasUnsavedWritingChanges)
        store.discardWritingChanges()
        XCTAssertEqual(store.displayedPreferences.count, 1)
        store.forgetPreference(learningPreference.id)
        store.saveWriting()
        await waitUntil { self.transport.sentActions.count == 1 }
        status.account.identity?.subject = "other-account"
        status.personalization = .empty
        store.apply(.state(status, entries: [], transforms: Fixtures.transforms))
        let result = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(["personalization": PersonalizationSnapshot(enabled: true, revision: 2, preferences: [learningPreference])]))
        store.apply(.result(id: try lastRequestID(), outcome: .success(result)))
        await waitUntil { !store.writingSaving }
        XCTAssertFalse(store.writingSaved)
        XCTAssertTrue(store.displayedPreferences.isEmpty)
        XCTAssertFalse(store.hasUnsavedWritingChanges)
    }

    func testWritingSaveCannotCrossSignOutAndReturnToSameAccount() async throws {
        let store = makeStore()
        let original = try Fixtures.status()
        store.apply(.state(original, entries: [], transforms: Fixtures.transforms))
        store.setTiming(.quick)
        store.saveWriting()
        await waitUntil { self.transport.sentActions.count == 1 }
        var signedOut = original
        signedOut.account.state = .signedOut
        store.apply(.state(signedOut, entries: [], transforms: Fixtures.transforms))
        store.apply(.state(original, entries: [], transforms: Fixtures.transforms))
        store.apply(.result(id: try lastRequestID(), outcome: .success(.object(["personalization": .object(["enabled": .bool(false), "revision": .number(0), "preferences": .array([])])]))))
        await waitUntil { !store.writingSaving }
        XCTAssertFalse(store.writingSaved)
        XCTAssertEqual(store.effectiveTiming, original.timing)
    }

    private var learningPreference: StylePreference {
        .init(id: "11111111-1111-4111-8111-111111111111", dimension: .concision, value: "concise", appId: "com.apple.mail", origin: .learned)
    }

    func testWritingRevertAndReturningToSavedValuesClearDirtyStateWithoutRequests() {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.setTiming(.quick)
        store.setTiming(.deliberate)
        XCTAssertFalse(store.hasUnsavedWritingChanges)
        store.setVisibility(.clear)
        store.setAutomatic(false)
        store.discardWritingChanges()
        XCTAssertEqual(store.writing.timing, .deliberate)
        XCTAssertEqual(store.writing.automaticSuggestions, store.effectiveAutomatic)
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertTrue(transport.sentActions.isEmpty)
    }

    func testLanguageOverlayAffectsLocalization() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.setLanguage(.en)
        XCTAssertEqual(store.l10n[.sectionLibrary], "Library")
        await waitUntil { self.transport.sentActions == ["setUiLanguage"] }
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .success(.null)))
        await waitUntil { store.pendingLanguage == nil }
        XCTAssertEqual(store.l10n[.sectionLibrary], "Biblioteca", "Until a new state arrives the confirmed value is Spanish")
    }

    func testApplicationRowsMergeObservedAndSavedApps() throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        let rows = store.applicationRows()
        XCTAssertEqual(rows.map(\.id).sorted(), ["com.apple.mail", "com.google.Chrome"])
        let mail = try XCTUnwrap(rows.first { $0.id == "com.apple.mail" })
        XCTAssertTrue(mail.isObserved)
        XCTAssertTrue(mail.isCurrent)
        XCTAssertTrue(store.isApplicationEnabled("com.apple.mail"))
        XCTAssertFalse(store.isApplicationEnabled("com.google.Chrome"))
        XCTAssertTrue(store.isApplicationEnabled("com.unknown.app"))
    }

    func testNavigationAsksBeforeDiscardingDirtyDraft() throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.navigate(.openEntry("entry-1"))
        XCTAssertEqual(store.selection, .library)
        XCTAssertEqual(store.libraryDraft?.title, "Acme pricing")
        XCTAssertFalse(store.hasUnsavedLibraryChanges)

        store.navigate(.section(.writing))
        XCTAssertEqual(store.selection, .writing, "Clean drafts navigate freely")
        XCTAssertNotNil(store.libraryDraft, "Clean drafts stay open")

        store.libraryDraft?.title = "Acme pricing 2026"
        XCTAssertTrue(store.hasUnsavedLibraryChanges)
        store.navigate(.section(.general))
        XCTAssertEqual(store.selection, .writing)
        XCTAssertEqual(store.pendingNavigation, .section(.general))

        store.cancelPendingNavigation()
        XCTAssertNil(store.pendingNavigation)
        XCTAssertEqual(store.libraryDraft?.title, "Acme pricing 2026")

        store.navigate(.openEntry("entry-2"))
        store.confirmPendingNavigation()
        XCTAssertEqual(store.selection, .library)
        XCTAssertEqual(store.libraryDraft?.id, "entry-2")
        XCTAssertFalse(store.hasUnsavedLibraryChanges)
    }

    func testSaveAdoptsReturnedEntryAndKeepsDraftOnError() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.navigate(.newEntry(.memory))
        store.libraryDraft?.title = "Alex prefers calls"
        store.libraryDraft?.anchor = "alex@example.com"
        store.libraryDraft?.appIds = ["com.apple.mail"]
        store.libraryDraft?.text = "Alex asked for a call instead of email."
        XCTAssertTrue(store.libraryDraft?.canSave == true)

        store.saveLibraryDraft()
        XCTAssertTrue(store.libraryBusy)
        await waitUntil { self.transport.sentActions == ["librarySave"] }
        var id = try lastRequestID()
        store.apply(.result(id: id, outcome: .failure(RequestFailure(message: "Topic too broad"))))
        await waitUntil { !store.libraryBusy }
        XCTAssertEqual(store.libraryError, "Topic too broad")
        XCTAssertEqual(store.libraryDraft?.title, "Alex prefers calls", "Draft survives a failed save")
        XCTAssertTrue(store.hasUnsavedLibraryChanges)

        store.saveLibraryDraft()
        await waitUntil { self.transport.sentActions.count == 2 }
        id = try lastRequestID()
        let saved = #"{"id":"entry-3","title":"Alex prefers calls","kind":"memory","text":"Alex asked for a call instead of email.","revision":1,"updatedAt":1756600000000,"expiresAt":null,"scope":{"appIds":["com.apple.mail"],"anchor":"alex@example.com"},"createdAt":1756600000000,"provenance":{"kind":"user"}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(saved.utf8))
        store.apply(.result(id: id, outcome: .success(value)))
        await waitUntil { !store.libraryBusy }
        XCTAssertNil(store.libraryError)
        XCTAssertEqual(store.libraryDraft?.id, "entry-3")
        XCTAssertEqual(store.libraryDraft?.expectedRevision, 1)
        XCTAssertFalse(store.hasUnsavedLibraryChanges)
        XCTAssertEqual(store.entries.count, 3)
    }

    func testImportCancelledLeavesDraftUntouched() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.navigate(.newEntry(.style))
        store.libraryDraft?.title = "Short replies"
        store.importLibraryDraft()
        await waitUntil { self.transport.sentActions == ["libraryImport"] }
        let payload = try XCTUnwrap(transport.sent.last?["payload"] as? [String: Any])
        XCTAssertNil(payload["text"])
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .success(.null)))
        await waitUntil { !store.libraryBusy }
        XCTAssertNil(store.libraryError)
        XCTAssertEqual(store.libraryDraft?.title, "Short replies")
        XCTAssertNil(store.libraryDraft?.id)
    }

    func testDeleteClosesEditor() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.navigate(.openEntry("entry-1"))
        store.deleteLibraryDraft()
        await waitUntil { self.transport.sentActions == ["libraryDelete"] }
        let payload = try XCTUnwrap(transport.sent.last?["payload"] as? [String: Any])
        XCTAssertEqual(payload["id"] as? String, "entry-1")
        XCTAssertEqual(payload["revision"] as? Int, 3)
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .success(.null)))
        await waitUntil { store.libraryDraft == nil }
        XCTAssertFalse(store.entries.contains { $0.id == "entry-1" })
    }

    func testStateUpdateRefreshesCleanDraftAndClosesDeletedOne() throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.navigate(.openEntry("entry-1"))
        let bumped = Fixtures.stateLine.replacingOccurrences(of: "\"revision\":3", with: "\"revision\":4")
        store.receive(line: bumped)
        XCTAssertEqual(store.libraryDraft?.expectedRevision, 4)

        store.libraryDraft?.text = "edited"
        store.receive(line: Fixtures.stateLine)
        XCTAssertEqual(store.libraryDraft?.text, "edited", "Dirty drafts are preserved across state updates")
        XCTAssertEqual(store.libraryDraft?.expectedRevision, 4)

        store.navigate(.openEntry("entry-2"))
        store.confirmPendingNavigation()
        let withoutStyle = #"{"type":"state","context":{"semanticStatus":"not_prepared","historyPage":0,"visualStatus":"disabled","visualEnabled":false,"enabled":false,"history":[],"connections":[],"references":[],"used":[]},"status":\#(Fixtures.statusJSON),"entries":[\#(Fixtures.referenceEntryJSON)],"transforms":{"enabled":false,"transforms":[]}}"#
        store.receive(line: withoutStyle)
        XCTAssertNil(store.libraryDraft, "A clean draft of a deleted entry closes")
    }

    func testSignedOutHidesUnsavedChangesFromGuards() throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.navigate(.openEntry("entry-1"))
        store.libraryDraft?.title = "Changed"
        XCTAssertTrue(store.hasUnsavedLibraryChanges)
        let signedOut = Fixtures.stateLine.replacingOccurrences(of: "\"state\":\"signed_in\"", with: "\"state\":\"signed_out\"")
        store.receive(line: signedOut)
        XCTAssertFalse(store.hasUnsavedLibraryChanges)
        XCTAssertNil(store.libraryDraft)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testSwitchingAccountsClearsUnsavedLibraryText() {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.navigate(.openEntry("entry-1"))
        store.libraryDraft?.text = "Private unsaved text"
        store.receive(line: Fixtures.stateLine.replacingOccurrences(of: "sub-1", with: "sub-2"))
        XCTAssertNil(store.libraryDraft)
    }

    func testExerciseLifecycleSendsActivationAndDeactivation() async throws {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.openExercise()
        XCTAssertTrue(store.exercisePresented)
        XCTAssertTrue(store.exerciseStarting)
        await waitUntil { self.transport.sentActions == ["setExerciseActive"] }
        XCTAssertEqual(transport.sent.last?["payload"] as? Bool, true)
        let id = try lastRequestID()
        store.apply(.result(id: id, outcome: .failure(RequestFailure(message: "Helper unavailable"))))
        await waitUntil { !store.exerciseStarting }
        XCTAssertEqual(store.exerciseError, "Helper unavailable")

        store.requestExerciseSuggestion()
        await waitUntil { self.transport.sentActions.count == 2 }
        XCTAssertEqual(transport.sentActions.last, "requestExerciseSuggestion")

        store.closeExercise()
        XCTAssertFalse(store.exercisePresented)
        await waitUntil { self.transport.sentActions.count == 3 }
        XCTAssertEqual(transport.sentActions.last, "setExerciseActive")
        XCTAssertEqual(transport.sent.last?["payload"] as? Bool, false)
    }

    func testShowMessageInvokesActivationHook() {
        let store = makeStore()
        var shown = 0
        store.onShowRequested = { shown += 1 }
        store.receive(line: #"{"type":"show"}"#)
        XCTAssertEqual(shown, 1)
    }

    func testMalformedLineReportsOnceAndKeepsState() {
        let store = makeStore()
        store.receive(line: Fixtures.stateLine)
        store.receive(line: "garbage")
        XCTAssertEqual(store.alert?.message, L10n(language: .es)[.malformedUpdate])
        store.alert = nil
        store.receive(line: "{\"type\":\"unknown\"}")
        XCTAssertNil(store.alert, "Only the first malformed line is announced")
        XCTAssertNotNil(store.status)
    }

    func testUnknownResultIdIsIgnored() {
        let store = makeStore()
        store.apply(.result(id: "nope", outcome: .success(.null)))
        XCTAssertNil(store.alert)
    }
}

final class IdentifierSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return "req-\(value)"
    }
}
