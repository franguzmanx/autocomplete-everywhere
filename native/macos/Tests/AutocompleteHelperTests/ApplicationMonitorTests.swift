import XCTest
@testable import AutocompleteHelper

final class ApplicationMonitorTests: XCTestCase {
    func testNoExternalForegroundAppEncodesExplicitNullForDesktopProtocol() throws {
        let message = ApplicationStateMessage(payload: .init(currentApplication: nil, applications: []))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertTrue(payload["currentApplication"] is NSNull)
    }
}
