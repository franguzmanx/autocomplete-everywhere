import Foundation
import XCTest
@testable import AutocompleteSettings

final class ContextSettingsTests: XCTestCase {
    func testContextActionsMatchParentContracts() throws {
        for (action, name, payload) in [
            (SettingsAction.contextUnpin("source"), "context_unpin", ["id": "source"]),
            (.contextSearch("release notes"), "context_search", ["query": "release notes"])
        ] {
            let data = try JSONEncoder().encode(RequestEnvelope(id: "request", action: action))
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(value["action"] as? String, name)
            XCTAssertEqual(value["payload"] as? [String: String], payload)
        }
        let more = try JSONEncoder().encode(RequestEnvelope(id: "request", action: .contextHistoryMore))
        let moreValue = try XCTUnwrap(JSONSerialization.jsonObject(with: more) as? [String: Any])
        XCTAssertEqual(moreValue["action"] as? String, "context_history_more")
        XCTAssertTrue(moreValue["payload"] is NSNull)
        let previous = try JSONEncoder().encode(RequestEnvelope(id: "request", action: .contextHistoryPrevious))
        let previousValue = try XCTUnwrap(JSONSerialization.jsonObject(with: previous) as? [String: Any])
        XCTAssertEqual(previousValue["action"] as? String, "context_history_previous")
        XCTAssertTrue(previousValue["payload"] is NSNull)
        let visual = try JSONEncoder().encode(RequestEnvelope(id: "request", action: .contextSetVisualEnabled(true)))
        let visualValue = try XCTUnwrap(JSONSerialization.jsonObject(with: visual) as? [String: Any])
        XCTAssertEqual(visualValue["action"] as? String, "context_set_visual_enabled")
        XCTAssertEqual(visualValue["payload"] as? [String: Bool], ["enabled": true])
    }
    func testSourcesExposeInspectableExcerptAndSeparateVisualConsent() throws {
        let data = Data(#"{"enabled":true,"visualEnabled":false,"semanticStatus":"not_prepared","historyPage":0,"visualStatus":"disabled","history":[],"connections":[],"references":[],"used":[{"id":"source","title":"Decision","detail":"Observed · Notes","excerpt":"The release is scheduled for Friday."}]}"#.utf8)
        let state = try JSONDecoder().decode(ContextState.self, from: data)
        XCTAssertTrue(state.enabled)
        XCTAssertFalse(state.visualEnabled)
        XCTAssertEqual(state.historyPage, 0)
        XCTAssertEqual(state.semanticStatus, .not_prepared)
        XCTAssertEqual(state.used.first?.excerpt, "The release is scheduled for Friday.")
        XCTAssertEqual(state.used.first?.detail, "Observed · Notes")
    }
}
