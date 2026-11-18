import XCTest
@testable import AutocompleteHelper

final class ContextArtifactFreshnessTests: XCTestCase {
    func testEveryEphemeralKindUsesItsOriginalCaptureDeadline() {
        for (kind, lifetime) in [("selection", Int64(60_000)), ("recent_writing", 300_000),
                                 ("accepted_completion", 300_000), ("clipboard", 600_000)] {
            let artifact = SuggestionRequestMessage.Payload.Artifact(
                id: "synthetic", kind: kind, text: "Evidence", capturedAtMs: 1_000)
            XCTAssertTrue(ContextArtifactFreshness.isFresh(artifact, at: 1_000 + lifetime - 1), kind)
            XCTAssertFalse(ContextArtifactFreshness.isFresh(artifact, at: 1_000 + lifetime), kind)
            XCTAssertFalse(ContextArtifactFreshness.isFresh(artifact, at: 999), kind)
        }
    }

    func testUnknownOrInvalidCaptureTimesCannotGainAuthority() {
        for (kind, timestamp) in [("unknown", Int64(1)), ("saved", -1), ("clipboard", 10_000)] {
            let artifact = SuggestionRequestMessage.Payload.Artifact(
                id: "synthetic", kind: kind, text: "Evidence", capturedAtMs: timestamp)
            XCTAssertFalse(ContextArtifactFreshness.isFresh(artifact, at: 1_000))
        }
    }
}
