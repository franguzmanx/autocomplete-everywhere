import XCTest
@testable import AutocompleteHelper

final class HelperConfigurationTests: XCTestCase {
    func testConfigurationRejectsEveryReservedBindingForAcceptAndDismiss() {
        for key in [48, 125, 126, 18, 19, 20, 21, 23, 22, 26, 28, 25] {
            for action in ["acceptShortcut", "dismissShortcut"] {
                let other = action == "acceptShortcut" ? "dismissShortcut" : "acceptShortcut"
                let raw = #"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":[],"automaticSuggestions":true,"quietPeriodMs":300,"ghostAlpha":0.30,"\#(action)":{"keyCode":\#(key),"modifiers":2048},"\#(other)":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#
                XCTAssertNil(HelperCommandDecoder().decode(raw))
                XCTAssertNotNil(HelperCommandDecoder().decode(raw.replacingOccurrences(of: "2048", with: "2560")))
            }
        }
    }

    func testLearningFlagIsRequiredAndCannotOverridePause() {
        let raw = #"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":[],"automaticSuggestions":true,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":true}}"#
        XCTAssertEqual(HelperCommandDecoder().decode(raw), .configure(.init(isEnabled: true, clipboardContextEnabled: false, learningEnabled: true)))
        XCTAssertEqual(HelperCommandDecoder().decode(raw.replacingOccurrences(of: #""enabled":true"#, with: #""enabled":false"#)), .configure(.disabled))
        XCTAssertNil(HelperCommandDecoder().decode(raw.replacingOccurrences(of: #", "contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":true"#.replacingOccurrences(of: " ", with: ""), with: "")))
    }

    func testCustomInteractionBindingsMustBeSafeAndDistinct() {
        let raw = #"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":[],"automaticSuggestions":true,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":36,"modifiers":256},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#
        guard case let .configure(config) = HelperCommandDecoder().decode(raw) else { return XCTFail("Custom keys did not decode") }
        XCTAssertEqual(config.acceptShortcut, .init(keyCode:36,modifiers:256))
        XCTAssertNil(HelperCommandDecoder().decode(raw.replacingOccurrences(of: #""keyCode":36,"modifiers":256"#, with: #""keyCode":53,"modifiers":0"#)))
        XCTAssertNil(HelperCommandDecoder().decode(raw.replacingOccurrences(of: #""keyCode":36,"modifiers":256"#, with: #""keyCode":0,"modifiers":0"#)))
    }

    func testAppearanceAndTimingRequireValidNativeValues() {
        let raw = #"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":[],"automaticSuggestions":true,"quietPeriodMs":150,"ghostAlpha":0.45,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#
        XCTAssertEqual(HelperCommandDecoder().decode(raw), .configure(.init(isEnabled: true, clipboardContextEnabled: false, quietPeriodMs: 150, ghostAlpha: 0.45)))
        XCTAssertEqual(HelperCommandDecoder().decode(raw.replacingOccurrences(of: "150", with: "0")), .configure(.init(isEnabled: true, clipboardContextEnabled: false, quietPeriodMs: 0, ghostAlpha: 0.45)))
        XCTAssertNil(HelperCommandDecoder().decode(raw.replacingOccurrences(of: "150", with: "-1")))
        XCTAssertNil(HelperCommandDecoder().decode(raw.replacingOccurrences(of: "0.45", with: "1.5")))
    }

    func testEnablesTheGlobalWritingSurfaceCapability() {
        let decoder = HelperCommandDecoder()
        let command = decoder.decode(
            #"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":[],"automaticSuggestions":true,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":true,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#
        )

        XCTAssertEqual(
            command,
            .configure(.init(isEnabled: true, clipboardContextEnabled: true))
        )
    }

    func testRejectsPerApplicationCaptureListsInsteadOfTheCapabilitySwitch() {
        let decoder = HelperCommandDecoder()

        for applications in [
            #"["com.apple.Notes"]"#,
            #"["*","*"]"#,
            #"["com.google.Chrome","*"]"#,
        ] {
            XCTAssertNil(
                decoder.decode(
                    #"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"enabledApplications":\#(applications),"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#
                ),
                applications
            )
        }
    }

    func testDisabledFlagWinsOverTheCapabilitySwitch() {
        let decoder = HelperCommandDecoder()

        XCTAssertEqual(
            decoder.decode(
                #"{"protocolVersion":5,"type":"configure","payload":{"enabled":false,"excludedApplications":[],"automaticSuggestions":true,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":true,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#
            ),
            .configure(.disabled)
        )
    }

    func testExclusionsAreUserPreferencesAndDoNotDisableOtherApps() {
        let command = HelperCommandDecoder().decode(#"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":["com.apple.Notes"],"automaticSuggestions":false,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#)
        XCTAssertEqual(command, .configure(.init(isEnabled: true, clipboardContextEnabled: false, excludedApplications: ["com.apple.Notes"], automaticSuggestions: false)))
    }

    func testRejectsMalformedUnknownAndWrongVersionCommands() {
        let decoder = HelperCommandDecoder()

        XCTAssertNil(decoder.decode("not-json"))
        XCTAssertNil(
            decoder.decode(
                #"{"protocolVersion":1,"type":"configure","payload":{"enabled":true}}"#
            )
        )
        XCTAssertNil(
            decoder.decode(
                #"{"protocolVersion":5,"type":"capture_private_text","payload":{}}"#
            )
        )
    }

    func testDecodesSuggestionResponsesWithTheirExactIdentity() {
        let decoder = HelperCommandDecoder()
        let identity = #"{"requestId":"DA2F74CE-C1DA-4E2E-85C7-B6D3C4069B63","focusSequence":7,"contentSignature":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","timestampMs":1788000000000}"#

        XCTAssertNil(
            decoder.decode(
                #"{"protocolVersion":5,"type":"suggestion_partial","identity":\#(identity),"payload":{"sequence":1,"text":" te mando"}}"#
            )
        )
        XCTAssertEqual(
            decoder.decode(
                #"{"protocolVersion":5,"type":"suggestion_final","identity":\#(identity),"payload":{"text":" te mando hoy"}}"#
            ),
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: Self.identity,
                    result: .text(" te mando hoy")
                )
            )
        )
        XCTAssertEqual(
            decoder.decode(
                #"{"protocolVersion":5,"type":"request_failed","identity":\#(identity),"payload":{"code":"network","retryable":true}}"#
            ),
            .requestFailed(
                RequestFailedCommand(
                    identity: Self.identity,
                    code: .network,
                    retryable: true
                )
            )
        )
    }

    func testRejectsMalformedOrMismatchedSuggestionIdentities() {
        let decoder = HelperCommandDecoder()

        XCTAssertNil(
            decoder.decode(
                #"{"protocolVersion":5,"type":"suggestion_final","identity":{"requestId":"not-a-uuid","focusSequence":7,"contentSignature":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","timestampMs":1788000000000},"payload":{"text":"private fixture"}}"#
            )
        )
        XCTAssertNil(
            decoder.decode(
                #"{"protocolVersion":5,"type":"suggestion_final","identity":{"requestId":"DA2F74CE-C1DA-4E2E-85C7-B6D3C4069B63","focusSequence":7,"contentSignature":"too-short","timestampMs":1788000000000},"payload":{"text":"private fixture"}}"#
            )
        )
    }

    private static let identity = SuggestionRequestMessage.Identity(
        requestId: "DA2F74CE-C1DA-4E2E-85C7-B6D3C4069B63",
        focusSequence: 7,
        contentSignature: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        timestampMs: 1_788_000_000_000
    )
}
