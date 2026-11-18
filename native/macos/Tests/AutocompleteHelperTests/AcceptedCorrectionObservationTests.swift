import Foundation
import XCTest
@testable import AutocompleteHelper

final class AcceptedCorrectionObservationTests: XCTestCase {
    @MainActor
    func testNonASCIIPhysicalCorrectionRemainsAttributedAfterVerifiedCapture() {
        let harness = Harness()
        harness.seed()
        harness.clock = 1_000
        let monitor = KeyboardMonitor(sessionProvider: { .inactive }, actionHandler: { _ in false }, onUserEdit: { harness.observer.noteUserEdit(timestampMs: harness.clock) })
        let classifier = KeyboardInputCommitmentClassifier { .init(isASCIICapable: true, isNonComposingKeyboardLayout: true) }
        _ = monitor.process(.init(keyCode: 14, textInput: classifier.classify("é")), phase: .keyDown)
        XCTAssertTrue(harness.events.isEmpty)
        harness.current = .captured(snapshot("Intro. Verbosé reply", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        harness.expire()
        XCTAssertEqual(harness.outcomes, [.editedAfterAcceptance])
        XCTAssertEqual(harness.corrections.first?.payload.after, "Verbosé reply")
    }

    func testVerifiedCorrectionEmitsOnceAtDeadlineWithOriginalIdentity() throws {
        let harness = Harness()
        harness.seed()
        harness.clock = 1_000
        harness.observer.noteUserEdit(timestampMs: harness.clock)
        harness.current = .captured(snapshot("Intro. Clear reply", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: harness.clock)
        XCTAssertTrue(harness.events.isEmpty)
        harness.expire()
        XCTAssertEqual(harness.outcomes, [.editedAfterAcceptance])
        let correction = try XCTUnwrap(harness.corrections.first)
        XCTAssertEqual(correction.identity, harness.identity)
        XCTAssertEqual(correction.payload.before, "Verbose reply")
        XCTAssertEqual(correction.payload.after, "Clear reply")
        XCTAssertEqual(correction.payload.appId, "com.example.editor")
        XCTAssertEqual(correction.payload.observedAtMs, 30_000)
        harness.observer.observe(harness.current, timestampMs: 31_000)
        XCTAssertEqual(harness.corrections.count, 1)
    }

    func testUnchangedAcceptanceDoesNotBecomeStyleEvidence() {
        let harness = Harness()
        harness.seed()
        harness.expire()
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testRemovedAcceptedRangeEmitsRemovalWithoutSnippets() {
        let harness = Harness()
        harness.seed()
        harness.observer.noteUserEdit(timestampMs: 1_000)
        harness.current = .captured(snapshot("Intro. ", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        XCTAssertEqual(harness.outcomes, [.removedAfterAcceptance])
        XCTAssertTrue(harness.corrections.isEmpty)
        harness.expire()
        XCTAssertEqual(harness.outcomes.count, 1)
    }

    func testUnobservedOutsideAndAmbiguousEditsBecomeUnavailable() {
        for (text, authored) in [("Intro. Clear reply", false), ("Changed. Verbose reply", true), ("Intro. Verbose reply continued", true)] {
            let harness = Harness()
            harness.seed()
            if authored { harness.observer.noteUserEdit(timestampMs: 1_000) }
            harness.current = .captured(snapshot(text, sequence: 2))
            harness.observer.observe(harness.current, timestampMs: 1_001)
            harness.expire()
            XCTAssertEqual(harness.outcomes, [.observationUnavailable])
            XCTAssertTrue(harness.corrections.isEmpty)
        }
    }

    func testSecureLostFocusRangeAndWindowEndObservation() {
        let invalid: [ActiveFieldCaptureResult] = [
            .skipped(.secureField), .skipped(.markerReadFailed),
            .captured(snapshot("Intro. Verbose reply", focus: 2, sequence: 2)),
            .captured(snapshot("Intro. Verbose reply", offset: 10, sequence: 2)),
        ]
        for result in invalid {
            let harness = Harness()
            harness.seed()
            harness.current = result
            harness.observer.observe(result, timestampMs: 1_000)
            harness.expire()
            XCTAssertEqual(harness.outcomes, [.observationUnavailable])
            XCTAssertTrue(harness.corrections.isEmpty)
        }
    }

    func testDisabledAndExcludedLearningNeverRetainsASeed() {
        for configuration in [CaptureConfiguration.enabled, CaptureConfiguration(isEnabled: true, clipboardContextEnabled: false, learningEnabled: true, excludedApplications: ["com.example.editor"])] {
            let harness = Harness()
            harness.observer.updateConfiguration(configuration)
            harness.seed(configure: false)
            harness.observer.noteUserEdit(timestampMs: 1_000)
            harness.current = .captured(snapshot("Intro. Clear reply", sequence: 2))
            harness.observer.observe(harness.current, timestampMs: 1_001)
            XCTAssertTrue(harness.events.isEmpty)
            XCTAssertTrue(harness.scheduled.isEmpty)
        }
    }

    func testDisablePurgesChangedObservationBeforeDeadline() {
        let harness = Harness()
        harness.seed()
        harness.observer.noteUserEdit(timestampMs: 1_000)
        harness.current = .captured(snapshot("Intro. Clear reply", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        harness.observer.updateConfiguration(.disabled)
        harness.expire()
        XCTAssertEqual(harness.outcomes, [.observationUnavailable])
        XCTAssertTrue(harness.corrections.isEmpty)
    }

    func testExpiryRevalidatesAuthorityInsteadOfSendingStoredCorrection() {
        let harness = Harness()
        harness.seed()
        harness.observer.noteUserEdit(timestampMs: 1_000)
        harness.current = .captured(snapshot("Intro. Clear reply", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        harness.current = .skipped(.secureField)
        harness.expire()
        XCTAssertEqual(harness.outcomes, [.observationUnavailable])
        XCTAssertTrue(harness.corrections.isEmpty)
    }

    func testOversizedAndLateCorrectionsAreUnavailable() {
        for (value, editAt, observedAt) in [
            ("Intro. " + String(repeating: "x", count: 2_001), Int64(1_000), Int64(1_001)),
            ("Intro. Clear reply", Int64(1_000), Int64(2_001)),
            ("Intro. Clear reply", Int64(29_900), Int64(30_001)),
        ] {
            let harness = Harness()
            harness.seed()
            harness.observer.noteUserEdit(timestampMs: editAt)
            harness.current = .captured(snapshot(value, sequence: 2))
            harness.observer.observe(harness.current, timestampMs: observedAt)
            XCTAssertEqual(harness.outcomes, [.observationUnavailable])
            XCTAssertTrue(harness.corrections.isEmpty)
        }
    }

    func testOverlongAcceptanceIsNotTruncatedIntoEvidence() {
        let harness = Harness()
        harness.observer.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false, learningEnabled: true))
        let text = String(repeating: "x", count: 2_001)
        harness.observer.recordAcceptance(identity: harness.identity, text: text, snapshot: snapshot(text), timestampMs: 0)
        XCTAssertEqual(harness.outcomes, [.observationUnavailable])
        XCTAssertTrue(harness.scheduled.isEmpty)
    }

    func testUnicodeCorrectionsPreserveExactSnippet() throws {
        let harness = Harness()
        harness.current = .captured(snapshot("Intro. 🚀 明日の予定"))
        harness.seed(text: "🚀 明日の予定")
        harness.observer.noteUserEdit(timestampMs: 1_000)
        harness.current = .captured(snapshot("Intro. 🌙 明日の計画", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        harness.expire()
        let correction = try XCTUnwrap(harness.corrections.first)
        XCTAssertEqual(correction.payload.before, "🚀 明日の予定")
        XCTAssertEqual(correction.payload.after, "🌙 明日の計画")
    }

    func testCorrectionRestoredToAcceptedTextIsNotEvidence() {
        let harness = Harness()
        harness.seed()
        harness.observer.noteUserEdit(timestampMs: 1_000)
        harness.current = .captured(snapshot("Intro. Clear reply", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        harness.observer.noteUserEdit(timestampMs: 2_000)
        harness.current = .captured(snapshot("Intro. Verbose reply", sequence: 3))
        harness.observer.observe(harness.current, timestampMs: 2_001)
        harness.expire()
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testRepeatedTextDeletionCannotBeAttributedToInsideRange() {
        let harness = Harness()
        harness.current = .captured(snapshot("aa"))
        harness.seed(text: "a")
        harness.observer.noteUserEdit(timestampMs: 1_000)
        harness.current = .captured(snapshot("a", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        XCTAssertEqual(harness.outcomes, [.observationUnavailable])
        XCTAssertTrue(harness.corrections.isEmpty)
    }

    func testRepeatedAcceptanceCannotRestartOrDuplicateItsObservation() {
        let harness = Harness()
        harness.seed()
        harness.observer.noteUserEdit(timestampMs: 1_000)
        harness.current = .captured(snapshot("Intro. Clear reply", sequence: 2))
        harness.observer.observe(harness.current, timestampMs: 1_001)
        harness.expire()
        harness.current = .captured(snapshot("Intro. Verbose reply", sequence: 3))
        harness.seed()
        XCTAssertTrue(harness.scheduled.isEmpty)
        XCTAssertEqual(harness.corrections.count, 1)
    }

    func testDelayedSeedCannotExtendThirtySecondRetention() {
        let harness = Harness()
        harness.clock = 1_000
        harness.observer.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false, learningEnabled: true))
        harness.observer.recordAcceptance(identity: harness.identity, text: "Verbose reply", snapshot: snapshot("Intro. Verbose reply"), timestampMs: 0)
        XCTAssertEqual(harness.delays, [29])
        let expired = Harness()
        expired.clock = 30_001
        expired.observer.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false, learningEnabled: true))
        expired.observer.recordAcceptance(identity: expired.identity, text: "Verbose reply", snapshot: snapshot("Intro. Verbose reply"), timestampMs: 0)
        XCTAssertEqual(expired.outcomes, [.observationUnavailable])
        XCTAssertTrue(expired.scheduled.isEmpty)
    }

    func testWritingSessionChangesAfterThirtyMinutesOfAuthoredInactivity() throws {
        let harness = Harness()
        var sessionIDs: [String] = []
        for start in [Int64(0), 31_000, 1_900_000] {
            harness.clock = start
            harness.identity = .init(requestId: UUID().uuidString, focusSequence: 1, contentSignature: String(repeating: "a", count: 64), timestampMs: start)
            harness.current = .captured(snapshot("Intro. Verbose reply"))
            harness.seed()
            harness.observer.noteUserEdit(timestampMs: start + 1_000)
            harness.current = .captured(snapshot("Intro. Clear reply", sequence: 2))
            harness.observer.observe(harness.current, timestampMs: start + 1_001)
            harness.expire(at: start + 30_000)
            sessionIDs.append(try XCTUnwrap(harness.corrections.last?.payload.sessionId))
        }
        XCTAssertEqual(sessionIDs[0], sessionIDs[1])
        XCTAssertNotEqual(sessionIDs[1], sessionIDs[2])
    }

    private func snapshot(_ value: String, focus: UInt64 = 1, offset: Int = 0, sequence: UInt64 = 1) -> ActiveFieldSnapshot {
        Self.snapshot(value, focus: focus, offset: offset, sequence: sequence)
    }

    private static func snapshot(_ value: String, focus: UInt64 = 1, offset: Int = 0, sequence: UInt64 = 1) -> ActiveFieldSnapshot {
        .init(applicationBundleIdentifier: "com.example.editor", elementIdentifier: "field", focusGeneration: focus,
              textBefore: value, selectedText: "", textAfter: "", selectionRange: NSRange(location: offset + value.utf16.count, length: 0),
              caretBounds: nil, geometryQuality: .unavailable, captureSequence: sequence)
    }

    private final class Harness: @unchecked Sendable {
        var clock: Int64 = 0
        var current: ActiveFieldCaptureResult = .captured(AcceptedCorrectionObservationTests.snapshot("Intro. Verbose reply"))
        var events: [AcceptedCorrectionObservation.Event] = []
        var scheduled: [@Sendable () -> Void] = []
        var delays: [TimeInterval] = []
        var identity = SuggestionRequestMessage.Identity(requestId: UUID().uuidString, focusSequence: 1, contentSignature: String(repeating: "a", count: 64), timestampMs: 0)
        lazy var observer = AcceptedCorrectionObservation(
            now: { [unowned self] in self.clock }, capture: { [unowned self] in self.current },
            scheduleExpiry: { [unowned self] delay, work in self.delays.append(delay); self.scheduled.append(work) },
            emit: { [unowned self] in self.events.append($0) }
        )
        var outcomes: [InteractionOutcome] { events.compactMap { if case let .interaction(_, outcome) = $0 { return outcome }; return nil } }
        var corrections: [CorrectionObservedMessage] { events.compactMap { if case let .correction(message) = $0 { return message }; return nil } }
        func seed(configure: Bool = true, text: String = "Verbose reply") {
            if configure { observer.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false, learningEnabled: true)) }
            guard case let .captured(snapshot) = current else { return }
            observer.recordAcceptance(identity: identity, text: text, snapshot: snapshot, timestampMs: clock)
        }
        func expire(at timestampMs: Int64 = 30_000) {
            clock = timestampMs
            let work = scheduled
            scheduled = []
            work.forEach { $0() }
        }
    }
}
