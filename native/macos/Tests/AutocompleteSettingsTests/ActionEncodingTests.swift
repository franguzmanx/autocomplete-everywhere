import Foundation
import XCTest
@testable import AutocompleteSettings

final class ActionEncodingTests: XCTestCase {
    func testExplicitGlobalPreferenceEncodesNullScope() throws {
        let preference = StylePreference(id: "11111111-1111-4111-8111-111111111111", dimension: .formality,
            value: "formal", appId: nil, origin: .explicit)
        let data = try JSONEncoder().encode(preference)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["appId"] is NSNull, "Global scope is explicit null in the strict shared contract")
        XCTAssertTrue(preference.isValid)
        var invalid = preference
        invalid.origin = .learned
        XCTAssertFalse(invalid.isValid)
        invalid.appId = "com.apple.mail"
        invalid.value = "English"
        XCTAssertFalse(invalid.isValid, "Language is never a learned dimension")
    }
    func testPersonalizationAcknowledgementRequiresExplicitValidScope() throws {
        let missing = #"{"id":"11111111-1111-4111-8111-111111111111","dimension":"formality","value":"formal","origin":"explicit"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(StylePreference.self, from: Data(missing.utf8)))
        let invalid = StylePreference(id: "11111111-1111-4111-8111-111111111111", dimension: .formality, value: "formal", appId: "not an app", origin: .explicit)
        XCTAssertFalse(invalid.isValid)
    }

    private func encode(_ action: SettingsAction, id: String = "req-1") throws -> [String: Any] {
        let data = try JSONEncoder().encode(RequestEnvelope(id: id, action: action))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testNullPayloadActions() throws {
        let actions: [(SettingsAction, String)] = [
            (.ready, "ready"), (.resume, "resume"), (.beginSignIn, "beginSignIn"), (.signOut, "signOut"),
            (.openManageAccount, "openManageAccount"), (.restartHelper, "restartHelper"),
            (.requestExerciseSuggestion, "requestExerciseSuggestion"),
        ]
        for (action, name) in actions {
            let json = try encode(action)
            XCTAssertEqual(json["id"] as? String, "req-1")
            XCTAssertEqual(json["action"] as? String, name)
            XCTAssertTrue(json.keys.contains("payload"), "\(name) must carry an explicit null payload")
            XCTAssertTrue(json["payload"] is NSNull, "\(name) payload should be null")
        }
    }

    func testScalarPayloads() throws {
        XCTAssertEqual(try encode(.pause(.fifteenMinutes))["payload"] as? String, "15m")
        XCTAssertEqual(try encode(.pause(.thirtyMinutes))["payload"] as? String, "30m")
        XCTAssertEqual(try encode(.pause(.oneHour))["payload"] as? String, "1h")
        XCTAssertEqual(try encode(.pause(.tomorrow))["payload"] as? String, "tomorrow")
        XCTAssertEqual(try encode(.setExerciseActive(true))["payload"] as? Bool, true)
        XCTAssertEqual(try encode(.setUiLanguage(.es))["payload"] as? String, "es")
        XCTAssertEqual(try encode(.openMacPermissionSettings(.inputMonitoring))["payload"] as? String, "input_monitoring")
        XCTAssertEqual(try encode(.openMacPermissionSettings(.accessibility))["payload"] as? String, "accessibility")
    }

    func testAppEnabledAndDeletePayloads() throws {
        let app = try XCTUnwrap(try encode(.setAppEnabled(appId: "com.apple.mail", enabled: false))["payload"] as? [String: Any])
        XCTAssertEqual(app["appId"] as? String, "com.apple.mail")
        XCTAssertEqual(app["enabled"] as? Bool, false)

        let delete = try XCTUnwrap(try encode(.libraryDelete(id: "entry-1", revision: 3))["payload"] as? [String: Any])
        XCTAssertEqual(delete["id"] as? String, "entry-1")
        XCTAssertEqual(delete["revision"] as? Int, 3)
        XCTAssertEqual(delete.count, 2)
    }

    func testLibrarySaveOmitsAbsentIdentityAndKeepsNullExpiry() throws {
        var draft = LibraryDraft(kind: .knowledge)
        draft.title = "  Acme pricing "
        draft.anchor = " Acme project "
        draft.appIds = ["com.apple.mail"]
        draft.text = "Seat price is 12."
        let payload = try XCTUnwrap(try encode(.librarySave(draft.input()))["payload"] as? [String: Any])
        XCTAssertNil(payload["id"])
        XCTAssertNil(payload["expectedRevision"])
        XCTAssertEqual(payload["title"] as? String, "Acme pricing")
        XCTAssertEqual(payload["kind"] as? String, "knowledge")
        XCTAssertEqual(payload["text"] as? String, "Seat price is 12.")
        XCTAssertTrue(payload["expiresAt"] is NSNull)
        let scope = try XCTUnwrap(payload["scope"] as? [String: Any])
        XCTAssertEqual(scope["appIds"] as? [String], ["com.apple.mail"])
        XCTAssertEqual(scope["anchor"] as? String, "Acme project")
        XCTAssertEqual(Set(payload.keys), ["title", "kind", "text", "scope", "expiresAt"])
    }

    func testLibrarySaveOfExistingEntryCarriesRevisionAndExpiry() throws {
        let entry = try Fixtures.entries()[0]
        let draft = LibraryDraft(entry: entry)
        let payload = try XCTUnwrap(try encode(.librarySave(draft.input()))["payload"] as? [String: Any])
        XCTAssertEqual(payload["id"] as? String, "entry-1")
        XCTAssertEqual(payload["expectedRevision"] as? Int, 3)
        XCTAssertEqual(payload["expiresAt"] as? Int64, 1_759_276_800_000)
    }

    func testLibraryImportOmitsText() throws {
        var draft = LibraryDraft(kind: .style)
        draft.title = "Short replies"
        draft.text = "ignored"
        let payload = try XCTUnwrap(try encode(.libraryImport(draft.input(includeText: false)))["payload"] as? [String: Any])
        XCTAssertNil(payload["text"])
        XCTAssertEqual(payload["kind"] as? String, "style")
        XCTAssertTrue(payload["expiresAt"] is NSNull)
        XCTAssertEqual(try encode(.libraryImport(draft.input()))["action"] as? String, "libraryImport")
        let withText = try XCTUnwrap(try encode(.libraryImport(draft.input()))["payload"] as? [String: Any])
        XCTAssertNil(withText["text"], "libraryImport must strip text even if the draft has some")
    }

    func testEnvelopeIsSingleLineJSON() throws {
        let data = try JSONEncoder().encode(RequestEnvelope(id: "x", action: .librarySave(LibraryDraft(kind: .style).input())))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("\n"))
    }
}
