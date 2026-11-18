import XCTest
@testable import AutocompleteSettings

final class ApiKeyAccountTests: XCTestCase {
    func testHostedStatusHasNoAccountKind() throws {
        XCTAssertFalse(try Fixtures.status().account.usesApiKey)
    }

    func testAccountKindDecodesFromTheWire() throws {
        let json = Data(#"{"state":"signed_out","identity":null,"kind":"api_key"}"#.utf8)
        let account = try JSONDecoder().decode(AccountStatus.self, from: json)
        XCTAssertTrue(account.usesApiKey)
        XCTAssertEqual(account.state, .signedOut)
    }

    func testMissingKeyIsItsOwnConditionAndNeverASignInPrompt() throws {
        var status = try Fixtures.status()
        status.account = AccountStatus(state: .signedOut, identity: nil, kind: .apiKey)
        XCTAssertEqual(ProductCondition(status: status), .apiKeyMissing)
        status.account.state = .expired
        XCTAssertEqual(ProductCondition(status: status), .apiKeyMissing)
        status.account.state = .signedIn
        XCTAssertNotEqual(ProductCondition(status: status), .apiKeyMissing)
        XCTAssertNotEqual(ProductCondition(status: status), .signedOut)
    }

    func testSetApiKeyEncodesTheKeyAsThePayload() throws {
        let data = try JSONEncoder().encode(RequestEnvelope(id: "request", action: .setApiKey("vck_example")))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["action"] as? String, "setApiKey")
        XCTAssertEqual(object["payload"] as? String, "vck_example")
    }
}
