import Foundation
import XCTest
@testable import AutocompleteSettings

final class WireDecodingTests: XCTestCase {
    func testDecodesFullStateMessage() throws {
        let message = try IncomingMessage.decode(line: Fixtures.stateLine)
        guard case .state(let status, let entries, let transforms, _) = message else {
            return XCTFail("Expected state message")
        }
        XCTAssertEqual(transforms, Fixtures.transforms)
        XCTAssertEqual(status.activity.requested, 4)
        XCTAssertEqual(status.activity.acceptedCharacters, 12)
        XCTAssertEqual(status.permissions.accessibility, .granted)
        XCTAssertEqual(status.permissions.inputMonitoring, .required)
        XCTAssertEqual(status.account.state, .signedIn)
        XCTAssertEqual(status.account.identity?.email, "jamie@example.com")
        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.pausedUntil, 1_757_059_200_000)
        XCTAssertEqual(status.pausedUntilDate, Date(timeIntervalSince1970: 1_757_059_200))
        XCTAssertFalse(status.automaticSuggestions)
        XCTAssertEqual(status.uiLanguage, .es)
        XCTAssertEqual(status.timing, .deliberate)
        XCTAssertEqual(status.visibility, .clear)
        XCTAssertEqual(status.apps, ["com.apple.mail": true, "com.google.Chrome": false])
        XCTAssertEqual(status.applications, [ObservedApplication(id: "com.apple.mail", name: "Mail")])
        XCTAssertEqual(status.currentApplication, "com.apple.mail")
        XCTAssertEqual(status.helperState, .running)
        XCTAssertFalse(status.shortcutRegistered)
        XCTAssertTrue(status.libraryAvailable)
        XCTAssertEqual(status.connection, .offline)
        XCTAssertEqual(status.exercise, .waiting)

        XCTAssertEqual(entries.count, 2)
        let reference = try XCTUnwrap(entries.first)
        XCTAssertEqual(reference.id, "entry-1")
        XCTAssertEqual(reference.kind, .knowledge)
        XCTAssertEqual(reference.revision, 3)
        XCTAssertEqual(reference.scope, LibraryScope(appIds: ["com.apple.mail"], anchor: "Acme project"))
        XCTAssertEqual(reference.expiresAt, 1_759_276_800_000)
        XCTAssertEqual(reference.provenance, .file(name: "notes.md"))
        XCTAssertEqual(reference.createdAt, 1_756_000_000_000)

        let style = entries[1]
        XCTAssertEqual(style.kind, .style)
        XCTAssertNil(style.expiresAt)
        XCTAssertEqual(style.provenance, .user)
        XCTAssertEqual(style.scope.appIds, [])
    }

    func testDecodesNullIdentityAndPause() throws {
        let line = Fixtures.stateLine
            .replacingOccurrences(of: Fixtures.identityJSON, with: "null")
            .replacingOccurrences(of: "\"pausedUntil\":1757059200000", with: "\"pausedUntil\":null")
            .replacingOccurrences(of: "\"currentApplication\":\"com.apple.mail\"", with: "\"currentApplication\":null")
        guard case .state(let status, _, _, _) = try IncomingMessage.decode(line: line) else {
            return XCTFail("Expected state message")
        }
        XCTAssertNil(status.account.identity)
        XCTAssertNil(status.pausedUntil)
        XCTAssertNil(status.currentApplication)
    }

    func testDecodesSuccessfulResultWithValueAndNull() throws {
        let entryResult = #"{"type":"result","id":"abc","ok":true,"value":\#(Fixtures.styleEntryJSON)}"#
        guard case .result(let id, let outcome) = try IncomingMessage.decode(line: entryResult) else {
            return XCTFail("Expected result")
        }
        XCTAssertEqual(id, "abc")
        let value = try outcome.get()
        let entry: LibraryEntry = try value.decoded()
        XCTAssertEqual(entry.id, "entry-2")
        XCTAssertEqual(entry.updatedAt, 1_756_500_000_000)

        let nullResult = #"{"type":"result","id":"def","ok":true,"value":null}"#
        guard case .result(_, let nullOutcome) = try IncomingMessage.decode(line: nullResult) else {
            return XCTFail("Expected result")
        }
        XCTAssertTrue(try nullOutcome.get().isNull)

        let missingValue = #"{"type":"result","id":"ghi","ok":true}"#
        guard case .result(_, let missingOutcome) = try IncomingMessage.decode(line: missingValue) else {
            return XCTFail("Expected result")
        }
        XCTAssertTrue(try missingOutcome.get().isNull)
    }

    func testDecodesFailedResult() throws {
        let line = #"{"type":"result","id":"abc","ok":false,"error":"This source changed elsewhere."}"#
        guard case .result(let id, let outcome) = try IncomingMessage.decode(line: line) else {
            return XCTFail("Expected result")
        }
        XCTAssertEqual(id, "abc")
        guard case .failure(let failure) = outcome else { return XCTFail("Expected failure") }
        XCTAssertEqual(failure.message, "This source changed elsewhere.")
    }

    func testDecodesShowAndRejectsUnknownType() throws {
        XCTAssertEqual(try IncomingMessage.decode(line: #"{"type":"show"}"#), .show)
        XCTAssertThrowsError(try IncomingMessage.decode(line: #"{"type":"mystery"}"#))
        XCTAssertThrowsError(try IncomingMessage.decode(line: "not json"))
    }

    func testRejectsUnknownEnumValues() {
        let line = Fixtures.stateLine.replacingOccurrences(of: "\"timing\":\"deliberate\"", with: "\"timing\":\"unknown\"")
        XCTAssertThrowsError(try IncomingMessage.decode(line: line))
    }

    func testJSONValueRoundTripsIntegralNumbers() throws {
        let value: JSONValue = .object(["revision": .number(3), "updatedAt": .number(1_756_500_000_000), "ratio": .number(0.5)])
        let data = try JSONEncoder().encode(value)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"revision\":3"))
        XCTAssertTrue(text.contains("\"updatedAt\":1756500000000"))
        XCTAssertTrue(text.contains("\"ratio\":0.5"))
    }
}

enum Fixtures {
    static let identityJSON = #"{"subject":"sub-1","name":"Jamie Doe","email":"jamie@example.com"}"#

    static let referenceEntryJSON = #"""
    {"id":"entry-1","title":"Acme pricing","kind":"knowledge","text":"Seat price is 12.","revision":3,"updatedAt":1756400000000,"expiresAt":1759276800000,"scope":{"appIds":["com.apple.mail"],"anchor":"Acme project"},"createdAt":1756000000000,"provenance":{"kind":"file","name":"notes.md"}}
    """#

    static let styleEntryJSON = #"""
    {"id":"entry-2","title":"Short replies","kind":"style","text":"Keep replies under three sentences.","revision":1,"updatedAt":1756500000000,"expiresAt":null,"scope":{"appIds":[],"anchor":""},"createdAt":1756500000000,"provenance":{"kind":"user"}}
    """#

    static let transforms = TransformSettings(enabled: false, transforms: [])
    static let activityJSON = #"{"since":"2026-09-08T00:00:00.000Z","requested":4,"generated":3,"suppressed":1,"failed":0,"cancelled":0,"shown":2,"accepted":1,"typedThrough":0,"dismissed":1,"stale":0,"acceptedCharacters":12,"requestToVisibleMs":{"p50":120,"p95":220,"samples":2},"requestToFinalMs":{"p50":100,"p95":200,"samples":3},"lastOutcome":"accepted_partial"}"#

    static let statusJSON = #"""
    {"activity":\#(activityJSON),"permissions":{"accessibility":"granted","inputMonitoring":"required"},"account":{"state":"signed_in","identity":\#(identityJSON)},"enabled":true,"pausedUntil":1757059200000,"automaticSuggestions":false,"uiLanguage":"es","timing":"deliberate","visibility":"clear","apps":{"com.apple.mail":true,"com.google.Chrome":false},"applications":[{"id":"com.apple.mail","name":"Mail"}],"currentApplication":"com.apple.mail","helperState":"running","shortcut":{"accelerator":"Command+Shift+Space","keyCode":49,"modifiers":768},"acceptShortcut":{"accelerator":"Tab","keyCode":48,"modifiers":0},"dismissShortcut":{"accelerator":"Escape","keyCode":53,"modifiers":0},"shortcutRegistered":false,"libraryAvailable":true,"connection":"offline","exercise":"waiting","personalization":{"enabled":false,"revision":0,"preferences":[]}}
    """#

    static let stateLine = #"{"type":"state","context":{"semanticStatus":"not_prepared","historyPage":0,"visualStatus":"disabled","visualEnabled":false,"enabled":false,"history":[],"connections":[],"references":[],"used":[]},"status":\#(statusJSON),"entries":[\#(referenceEntryJSON),\#(styleEntryJSON)],"transforms":{"enabled":false,"transforms":[]}}"#

    static func status() throws -> ProductStatus {
        try JSONDecoder().decode(ProductStatus.self, from: Data(statusJSON.utf8))
    }

    static func entries() throws -> [LibraryEntry] {
        try JSONDecoder().decode([LibraryEntry].self, from: Data("[\(referenceEntryJSON),\(styleEntryJSON)]".utf8))
    }
}
