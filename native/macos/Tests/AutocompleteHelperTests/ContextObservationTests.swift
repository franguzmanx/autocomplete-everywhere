import XCTest
@testable import AutocompleteHelper
final class ContextObservationTests: XCTestCase {
    func testConsentPauseExclusionAndSecureSurfaceGateReads() {
        var config = CaptureConfiguration.enabled
        XCTAssertFalse(ContextObservationPolicy.allows(configuration: config, appId: "example", locked: false, secure: false))
        config.contextEnabled = true
        XCTAssertTrue(ContextObservationPolicy.allows(configuration: config, appId: "example", locked: false, secure: false))
        XCTAssertFalse(ContextObservationPolicy.allows(configuration: config, appId: "example", locked: true, secure: false))
        XCTAssertFalse(ContextObservationPolicy.allows(configuration: config, appId: "example", locked: false, secure: true))
        config.excludedApplications = ["example"]
        XCTAssertFalse(ContextObservationPolicy.allows(configuration: config, appId: "example", locked: false, secure: false))
        XCTAssertFalse(ContextObservationPolicy.allows(configuration: .disabled, appId: "example", locked: false, secure: false))
    }
    func testScreenPermissionCommandRequiresExplicitNullPayloadAndCurrentProtocol() {
        XCTAssertEqual(HelperCommandDecoder().decode(#"{"protocolVersion":5,"type":"context_request_screen_permission","payload":null}"#), .contextRequestScreenPermission)
        XCTAssertNil(HelperCommandDecoder().decode(#"{"protocolVersion":5,"type":"context_request_screen_permission","payload":true}"#))
        XCTAssertNil(HelperCommandDecoder().decode(#"{"protocolVersion":4,"type":"context_request_screen_permission","payload":null}"#))
    }
    func testDedupUsesContentWithoutCursorGeometry() {
        XCTAssertEqual(ContextObservationPolicy.digest("window:message"), ContextObservationPolicy.digest("window:message"))
        XCTAssertNotEqual(ContextObservationPolicy.digest("window:message"), ContextObservationPolicy.digest("window:edited"))
    }
    func testInvalidationRequiresBoundedRequestIdentifiers() {
        let id = UUID().uuidString
        XCTAssertEqual(HelperCommandDecoder().decode("{\"protocolVersion\":5,\"type\":\"context_invalidate\",\"payload\":{\"requestIds\":[\"\(id)\"]}}"), .contextInvalidate([id]))
        XCTAssertNil(HelperCommandDecoder().decode("{\"protocolVersion\":5,\"type\":\"context_invalidate\",\"payload\":{\"requestIds\":[\"invalid\"]}}"))
    }
}

extension ContextObservationTests {
    func testTruncatedChildListNeverAuthorizesPixelsEvenIfQueueDrains() {
        let budget = ContextObservationPolicy.childBudget(count: 300, inspected: 1, queued: 0)
        XCTAssertEqual(budget.take, 255)
        XCTAssertFalse(budget.complete)
        XCTAssertFalse(ContextObservationPolicy.childBudget(count: 1, inspected: 250, queued: 6).complete)
        XCTAssertTrue(ContextObservationPolicy.childBudget(count: 3, inspected: 250, queued: 3).complete)
    }
    func testScreenshotRequiresUniqueTitleAndGeometryMatch() {
        let active = CGRect(x: 0, y: 0, width: 800, height: 600)
        let other = active.offsetBy(dx: 100, dy: 100)
        XCTAssertEqual(ContextObservationPolicy.matchingWindowIndex(title: "Document", frame: active,
            candidates: [("Document", other), ("Document", active)]), 1)
        XCTAssertNil(ContextObservationPolicy.matchingWindowIndex(title: "Document", frame: active,
            candidates: [("Document", active), ("Document", active)]))
        XCTAssertNil(ContextObservationPolicy.matchingWindowIndex(title: "Document", frame: active,
            candidates: [("Document", other)]))
    }
    func testObservedURLAndDocumentIdentityRetainDistinctDocuments() {
        let first = "https://github.com/org/repo/pull/42"
        let second = "https://www.figma.com/design/AbC/File?node-id=1-2"
        XCTAssertEqual(ContextObservationPolicy.observedURL(first), first)
        XCTAssertEqual(ContextObservationPolicy.observedURL(second), second)
        XCTAssertNil(ContextObservationPolicy.observedURL("arbitrary field input"))
        XCTAssertNil(ContextObservationPolicy.observedURL("https://user:password@example.com"))
        XCTAssertNotEqual(ContextObservationPolicy.documentKey(url: first, title: "Browser"), ContextObservationPolicy.documentKey(url: second, title: "Browser"))
        XCTAssertNotEqual(ContextObservationPolicy.documentKey(url: nil, title: "Document A"), ContextObservationPolicy.documentKey(url: nil, title: "Document B"))
        XCTAssertEqual(ContextObservationPolicy.documentKey(url: first, title: "Changed page title"), ContextObservationPolicy.documentKey(url: first, title: "Original title"))
    }
}

extension ContextObservationTests {
    func testUnicodeSourcesRespectWireUTF16LimitsWithoutSplittingSurrogates() {
        let chunks = ContextObservationPolicy.sourceTexts(String(repeating: "😀", count: 7_000))
        XCTAssertEqual(chunks.count, 6)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 2_000 && !$0.contains("�") })
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.utf16.count }, 12_000)
    }
}
