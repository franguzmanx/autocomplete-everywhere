import Foundation
import XCTest
@testable import AutocompleteHelper

final class SuggestionControllerTests: XCTestCase {
    @MainActor
    func testContextInvalidationDismissesAffectedSuggestionAndRejectsLateResult() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        Self.makeReady(controller, current: current, writer: writer, text: "grounded completion")
        let identity = writer.requests[0].identity
        controller.handle(.contextInvalidate([UUID().uuidString]))
        XCTAssertEqual(presenter.visibleText, "grounded completion")
        controller.handle(.contextInvalidate([identity.requestId]))
        XCTAssertNil(presenter.visibleText)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text("stale completion"))))
        XCTAssertNil(presenter.visibleText)
    }

    @MainActor
    func testClickInFieldActivatesAfterPassiveDiscovery() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) },
            presenter: ControllerPresenter(), writer: writer, userInteraction: false)
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        controller.monitor.poll(at: 0.4)
        XCTAssertTrue(writer.requests.isEmpty)
        controller.notePointerInput(at: CGPoint(x: 100, y: 100))
        _ = controller.handle(.hostStateChanged)
        current.value = Self.snapshot(text: "Prueba:", x: 100, sequence: 2)
        controller.monitor.poll(at: 0.5)
        controller.monitor.poll(at: 0.9)
        XCTAssertEqual(writer.requests.count, 1)
    }

    @MainActor
    func testFocusDiscoveryDoesNotGenerateUntilUserTypes() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) },
            presenter: ControllerPresenter(), writer: writer, userInteraction: false)
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = Self.snapshot(text: "Prueba:", x: 100, sequence: 2)
        controller.monitor.poll(at: 0.4)
        XCTAssertTrue(writer.requests.isEmpty)
        controller.noteUserEdit()
        _ = controller.handle(.hostText("a"))
        current.value = Self.snapshot(text: "Prueba:a", x: 108, sequence: 3)
        controller.monitor.poll(at: 0.5)
        current.value = Self.snapshot(text: "Prueba:a", x: 108, sequence: 4)
        controller.monitor.poll(at: 0.9)
        XCTAssertEqual(writer.requests.count, 1)
    }

    @MainActor
    func testExpiredAlternativeContextStartsFreshCaptureWithoutOldCandidates() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let clock = ControllerCooldownClock()
        var collections = 0
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer,
            cooldownClock: clock, contextArtifacts: { _, timestamp in
                collections += 1
                return [.init(id: "source", kind: "recent_writing", text: "Grounding", capturedAtMs: timestamp)]
            })
        Self.makeReady(controller, current: current, writer: writer, text: "first version")
        let originalTimestamp = writer.requests[0].payload.artifacts[0].capturedAtMs
        clock.now += 301
        XCTAssertTrue(controller.handle(.nextAlternative))
        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(writer.requests.count, 1, "Do not transmit the expired request or its candidates")
        for (sequence, time) in [(UInt64(4), 0.4), (5, 0.5), (6, 0.8)] {
            current.value = Self.snapshot(text: "Prueba:", x: 100, sequence: sequence)
            controller.monitor.poll(at: time)
        }
        XCTAssertEqual(collections, 2)
        XCTAssertEqual(writer.requests.count, 2)
        XCTAssertNil(writer.requests.last!.payload.alternativeTo)
        XCTAssertGreaterThan(writer.requests.last!.payload.artifacts[0].capturedAtMs, originalTimestamp)
    }

    @MainActor
    func testContextExpiringDuringGenerationRejectsNormalAndAlternativeReplies() {
        for alternative in [false, true] {
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let presenter = ControllerPresenter()
            let writer = ControllerWriter()
            let clock = ControllerCooldownClock()
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer,
                cooldownClock: clock, contextArtifacts: { _, timestamp in
                    [.init(id: "source", kind: "selection", text: "Grounding", capturedAtMs: timestamp)]
                })
            Self.makeReady(controller, current: current, writer: writer, text: "first version")
            if alternative { XCTAssertTrue(controller.handle(.nextAlternative)) }
            else { controller.handle(.requestSuggestion)
                for (sequence, time) in [(UInt64(4), 0.4), (5, 0.5), (6, 0.8)] {
                    current.value = Self.snapshot(text: "Prueba:", x: 100, sequence: sequence)
                    controller.monitor.poll(at: time)
                }
            }
            let pending = writer.requests.last!.identity
            clock.now += 61
            controller.handle(.suggestionFinal(.init(identity: pending, result: .text("late text"))))
            XCTAssertNil(presenter.visibleText)
            XCTAssertNil(controller.currentIdentity)
            XCTAssertFalse(controller.handle(.previousAlternative))
        }
    }

    @MainActor
    func testFittedDuplicateAlternativeDoesNotReportAnotherShownVersion() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        Self.makeReady(controller, current: current, writer: writer, text: "first version")
        let original = controller.currentIdentity
        XCTAssertTrue(controller.handle(.nextAlternative))
        presenter.fittedText = "first version"
        controller.handle(.suggestionFinal(.init(identity: writer.requests.last!.identity, result: .text("first version with more detail"))))
        XCTAssertEqual(controller.currentIdentity, original)
        XCTAssertEqual(presenter.visibleText, "first version")
        XCTAssertEqual(writer.interactions.filter { $0.0 == .shown }.count, 1)
        XCTAssertTrue(controller.handle(.previousAlternative))
        XCTAssertEqual(controller.currentIdentity, original)
    }

    @MainActor
    func testTypeThroughPreservesOriginalGroundingForAlternativeSuffix() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let artifact = SuggestionRequestMessage.Payload.Artifact(id: "source", kind: "recent_writing", text: "Grounded context", capturedAtMs: Int64(Date().timeIntervalSince1970 * 1_000))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer,
            contextArtifacts: { _, _ in [artifact] })
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertFalse(controller.handle(.hostText("f")))
        current.value = Self.snapshot(text: "Prueba:f", x: 109, sequence: 4)
        controller.monitor.poll(at: 0.31)
        current.value = Self.snapshot(text: "Prueba:f", x: 109, sequence: 5)
        controller.monitor.poll(at: 0.32)
        XCTAssertEqual(presenter.visibleText, "unciona")
        XCTAssertTrue(controller.handle(.nextAlternative))
        XCTAssertEqual(writer.requests.last!.payload.artifacts, [artifact])
        XCTAssertEqual(writer.requests.last!.payload.alternativeTo, ["unciona"])
    }

    @MainActor
    func testWordAcceptanceStartsFreshHistoryAtTheRemainingSuffix() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let inserter = ControllerInserter()
        inserter.insertResult = { text, prepared in
            current.value = Self.snapshot(text: prepared.expectedSnapshot.textBefore + text, x: 180,
                sequence: prepared.expectedSnapshot.captureSequence + 1)
            return .inserted(method: .accessibility, snapshot: current.value)
        }
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, inserter: inserter, writer: writer)
        Self.makeReady(controller, current: current, writer: writer, text: "first version")
        XCTAssertTrue(controller.handle(.nextAlternative))
        controller.handle(.suggestionFinal(.init(identity: writer.requests.last!.identity, result: .text("second version"))))
        XCTAssertTrue(controller.handle(.acceptNextWord))
        XCTAssertEqual(inserter.insertedTexts, ["second "])
        current.value = Self.snapshot(text: current.value.textBefore, x: 180, sequence: 5)
        controller.monitor.poll(at: 0.4)
        current.value = Self.snapshot(text: current.value.textBefore, x: 180, sequence: 6)
        controller.monitor.poll(at: 0.5)
        XCTAssertEqual(presenter.visibleText, "version")
        XCTAssertTrue(controller.handle(.previousAlternative))
        XCTAssertEqual(presenter.visibleText, "version")
        XCTAssertTrue(controller.handle(.nextAlternative))
        XCTAssertEqual(writer.requests.last!.payload.alternativeTo, ["version"])
        XCTAssertEqual(writer.requests.last!.payload.textBefore, "Prueba:second ")
    }

    @MainActor
    func testPendingAlternativeCancelledByTypingFocusExclusionDisableDismissAndAcceptance() {
        for boundary in ["typing", "focus", "source", "exclude", "disable", "dismiss", "accept", "word"] {
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let presenter = ControllerPresenter()
            let writer = ControllerWriter()
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
            Self.makeReady(controller, current: current, writer: writer, text: "first version")
            XCTAssertTrue(controller.handle(.nextAlternative))
            let pending = writer.requests.last!.identity
            switch boundary {
            case "typing": _ = controller.handle(.hostText("x"))
            case "focus":
                current.value = Self.snapshot(text: "Other", x: 120, sequence: 4, focusGeneration: 2)
                controller.monitor.poll(at: 0.4)
            case "source":
                current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 4,
                    fieldContext: .init(shape: .multiline, sources: [
                        .init(id: "other", containerId: "chat", relation: .sharedContainer, text: "New message")
                    ]))
                controller.monitor.poll(at: 0.4)
            case "exclude": controller.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false, excludedApplications: ["com.apple.Notes"]))
            case "disable": controller.updateConfiguration(.disabled)
            case "dismiss": XCTAssertTrue(controller.handle(.dismissSuggestion))
            case "accept": XCTAssertTrue(controller.handle(.acceptSuggestion))
            default: XCTAssertTrue(controller.handle(.acceptNextWord))
            }
            XCTAssertTrue(writer.cancellations.contains { $0.identity == pending }, boundary)
            controller.handle(.suggestionFinal(.init(identity: pending, result: .text("late alternative"))))
            XCTAssertNotEqual(presenter.visibleText, "late alternative", boundary)
            XCTAssertFalse(controller.handle(.previousAlternative), boundary)
        }
    }

    @MainActor
    func testAlternativesKeepCurrentDuringLatencyAndNavigateCachedIdentity() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        Self.makeReady(controller, current: current, writer: writer, text: "first version")
        let first = controller.currentIdentity
        XCTAssertTrue(controller.handle(.previousAlternative))
        XCTAssertEqual(writer.requests.count, 1)
        XCTAssertTrue(controller.handle(.nextAlternative))
        XCTAssertEqual(presenter.visibleText, "first version")
        XCTAssertEqual(controller.keyboardStatus(), .ready)
        XCTAssertEqual(writer.requests.last?.payload.alternativeTo, ["first version"])
        XCTAssertTrue(writer.requests.last!.payload.explicit)
        XCTAssertNotEqual(writer.requests.last?.identity, first)
        XCTAssertTrue(controller.handle(.nextAlternative))
        XCTAssertEqual(writer.requests.count, 2)
        let second = writer.requests.last!.identity
        controller.handle(.suggestionFinal(.init(identity: second, result: .text("second version"))))
        XCTAssertEqual(presenter.visibleText, "second version")
        XCTAssertTrue(controller.handle(.previousAlternative))
        XCTAssertEqual(controller.currentIdentity, first)
        XCTAssertEqual(presenter.visibleText, "first version")
        XCTAssertTrue(controller.handle(.nextAlternative))
        XCTAssertEqual(controller.currentIdentity, second)
        XCTAssertEqual(writer.requests.count, 2)
        XCTAssertEqual(writer.interactions.filter { $0.0 == .shown }.count, 2)
    }

    @MainActor
    func testAlternativeFailureSilenceDuplicateAndLateResponsePreserveSelection() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        Self.makeReady(controller, current: current, writer: writer, text: "first version")
        let results: [SuggestionFinalResult] = [.silence("no_alternative"), .text("first version"), .text("")]
        for result in results {
            XCTAssertTrue(controller.handle(.nextAlternative))
            controller.handle(.suggestionFinal(.init(identity: writer.requests.last!.identity, result: result)))
            XCTAssertEqual(presenter.visibleText, "first version")
        }
        XCTAssertTrue(controller.handle(.nextAlternative))
        controller.handle(.requestFailed(.init(identity: writer.requests.last!.identity, code: .network, retryable: true)))
        XCTAssertEqual(presenter.visibleText, "first version")
        XCTAssertTrue(controller.handle(.nextAlternative))
        let pending = writer.requests.last!.identity
        XCTAssertTrue(controller.handle(.previousAlternative))
        XCTAssertEqual(writer.cancellations.last?.identity, pending)
        controller.handle(.suggestionFinal(.init(identity: pending, result: .text("late version"))))
        XCTAssertEqual(presenter.visibleText, "first version")
    }

    @MainActor
    func testAlternativesAreBoundedAndInputClearsPendingHistory() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        Self.makeReady(controller, current: current, writer: writer, text: "version 0")
        for index in 1...7 {
            XCTAssertTrue(controller.handle(.nextAlternative))
            XCTAssertLessThanOrEqual(writer.requests.last!.payload.alternativeTo!.count, 5)
            controller.handle(.suggestionFinal(.init(identity: writer.requests.last!.identity, result: .text("version \(index)"))))
        }
        for _ in 0..<8 { XCTAssertTrue(controller.handle(.previousAlternative)) }
        XCTAssertEqual(presenter.visibleText, "version 3")
        for _ in 0..<4 { XCTAssertTrue(controller.handle(.nextAlternative)) }
        XCTAssertTrue(controller.handle(.nextAlternative))
        let pending = writer.requests.last!.identity
        XCTAssertFalse(controller.handle(.hostStateChanged))
        XCTAssertTrue(writer.cancellations.contains { $0.identity == pending })
        controller.handle(.suggestionFinal(.init(identity: pending, result: .text("stale"))))
        XCTAssertNil(presenter.visibleText)
        XCTAssertFalse(controller.handle(.previousAlternative))
    }

    @MainActor
    func testInstantEditStartsReplacementWithoutInvalidatingItsNewRequest() throws {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Hello", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let presenter = ControllerPresenter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        var configuration = CaptureConfiguration.enabled
        configuration.quietPeriodMs = 0
        controller.updateConfiguration(configuration)
        controller.monitor.poll(at: 0)
        XCTAssertEqual(writer.requests.count, 1)
        current.value = Self.snapshot(text: "Hello there", x: 110, sequence: 2)
        controller.monitor.poll(at: 0.01)
        XCTAssertEqual(writer.requests.count, 2)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        current.value = Self.snapshot(text: "Hello there", x: 110, sequence: 3)
        controller.monitor.poll(at: 0.02)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text(" friend"))))
        XCTAssertEqual(presenter.visibleText, " friend")
        XCTAssertEqual(writer.requests.count, 2)
    }

    @MainActor
    func testDisablingBeforeDeferredWordInsertionPreventsTheWrite() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let inserter = ControllerInserter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter,
            inserter: inserter, writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer, text: "funciona muy bien")
        background.runNext() // Complete the off-main insertion capability check.
        XCTAssertTrue(controller.handle(.acceptNextWord))
        controller.updateConfiguration(.disabled)
        background.runNext()
        XCTAssertEqual(inserter.prepareCount, 1)
        XCTAssertEqual(inserter.insertCount, 0)
        XCTAssertEqual(controller.sessionState, .idle)
        XCTAssertNil(presenter.visibleText)
    }

    @MainActor
    func testOptionTabInsertsOneWordThenReanchorsRemainderWithoutRegeneration() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let inserter = ControllerInserter()
        inserter.insertResult = { text, prepared in
            current.value = Self.snapshot(text: prepared.expectedSnapshot.textBefore + text, x: 180, sequence: prepared.expectedSnapshot.captureSequence + 1)
            return .inserted(method: .accessibility, snapshot: current.value)
        }
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter,
            inserter: inserter, writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer, text: "funciona muy bien")
        background.runNext() // Complete the off-main insertion capability check.

        XCTAssertTrue(controller.handle(.acceptNextWord))
        XCTAssertFalse(controller.handle(.acceptNextWord), "Do not queue presses during insertion")
        XCTAssertNil(presenter.visibleText)
        background.runNext()
        XCTAssertEqual(inserter.insertedTexts, ["funciona "])
        XCTAssertEqual(current.value.textBefore, "Prueba:funciona ")
        // Reacquire actual caret geometry after the host has inserted the word.
        current.value = Self.snapshot(text: current.value.textBefore, x: 180, sequence: 5)
        controller.monitor.poll(at: 0.4)
        XCTAssertNil(presenter.visibleText, "One fresh caret sample cannot corroborate the remainder")
        XCTAssertFalse(controller.handle(.acceptNextWord))
        current.value = Self.snapshot(text: current.value.textBefore, x: 180, sequence: 6)
        controller.monitor.poll(at: 0.5)
        background.runNext() // Revalidate insertion capability for the remaining suffix.
        XCTAssertEqual(presenter.visibleText, "muy bien")
        XCTAssertEqual(controller.keyboardStatus(), .ready)
        XCTAssertEqual(writer.requests.count, 1)
        XCTAssertEqual(writer.interactions.filter { $0.0 == .shown }.count, 1)

        XCTAssertTrue(controller.handle(.acceptSuggestion))
        background.runNext()
        XCTAssertEqual(inserter.insertedTexts, ["funciona ", "muy bien"])
        XCTAssertEqual(controller.sessionState, .idle)
        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(writer.interactions.filter { $0.0 == .acceptedPartial }.map { $0.1 }, [9, 8])
    }

    @MainActor
    func testEscapeAfterWordAcceptanceDiscardsOnlyTheRemainder() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let inserter = ControllerInserter()
        inserter.insertResult = { text, prepared in
            current.value = Self.snapshot(text: prepared.expectedSnapshot.textBefore + text, x: 180, sequence: prepared.expectedSnapshot.captureSequence + 1)
            return .inserted(method: .accessibility, snapshot: current.value)
        }
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter,
            inserter: inserter, writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer, text: "funciona muy bien")
        background.runNext() // Complete the off-main insertion capability check.
        XCTAssertTrue(controller.handle(.acceptNextWord))
        background.runNext()
        current.value = Self.snapshot(text: current.value.textBefore, x: 180, sequence: 5)
        controller.monitor.poll(at: 0.4)
        XCTAssertNil(presenter.visibleText, "One fresh caret sample cannot corroborate the remainder")
        XCTAssertFalse(controller.handle(.acceptNextWord))
        current.value = Self.snapshot(text: current.value.textBefore, x: 180, sequence: 6)
        controller.monitor.poll(at: 0.5)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        XCTAssertEqual(current.value.textBefore, "Prueba:funciona ")
        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(controller.sessionState, .idle)
    }

    @MainActor
    func testFailedWordInsertionDoesNotRestoreRemainder() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter,
            writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer, text: "funciona muy bien")
        background.runNext() // Complete the off-main insertion capability check.
        XCTAssertTrue(controller.handle(.acceptNextWord))
        background.runNext()
        XCTAssertEqual(current.value.textBefore, "Prueba:")
        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(controller.sessionState, .idle)
    }

    @MainActor
    func testFinalWithoutInitialAnchorAppearsWhenFirstGeometryArrives() throws {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Yes", x: 100, sequence: 1, hasGeometry: false))
        let writer = ControllerWriter()
        let presenter = ControllerPresenter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text(", that works."))))
        XCTAssertNil(presenter.visibleIdentity)
        current.value = Self.snapshot(text: "Yes", x: 100, sequence: 2)
        controller.monitor.poll(at: 0.4)
        current.value = Self.snapshot(text: "Yes", x: 100, sequence: 3)
        controller.monitor.poll(at: 0.7)
        XCTAssertEqual(presenter.visibleIdentity, identity)
        XCTAssertEqual(presenter.visibleText, ", that works.")
        XCTAssertEqual(writer.requests.count, 1)
    }

    @MainActor
    func testFirstAnchorCannotReviveInvalidatedOrChangedSourceFinal() throws {
        for boundary in ["source", "dismiss", "pause", "edit", "focus"] {
            func snapshot(_ sequence: UInt64, geometry: Bool) -> ActiveFieldSnapshot {
                Self.snapshot(text: geometry && boundary == "edit" ? "No" : "Yes", x: 100,
                    sequence: sequence, focusGeneration: geometry && boundary == "focus" ? 2 : 1,
                    hasGeometry: geometry, fieldContext: .init(shape: .multiline, sources: [
                        .init(id: "message", containerId: "chat", relation: .sharedContainer,
                              text: geometry && boundary == "source" ? "Friday" : "Tuesday")
                    ]))
            }
            let current = ControllerSnapshotBox(snapshot(1, geometry: false))
            let writer = ControllerWriter()
            let presenter = ControllerPresenter()
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
            controller.updateConfiguration(.enabled)
            controller.monitor.poll(at: 0)
            controller.monitor.poll(at: 0.3)
            let identity = try XCTUnwrap(writer.requests.last?.identity)
            controller.handle(.suggestionFinal(.init(identity: identity, result: .text(", Tuesday works."))))
            if boundary == "dismiss" {
                XCTAssertFalse(controller.handle(.dismissSuggestion))
                XCTAssertTrue(writer.outcomes.isEmpty)
            }
            if boundary == "pause" { controller.updateConfiguration(.disabled) }
            current.value = snapshot(2, geometry: true)
            controller.monitor.poll(at: 0.4)
            current.value = snapshot(3, geometry: true)
            controller.monitor.poll(at: 0.7)
            current.value = snapshot(4, geometry: true)
            controller.monitor.poll(at: 1.1)
            current.value = snapshot(5, geometry: true)
            controller.monitor.poll(at: 1.5)
            XCTAssertNil(presenter.visibleIdentity, boundary)
            XCTAssertEqual(presenter.presentCount, 0, boundary)
            if boundary == "source" {
                XCTAssertEqual(writer.requests.count, 2)
                XCTAssertEqual(writer.requests.last?.payload.fieldContext.sources.first?.text, "Friday")
                let replacement = try XCTUnwrap(writer.requests.last?.identity)
                controller.handle(.suggestionFinal(.init(identity: replacement, result: .text(", Friday works."))))
                XCTAssertEqual(presenter.visibleText, ", Friday works.")
            }
        }
    }

    @MainActor
    func testSourceRecoveryWaitsForSettledEvidenceAndHonorsManualBoundaries() throws {
        try assertSourceRecoveryBoundaries(result: .text(", Tuesday works."))
    }

    @MainActor
    func testStaleSilenceRecoversWithTheSameManualBoundaries() throws {
        try assertSourceRecoveryBoundaries(result: .silence("no_useful_continuation"))
    }

    @MainActor
    private func assertSourceRecoveryBoundaries(result: SuggestionFinalResult) throws {
        for ending in ["recover", "dismiss", "pause", "edit", "target"] {
            func snapshot(_ body: String, _ sequence: UInt64, draft: String = "Yes") -> ActiveFieldSnapshot {
                Self.snapshot(text: draft, x: 100, sequence: sequence, fieldContext: .init(shape: .multiline,
                    sources: [.init(id: ending == "target" && sequence >= 5 ? "another-message" : "message",
                        containerId: "chat", relation: .sharedContainer, text: body)]))
            }
            let current = ControllerSnapshotBox(snapshot("Tuesday", 1))
            let writer = ControllerWriter()
            let lines = ControllerTimelineLines()
            let tracer = HelperTimelineTracer(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
                dispatch: { $0() }, sink: { lines.append($0) })
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, timeline: tracer)
            let decoder = HelperCommandDecoder()
            let command = try XCTUnwrap(decoder.decode(#"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":[],"automaticSuggestions":false,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#))
            guard case let .configure(config) = command else { return XCTFail("configuration") }
            controller.updateConfiguration(config)
            controller.handle(.requestSuggestion)
            controller.monitor.poll(at: 0)
            current.value = snapshot("Tuesday", 2)
            controller.monitor.poll(at: 0.3)
            let identity = try XCTUnwrap(writer.requests.last?.identity)
            current.value = snapshot("Friday", 3)
            controller.monitor.poll(at: 0.4)
            controller.handle(.suggestionFinal(.init(identity: identity, result: result)))
            let events = try lines.values.map(Self.decodeTimeline)
            let received = try XCTUnwrap(events.last { ($0["event"] as? String) == "final_received" })
            XCTAssertEqual((received["attrs"] as? [String: Any])?["disposition"] as? String, "rejected_current")
            if case .silence = result {
                XCTAssertFalse(events.contains { ($0["event"] as? String) == "present_rejected" },
                    "Stale silence is a response rejection, not a failed drawing attempt")
            }

            current.value = snapshot("Friday afternoon", 4)
            controller.monitor.poll(at: 0.5)
            if ending == "dismiss" { _ = controller.handle(.dismissSuggestion) }
            if ending == "pause" { controller.updateConfiguration(.disabled) }
            current.value = snapshot("Friday evening", 5, draft: ending == "edit" ? "Actually" : "Yes")
            controller.monitor.poll(at: 0.7)
            controller.monitor.poll(at: 0.85)
            XCTAssertEqual(writer.requests.count, 1, "Do not generate while source is updating")
            controller.monitor.poll(at: 1.1)
            controller.monitor.poll(at: 2)
            XCTAssertEqual(writer.requests.count, ending == "recover" ? 2 : 1, ending)
            if ending == "recover" {
                XCTAssertEqual(writer.requests.last?.payload.explicit, true)
            }
        }
    }

    @MainActor
    func testChangedSourceIsNotMisreportedAsMissingCursorGeometry() throws {
        let lines = ControllerTimelineLines()
        let tracer = HelperTimelineTracer(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            dispatch: { $0() }, sink: { lines.append($0) })
        func snapshot(_ body: String, _ sequence: UInt64) -> ActiveFieldSnapshot {
            Self.snapshot(text: "Yes", x: sequence >= 4 ? 102 : 100, sequence: sequence, fieldContext: .init(shape: .multiline,
                sources: [.init(id: "message", containerId: "chat", relation: .sharedContainer, text: body)]))
        }
        let current = ControllerSnapshotBox(snapshot("Delivery Tuesday", 1))
        let writer = ControllerWriter()
        let presenter = ControllerPresenter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter,
            writer: writer, timeline: tracer)
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = snapshot("Delivery Tuesday", 2)
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        current.value = snapshot("Correction: Friday", 3)
        controller.monitor.poll(at: 0.4)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text(", Tuesday works."))))
        XCTAssertNil(presenter.visibleText)
        let events = try lines.values.map(Self.decodeTimeline)
        let rejected = try XCTUnwrap(events.last { ($0["event"] as? String) == "present_rejected" })
        let attrs = try XCTUnwrap(rejected["attrs"] as? [String: Any])
        XCTAssertEqual(attrs["rejection"] as? String, "source_changed")
        current.value = snapshot("Correction: Friday", 4)
        controller.monitor.poll(at: 0.7)
        current.value = snapshot("Correction: Friday", 5)
        controller.monitor.poll(at: 1.0)
        XCTAssertNil(presenter.visibleText, "Geometry refresh must not revive a response to superseded source text")
        current.value = snapshot("Correction: Friday", 6)
        controller.monitor.poll(at: 12.0)
        XCTAssertEqual(writer.requests.count, 2, "A source-invalidated final needs a fresh request after the new source settles")
        let replacement = try XCTUnwrap(writer.requests.last?.identity)
        XCTAssertNotEqual(identity.requestId, replacement.requestId)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text(", Tuesday works."))))
        XCTAssertNil(presenter.visibleText, "A late obsolete final cannot return")
        controller.handle(.suggestionFinal(.init(identity: replacement, result: .text(", Friday works."))))
        XCTAssertEqual(presenter.visibleText, ", Friday works.")



    }

    @MainActor
    func testFittedFinalNeverAcceptsOrRevivesItsInvisibleRemainder() throws {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Reply", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let inserter = ControllerInserter()
        let presenter = ControllerPresenter()
        presenter.fittedText = " first line"
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter,
            inserter: inserter, writer: writer)
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = Self.snapshot(text: "Reply", x: 100, sequence: 2)
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text(" first line\nnot visible"))))
        XCTAssertEqual(presenter.visibleText, " first line")
        _ = controller.handle(.hostGeometryDisturbed)
        current.value = Self.snapshot(text: "Reply", x: 102, sequence: 3)
        controller.monitor.poll(at: 0.5)
        current.value = Self.snapshot(text: "Reply", x: 102, sequence: 4)
        controller.monitor.poll(at: 0.8)
        XCTAssertEqual(presenter.visibleText, " first line")
        XCTAssertEqual(presenter.fittingFlags.last, false)
        XCTAssertTrue(controller.attemptAcceptance())
        XCTAssertEqual(inserter.insertedTexts, [" first line"])
        XCTAssertFalse(controller.attemptAcceptance())
        XCTAssertEqual(inserter.insertCount, 1)
    }

    @MainActor
    func testDeliberateSilenceDoesNotReportPresentationFailure() throws {
        let lines = ControllerTimelineLines()
        let tracer = HelperTimelineTracer(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            dispatch: { $0() }, sink: { lines.append($0) })
        let current = ControllerSnapshotBox(Self.snapshot(text: "Draft", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let presenter = ControllerPresenter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter,
            writer: writer, timeline: tracer)
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = Self.snapshot(text: "Draft", x: 100, sequence: 2)
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .silence("no_completion"))))
        let events = try lines.values.map(Self.decodeTimeline).filter { $0["requestId"] as? String == identity.requestId }
        XCTAssertEqual(events.compactMap { $0["event"] as? String }, ["request_written", "final_received"])
        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertTrue(writer.outcomes.isEmpty)
    }

    @MainActor
    func testManualInvocationReplacesReadyResultWhenInvalidationIsQueued() throws {
        for hide in [false, true] {
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let writer = ControllerWriter()
            let presenter = ControllerPresenter()
            let main = DeferredControllerMainExecutor()
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, main: main)
            Self.makeReady(controller, current: current, writer: writer)
            let oldIdentity = try XCTUnwrap(controller.currentIdentity)
            if hide { _ = controller.handle(.hostGeometryDisturbed) }
            main.isDeferred = true
            controller.handle(.requestSuggestion)
            current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 4)
            controller.monitor.poll(at: 1)
            current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 5)
            controller.monitor.poll(at: 1.4)
            main.runAll()
            XCTAssertEqual(writer.requests.count, 2)
            XCTAssertTrue(try XCTUnwrap(writer.requests.last).payload.explicit)
            XCTAssertNotEqual(controller.currentIdentity, oldIdentity)
            let newIdentity = try XCTUnwrap(controller.currentIdentity)
            controller.handle(.suggestionFinal(.init(identity: oldIdentity, result: .text("obsolete"))))
            XCTAssertNil(presenter.visibleText)
            controller.handle(.suggestionFinal(.init(identity: newIdentity, result: .text("replacement"))))
            XCTAssertEqual(presenter.visibleText, "replacement")
            XCTAssertFalse(writer.outcomes.contains(.dismissed))
        }
    }

    @MainActor
    func testExplicitDismissalBlocksAutomaticRequestAfterAuthoredEdit() throws {
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Prueba: again", x: 101, sequence: 4)
        controller.monitor.poll(at: 0.5)
        controller.monitor.poll(at: 0.9)
        XCTAssertEqual(writer.requests.count, 1, "Dismissal must prevent a new request during the cooldown")
    }

    @MainActor
    func testCooldownExpiryRecapturesLatestDraftWithoutAnotherKeystroke() throws {
        let clock = ControllerCooldownClock()
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        clock.advance(to: 0.2)
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Prueba: edited", x: 101, sequence: 4)
        controller.monitor.poll(at: 1)
        controller.monitor.poll(at: 1.4)
        clock.advance(to: 0.9800000000000001)
        XCTAssertEqual(writer.requests.count, 1)
        // This latest draft, not the snapshot that scheduled the timer, must win.
        current.value = Self.snapshot(text: "Prueba: latest", x: 101, sequence: 5)
        clock.advance(to: 1.5)
        XCTAssertEqual(writer.requests.count, 2)
        XCTAssertEqual(writer.requests.last?.payload.textBefore, "Prueba: latest")
        clock.advance(to: 6.0)
        XCTAssertEqual(writer.requests.count, 2, "Expiry must not generate repeatedly")
    }

    @MainActor
    func testCompletedManualRequestRetiresSameTargetCooldownWakeup() throws {
        for fails in [false, true] {
            let clock = ControllerCooldownClock()
            let presenter = ControllerPresenter()
            let writer = ControllerWriter()
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
            Self.makeReady(controller, current: current, writer: writer)
            XCTAssertTrue(controller.handle(.dismissSuggestion))
            clock.advance(to: 0.2)
            controller.noteUserEdit()
            current.value = Self.snapshot(text: "Prueba: edited", x: 101, sequence: 4)
            controller.monitor.poll(at: 1)
            controller.monitor.poll(at: 1.4)
            clock.advance(to: 0.4)
            controller.handle(.requestSuggestion)
            controller.monitor.poll(at: 2)
            controller.monitor.poll(at: 2.4)
            XCTAssertEqual(writer.requests.count, 2)
            let identity = try XCTUnwrap(writer.requests.last?.identity)
            if fails {
                controller.handle(.requestFailed(.init(identity: identity, code: .network, retryable: true)))
            } else {
                controller.handle(.suggestionFinal(.init(identity: identity, result: .silence("no_completion"))))
            }
            clock.advance(to: 1.2)
            XCTAssertEqual(writer.requests.count, 2, "The old expiry must not retry a manually requested draft")
        }
    }

    @MainActor
    func testNewEditAfterManualRequestCanStillResumeAtOriginalCooldownDeadline() throws {
        let clock = ControllerCooldownClock()
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        clock.advance(to: 0.2)
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Prueba: edited", x: 101, sequence: 4)
        controller.monitor.poll(at: 1)
        controller.monitor.poll(at: 1.4)
        clock.advance(to: 0.4)
        controller.handle(.requestSuggestion)
        controller.monitor.poll(at: 2)
        controller.monitor.poll(at: 2.4)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .silence("no_completion"))))
        clock.advance(to: 0.6)
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Prueba: edited further", x: 101, sequence: 5)
        controller.monitor.poll(at: 3)
        controller.monitor.poll(at: 3.4)
        clock.advance(to: 0.9800000000000001)
        XCTAssertEqual(writer.requests.count, 2)
        clock.advance(to: 1.5)
        XCTAssertEqual(writer.requests.count, 3)
        XCTAssertEqual(writer.requests.last?.payload.textBefore, "Prueba: edited further")
    }

    @MainActor
    func testCooldownRequiresAuthoredChangeAndManualRequestBypassesOnlyCooldown() throws {
        let clock = ControllerCooldownClock()
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        // An AX-only draft change has no physical authored edit opportunity.
        current.value = Self.snapshot(text: "Prueba: AX edit", x: 101, sequence: 4)
        controller.monitor.poll(at: 1)
        controller.monitor.poll(at: 1.4)
        clock.advance(to: 2.0)
        XCTAssertEqual(writer.requests.count, 1)
        controller.handle(.requestSuggestion)
        controller.monitor.poll(at: 10)
        controller.monitor.poll(at: 10.4)
        XCTAssertEqual(writer.requests.count, 2)
        controller.updateConfiguration(.disabled)
        controller.handle(.requestSuggestion)
        controller.monitor.poll(at: 11)
        controller.monitor.poll(at: 11.4)
        XCTAssertEqual(writer.requests.count, 2)
    }

    @MainActor
    func testCooldownWakeupCannotGenerateInSecureField() throws {
        let clock = ControllerCooldownClock()
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let capture = ControllerCaptureBox()
        let controller = Self.controller(capture: { capture.secure ? .skipped(.secureField) : .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        clock.advance(to: 0.2)
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Prueba: edited", x: 101, sequence: 4)
        controller.monitor.poll(at: 1)
        controller.monitor.poll(at: 1.4)
        capture.secure = true
        clock.advance(to: 1.2)
        controller.handle(.requestSuggestion)
        clock.advance(to: 1.4)
        XCTAssertEqual(writer.requests.count, 1)
    }

    @MainActor
    func testTargetChangeCancelsOldCooldownWakeup() throws {
        let clock = ControllerCooldownClock()
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        clock.advance(to: 0.2)
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Prueba: edited", x: 101, sequence: 4)
        controller.monitor.poll(at: 1)
        controller.monitor.poll(at: 1.4)
        clock.advance(to: 0.4)
        controller.noteUserEdit() // User enters the new field; focus alone is insufficient.
        current.value = Self.snapshot(text: "Other field", x: 101, sequence: 5, focusGeneration: 2)
        controller.monitor.poll(at: 2)
        controller.monitor.poll(at: 2.4)
        XCTAssertEqual(writer.requests.count, 2, "A changed target resets the cooldown")
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .silence("no_completion"))))
        clock.advance(to: 1.2)
        XCTAssertEqual(writer.requests.count, 2, "An old target timer cannot retry a completed request")
    }

    @MainActor
    func testSecondExplicitDismissalWaitsThreeSecondsAfterNewAuthoredEdit() throws {
        let clock = ControllerCooldownClock()
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        clock.advance(to: 2)
        controller.handle(.requestSuggestion)
        current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 4)
        controller.monitor.poll(at: 2)
        current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 5)
        controller.monitor.poll(at: 2.4)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text("funciona"))))
        XCTAssertTrue(controller.handle(.dismissSuggestion))
        clock.advance(to: 3)
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Prueba: new edit", x: 101, sequence: 6)
        controller.monitor.poll(at: 3)
        controller.monitor.poll(at: 3.4)
        clock.advance(to: 4.9)
        XCTAssertEqual(writer.requests.count, 2)
        clock.advance(to: 5.5)
        XCTAssertEqual(writer.requests.count, 3)
    }

    @MainActor
    func testVerifiedAcceptanceResetsCooldownButFailedInsertionDoesNot() throws {
        for succeeds in [true, false] {
            let clock = ControllerCooldownClock()
            let presenter = ControllerPresenter()
            let writer = ControllerWriter()
            let inserter = ControllerInserter()
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, inserter: inserter, writer: writer, cooldownClock: clock)
            Self.makeReady(controller, current: current, writer: writer)
            XCTAssertTrue(controller.handle(.dismissSuggestion))
            clock.advance(to: 0.2)
            controller.handle(.requestSuggestion)
            current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 4)
            controller.monitor.poll(at: 1)
            current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 5)
            controller.monitor.poll(at: 1.4)
            let identity = try XCTUnwrap(writer.requests.last?.identity)
            controller.handle(.suggestionFinal(.init(identity: identity, result: .text("funciona"))))
            let accepted = Self.snapshot(text: "Prueba:funciona", x: 101, sequence: 6)
            inserter.result = succeeds ? .inserted(method: .accessibility, snapshot: accepted) : .writeFailed
            XCTAssertTrue(controller.attemptAcceptance())
            clock.advance(to: 0.4)
            controller.noteUserEdit()
            current.value = Self.snapshot(text: "Prueba:funciona again", x: 101, sequence: 7)
            controller.monitor.poll(at: 2)
            controller.monitor.poll(at: 2.4)
            XCTAssertEqual(writer.requests.count, succeeds ? 3 : 2)
        }
    }

    @MainActor
    func testDivergenceAndGeometryDoNotArmDismissalCooldown() {
        for action in [KeyboardAction.hostText("different"), .hostGeometryDisturbed] {
            let clock = ControllerCooldownClock()
            let presenter = ControllerPresenter()
            let writer = ControllerWriter()
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer, cooldownClock: clock)
            Self.makeReady(controller, current: current, writer: writer)
            _ = controller.handle(action)
            current.value = Self.snapshot(text: "Prueba: changed", x: 101, sequence: 4)
            controller.monitor.poll(at: 1)
            controller.monitor.poll(at: 1.4)
            XCTAssertEqual(writer.requests.count, 2)
            XCTAssertFalse(writer.outcomes.contains(.dismissed))
        }
    }

    @MainActor
    func testAppExclusionInvalidatesPendingResultAndResumeWaitsForInput() throws {
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let current = ControllerSnapshotBox(Self.snapshot(text: "Hello", x: 100, sequence: 1))
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, writer: writer)
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0); controller.monitor.poll(at: 0.4)
        let old = try XCTUnwrap(writer.requests.last?.identity)
        controller.updateConfiguration(.init(isEnabled: true, clipboardContextEnabled: false, excludedApplications: ["com.apple.Notes"]))
        controller.handle(.suggestionFinal(.init(identity: old, result: .text(" world"))))
        controller.handle(.requestSuggestion)
        controller.monitor.poll(at: 1); controller.monitor.poll(at: 1.4)
        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertEqual(writer.requests.count, 1)
        controller.updateConfiguration(.disabled)
        controller.updateConfiguration(.enabled, waitForInput: true)
        controller.monitor.poll(at: 2); controller.monitor.poll(at: 2.4)
        XCTAssertEqual(writer.requests.count, 1)
        controller.noteUserEdit()
        current.value = Self.snapshot(text: "Hello again", x: 100, sequence: 2)
        controller.monitor.poll(at: 3); controller.monitor.poll(at: 3.4)
        XCTAssertEqual(writer.requests.count, 2)
    }

    @MainActor
    func testExplicitRequestCannotRetargetAfterForegroundChanges() {
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(Self.snapshot(text: "Hello", x: 100, sequence: 1)) }, presenter: ControllerPresenter(), writer: writer, foregroundApplication: { "com.apple.TextEdit" })
        controller.updateConfiguration(.enabled)
        controller.handle(.requestSuggestion)
        controller.monitor.poll(at: 0); controller.monitor.poll(at: 0.4)
        XCTAssertTrue(writer.requests.isEmpty)
    }

    @MainActor
    func testOnDemandModeDoesNotGenerateUntilExplicitRequestAndCannotOverridePause() throws {
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let snapshot = Self.snapshot(text: "Hello", x: 100, sequence: 1)
        let controller = Self.controller(capture: { .captured(snapshot) }, presenter: presenter, writer: writer)
        let decoder = HelperCommandDecoder()
        let command = try XCTUnwrap(decoder.decode(#"{"protocolVersion":5,"type":"configure","payload":{"enabled":true,"excludedApplications":[],"automaticSuggestions":false,"quietPeriodMs":300,"ghostAlpha":0.30,"acceptShortcut":{"keyCode":48,"modifiers":0},"dismissShortcut":{"keyCode":53,"modifiers":0},"clipboardContextEnabled":false,"contextEnabled":false,"contextImagesEnabled":false,"learningEnabled":false}}"#))
        guard case let .configure(config) = command else { return XCTFail("Expected configuration") }
        controller.updateConfiguration(config)
        controller.monitor.poll(at: 0)
        controller.monitor.poll(at: 0.4)
        XCTAssertTrue(writer.requests.isEmpty)
        let request = try XCTUnwrap(decoder.decode(#"{"protocolVersion":5,"type":"request_suggestion","payload":null}"#))
        controller.handle(request)
        controller.monitor.poll(at: 1)
        controller.monitor.poll(at: 1.4)
        XCTAssertEqual(writer.requests.count, 1)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.updateConfiguration(.disabled)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text(" world"))))
        controller.handle(request)
        controller.monitor.poll(at: 2)
        controller.monitor.poll(at: 2.4)
        XCTAssertNil(presenter.visibleIdentity)
        XCTAssertEqual(writer.requests.count, 1)
    }

    @MainActor
    func testTracesRequestResponsePresentationCancellationAndInteraction() throws {
        let lines = ControllerTimelineLines()
        var monotonicMs = 100.0
        let tracer = HelperTimelineTracer(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            monotonicMilliseconds: { monotonicMs },
            wallMilliseconds: { 1_788_530_537_021 },
            dispatch: { work in work() },
            sink: { lines.append($0) }
        )
        let current = ControllerSnapshotBox(
            Self.snapshot(text: "PRIVATE DRAFT", x: 100, sequence: 1)
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer,
            timeline: tracer,
            monotonicMilliseconds: { monotonicMs }
        )

        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = Self.snapshot(text: "PRIVATE DRAFT", x: 101, sequence: 2)
        controller.monitor.poll(at: 0.1)
        current.value = Self.snapshot(text: "PRIVATE DRAFT", x: 101, sequence: 3)
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)

        monotonicMs = 400
        controller.handle(
            .suggestionFinal(.init(identity: identity, result: .text("SECRET FINAL")))
        )
        monotonicMs = 500
        XCTAssertTrue(controller.handle(.dismissSuggestion))

        let requestEvents = try lines.values.map(Self.decodeTimeline).filter {
            ($0["requestId"] as? String) == identity.requestId
        }
        XCTAssertEqual(
            requestEvents.map { $0["event"] as? String },
            [
                "request_written",
                "final_received",
                "presented",
                "interaction",
                "cancel_written",
                "interaction",
            ]
        )
        let cancel = try XCTUnwrap(requestEvents[4]["attrs"] as? [String: Any])
        XCTAssertEqual(cancel["sessionState"] as? String, "ready")
        XCTAssertEqual(cancel["reason"] as? String, "dismissed")
        let interactions = requestEvents.compactMap { event -> String? in
            guard event["event"] as? String == "interaction",
                  let attrs = event["attrs"] as? [String: Any]
            else { return nil }
            return attrs["outcome"] as? String
        }
        XCTAssertEqual(interactions, ["shown", "dismissed"])
        let dismissedInteraction = try XCTUnwrap(requestEvents.last?["attrs"] as? [String: Any])
        XCTAssertEqual(dismissedInteraction["sinceShownMs"] as? Double, 100)
        let serialized = lines.values.joined()
        XCTAssertFalse(serialized.contains("PRIVATE DRAFT"))
        XCTAssertFalse(serialized.contains("SECRET PARTIAL"))
        XCTAssertFalse(serialized.contains("SECRET PARTIAL FINAL"))
        XCTAssertFalse(serialized.contains("com.apple.Notes"))
    }

    @MainActor
    func testTracesFinalRejectedWhileAnchorIsUnavailable() throws {
        let lines = ControllerTimelineLines()
        var monotonicMs = 100.0
        let tracer = HelperTimelineTracer(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            monotonicMilliseconds: { monotonicMs },
            wallMilliseconds: { 1_788_530_537_021 },
            dispatch: { work in work() },
            sink: { lines.append($0) }
        )
        let current = ControllerSnapshotBox(
            Self.snapshot(
                text: "",
                x: 100,
                sequence: 1,
                hasGeometry: false,
                fieldContext: Self.derivedSubjectContext
            )
        )
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: ControllerPresenter(),
            writer: writer,
            timeline: tracer,
            monotonicMilliseconds: { monotonicMs }
        )
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)

        monotonicMs = 250
        controller.handle(
            .suggestionFinal(.init(identity: identity, result: .text("Resumen")))
        )

        let events = try lines.values.map(Self.decodeTimeline).filter {
            ($0["requestId"] as? String) == identity.requestId
        }
        XCTAssertEqual(
            events.map { $0["event"] as? String },
            ["request_written", "final_received", "present_rejected"]
        )
        let attrs = try XCTUnwrap(events.last?["attrs"] as? [String: Any])
        XCTAssertEqual(attrs["rejection"] as? String, "anchor_unavailable")
        XCTAssertEqual(attrs["anchorWaitMs"] as? Double, 0)
    }

    @MainActor
    func testUnresolvedEmptyFieldDoesNotCreateANetworkRequest() {
        let current = ControllerSnapshotBox(
            Self.snapshot(text: "", x: 100, sequence: 1, masksHostPlaceholder: true)
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer
        )

        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = Self.snapshot(
            text: "",
            x: 101,
            sequence: 2,
            masksHostPlaceholder: true
        )
        controller.monitor.poll(at: 0.1)
        current.value = Self.snapshot(
            text: "",
            x: 101,
            sequence: 3,
            masksHostPlaceholder: true
        )
        controller.monitor.poll(at: 0.3)

        XCTAssertTrue(writer.requests.isEmpty)
        XCTAssertEqual(controller.sessionState, .idle)
    }

    @MainActor
    func testResumeRecognizesObservedValueEditWithoutKeyboardEvent() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Existing draft", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer)
        controller.updateConfiguration(.enabled, waitForInput: true)
        controller.monitor.poll(at: 0)
        controller.monitor.poll(at: 0.4)
        XCTAssertTrue(writer.requests.isEmpty)
        current.value = Self.snapshot(text: "Existing draft", x: 100, sequence: 2, fieldContext: .init(shape: .multiline, label: "New source label"))
        controller.monitor.poll(at: 0.5)
        controller.monitor.poll(at: 0.9)
        XCTAssertTrue(writer.requests.isEmpty)
        current.value = Self.snapshot(text: "Existing draft. Dictated addition", x: 101, sequence: 3, fieldContext: .init(shape: .multiline, label: "New source label"))
        controller.monitor.poll(at: 1)
        controller.monitor.poll(at: 1.4)
        XCTAssertEqual(writer.requests.count, 1)
        XCTAssertEqual(writer.requests.first?.payload.explicit, false)
    }

    @MainActor
    func testExplicitInvocationReachesWireForEmptyField() throws {
        let current = ControllerSnapshotBox(Self.snapshot(text: "", x: 100, sequence: 1, masksHostPlaceholder: true))
        let writer = ControllerWriter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer)
        controller.updateConfiguration(.enabled)
        controller.handle(.requestSuggestion)
        controller.monitor.poll(at: 0)
        controller.monitor.poll(at: 0.4)
        XCTAssertTrue(try XCTUnwrap(writer.requests.last).payload.explicit)
    }

    @MainActor
    func testIncidentalArtifactCannotTriggerAnEmptyFieldRequest() throws {
        let current = ControllerSnapshotBox(
            Self.snapshot(text: "", x: 100, sequence: 1, masksHostPlaceholder: true)
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer,
            contextArtifacts: { _, timestamp in [.init(
                id: "clipboard-current", kind: "clipboard", text: "Hola Dana,\r\n\r\nTexto exacto",
                capturedAtMs: timestamp
            )] }
        )

        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = Self.snapshot(
            text: "",
            x: 101,
            sequence: 2,
            masksHostPlaceholder: true
        )
        controller.monitor.poll(at: 0.1)
        current.value = Self.snapshot(
            text: "",
            x: 101,
            sequence: 3,
            masksHostPlaceholder: true
        )
        controller.monitor.poll(at: 0.3)

        XCTAssertTrue(writer.requests.isEmpty)
    }

    @MainActor
    func testMaskedEmptyFieldPresentsOneFinalResponse() throws {
        let current = ControllerSnapshotBox(
            Self.snapshot(
                text: "",
                x: 100,
                sequence: 1,
                masksHostPlaceholder: true,
                fieldContext: Self.derivedSubjectContext
            )
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer
        )

        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = Self.snapshot(
            text: "",
            x: 101,
            sequence: 2,
            masksHostPlaceholder: true,
            fieldContext: Self.derivedSubjectContext
        )
        controller.monitor.poll(at: 0.1)
        current.value = Self.snapshot(
            text: "",
            x: 101,
            sequence: 3,
            masksHostPlaceholder: true,
            fieldContext: Self.derivedSubjectContext
        )
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)

        controller.handle(
            .suggestionFinal(.init(identity: identity, result: .text("one final result")))
        )
        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertEqual(presenter.visibleText, "one final result")
    }

    @MainActor
    func testEmptyFieldPreparesSilentlyThenShowsAfterTheFirstMatchingCharacter() throws {
        let current = ControllerSnapshotBox(
            Self.snapshot(
                text: "",
                x: 100,
                sequence: 1,
                hasGeometry: false,
                fieldContext: Self.derivedSubjectContext
            )
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer
        )

        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        controller.monitor.poll(at: 0.3)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.handle(
            .suggestionFinal(.init(identity: identity, result: .text("Resumen del proyecto")))
        )

        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(controller.keyboardStatus(), .activeWithoutGhost)

        XCTAssertFalse(controller.handle(.hostText("R")))
        current.value = Self.snapshot(
            text: "R",
            x: 108,
            sequence: 2,
            fieldContext: Self.derivedSubjectContext
        )
        controller.monitor.poll(at: 0.31)
        current.value = Self.snapshot(
            text: "R",
            x: 108.5,
            sequence: 3,
            fieldContext: Self.derivedSubjectContext
        )
        controller.monitor.poll(at: 0.32)

        XCTAssertEqual(presenter.visibleText, "esumen del proyecto")
    }

    @MainActor
    func testMatchingKeystrokeAdvancesGhostWithoutWaitingForAccessibility() throws {
        let current = ControllerSnapshotBox(
            Self.snapshot(text: "Prueba:", x: 100, sequence: 1)
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer
        )

        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertEqual(presenter.visibleText, "funciona")

        XCTAssertFalse(controller.handle(.hostText("f")))

        XCTAssertEqual(presenter.visibleText, "unciona")
        XCTAssertEqual(presenter.advancedTexts, ["f"])
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
    }

    @MainActor
    func testAcceptancePassesThroughUntilPreparationCompletes() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let inserter = ControllerInserter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), inserter: inserter, writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer)
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        XCTAssertFalse(controller.attemptAcceptance())
        XCTAssertEqual(inserter.prepareCount, 0)
        XCTAssertEqual(background.pendingCount, 1)
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
        XCTAssertEqual(inserter.prepareCount, 1)
        XCTAssertEqual(inserter.insertCount, 0)
    }

    @MainActor
    func testFailedPreparationPassesKeyboardDownRepeatAndUpThrough() {
        for failure in [NotesInsertionPreparation.staleField, .fieldUnavailable, .unsupportedSelection, .safeMethodUnavailable] {
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let writer = ControllerWriter()
            let inserter = ControllerInserter()
            inserter.preparationResult = failure
            let background = DeferredControllerExecutor()
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), inserter: inserter, writer: writer, background: background)
            Self.makeReady(controller, current: current, writer: writer)
            background.runNext()
            XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
            XCTAssertFalse(controller.attemptAcceptance())
            let keyboard = KeyboardMonitor(sessionProvider: { controller.keyboardStatus() }, actionHandler: { controller.handle($0) })
            XCTAssertFalse(keyboard.process(.init(keyCode: 48), phase: .keyDown))
            XCTAssertFalse(keyboard.process(.init(keyCode: 48, isRepeat: true), phase: .keyDown))
            XCTAssertFalse(keyboard.process(.init(keyCode: 48), phase: .keyUp))
            XCTAssertEqual(inserter.insertCount, 0)
            XCTAssertEqual(background.pendingCount, 0)
        }
    }

    @MainActor
    func testDelayedPreparationCannotReviveAfterInputFocusGeometryOrConfigurationChanges() {
        for change in 0..<5 {
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let writer = ControllerWriter()
            let background = DeferredControllerExecutor()
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, background: background)
            Self.makeReady(controller, current: current, writer: writer)
            switch change {
            case 0: _ = controller.handle(.hostText("f"))
            case 1: _ = controller.handle(.hostStateChanged)
            case 2: _ = controller.handle(.hostGeometryDisturbed)
            case 3: controller.updateConfiguration(.disabled)
            default: _ = controller.handle(.hostAmbiguousText)
            }
            background.runNext()
            XCTAssertNotEqual(controller.keyboardStatus(), .ready)
            XCTAssertFalse(controller.attemptAcceptance())
        }
    }

    @MainActor
    func testTypeThroughNeedsPreparationForAuthoritativeRemainingText() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let inserter = ControllerInserter()
        let background = DeferredControllerExecutor()
        let presenter = ControllerPresenter()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, inserter: inserter, writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer)
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
        XCTAssertFalse(controller.handle(.hostText("f")))
        XCTAssertFalse(controller.attemptAcceptance())
        current.value = Self.snapshot(text: "Prueba:f", x: 109, sequence: 4)
        controller.monitor.poll(at: 0.31)
        current.value = Self.snapshot(text: "Prueba:f", x: 109, sequence: 5)
        controller.monitor.poll(at: 0.32)
        XCTAssertEqual(presenter.visibleText, "unciona")
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
        XCTAssertTrue(controller.attemptAcceptance())
        background.runNext()
        XCTAssertEqual(inserter.insertedTexts, ["unciona"])
        XCTAssertEqual(inserter.preparedSnapshots.last?.textBefore, "Prueba:f")
    }

    @MainActor
    func testReadyAcceptanceRevalidatesFocusBeforeInsertionAndConsumesKeyExactlyOnce() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let inserter = ControllerInserter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), inserter: inserter, writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer)
        background.runNext()
        let keyboard = KeyboardMonitor(sessionProvider: { controller.keyboardStatus() }, actionHandler: { controller.handle($0) })
        XCTAssertTrue(keyboard.process(.init(keyCode: 48), phase: .keyDown))
        XCTAssertTrue(keyboard.process(.init(keyCode: 48, isRepeat: true), phase: .keyDown))
        inserter.preparationResult = .staleField
        background.runNext()
        XCTAssertEqual(inserter.prepareCount, 2)
        XCTAssertEqual(inserter.insertCount, 0)
        XCTAssertEqual(writer.outcomes.last, .stale)
        XCTAssertTrue(keyboard.process(.init(keyCode: 48), phase: .keyUp))
        XCTAssertFalse(keyboard.process(.init(keyCode: 48), phase: .keyUp))
    }

    @MainActor
    func testNewRequestCannotUseOldPreparationCompletion() throws {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer)
        let oldIdentity = controller.currentIdentity
        _ = controller.handle(.hostStateChanged)
        current.value = Self.snapshot(text: "New draft", x: 101, sequence: 4)
        controller.monitor.poll(at: 1)
        current.value = Self.snapshot(text: "New draft", x: 101, sequence: 5)
        controller.monitor.poll(at: 1.4)
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        XCTAssertNotEqual(identity, oldIdentity)
        controller.handle(.suggestionFinal(.init(identity: identity, result: .text(" new result"))))
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        XCTAssertFalse(controller.attemptAcceptance())
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
    }

    @MainActor
    func testUnchangedPollingDoesNotDiscardPreparedPresentation() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer)
        background.runNext()
        current.value = Self.snapshot(text: "Prueba:", x: 101, sequence: 4)
        controller.monitor.poll(at: 0.4)
        XCTAssertEqual(controller.keyboardStatus(), .ready)
        XCTAssertEqual(background.pendingCount, 0)
    }

    @MainActor
    func testOffMainPreparationWaitsForMainPublicationAndDropsStaleCompletion() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let inserter = ControllerInserter()
        let background = DeferredControllerExecutor()
        let main = DeferredControllerMainExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), inserter: inserter, writer: writer, background: background, main: main)
        Self.makeReady(controller, current: current, writer: writer)
        main.isDeferred = true
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            background.runNext()
            finished.signal()
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(inserter.preparationWasOnMainThread, [false])
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        XCTAssertFalse(controller.attemptAcceptance())
        _ = controller.handle(.hostStateChanged)
        main.runAll()
        XCTAssertEqual(controller.keyboardStatus(), .inactive)
        XCTAssertFalse(controller.attemptAcceptance())
        XCTAssertEqual(inserter.insertCount, 0)
    }

    @MainActor
    func testCaptureGenerationInvalidatesReadinessBeforeFocusCallbackRuns() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let main = DeferredControllerMainExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, background: background, main: main)
        Self.makeReady(controller, current: current, writer: writer)
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
        main.isDeferred = true
        current.value = Self.snapshot(text: "Other field", x: 101, sequence: 4, focusGeneration: 2)
        controller.monitor.poll(at: 0.4)
        XCTAssertNotEqual(controller.keyboardStatus(), .ready)
        XCTAssertFalse(controller.attemptAcceptance())
        main.runAll()
        XCTAssertEqual(controller.keyboardStatus(), .inactive)
    }

    @MainActor
    func testStableGeometryChangeRevokesReadinessBeforeMainCallbackRuns() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let main = DeferredControllerMainExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, background: background, main: main)
        Self.makeReady(controller, current: current, writer: writer)
        background.runNext()
        main.isDeferred = true
        current.value = Self.snapshot(text: "Prueba:", x: 121, sequence: 4)
        controller.monitor.poll(at: 0.4)
        current.value = Self.snapshot(text: "Prueba:", x: 121, sequence: 5)
        controller.monitor.poll(at: 0.5)
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        XCTAssertFalse(controller.attemptAcceptance())
        main.runAll()
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        background.runNext()
        main.runAll()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
    }

    @MainActor
    func testGeometryReacquisitionRequiresNewPreparation() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer)
        background.runNext()
        _ = controller.handle(.hostGeometryDisturbed)
        current.value = Self.snapshot(text: "Prueba:", x: 121, sequence: 4)
        controller.monitor.poll(at: 0.4)
        current.value = Self.snapshot(text: "Prueba:", x: 121, sequence: 5)
        controller.monitor.poll(at: 0.5)
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        XCTAssertFalse(controller.attemptAcceptance())
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
    }

    @MainActor
    func testAppearanceConfigurationCannotReusePendingPreparation() {
        let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
        let writer = ControllerWriter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(capture: { .captured(current.value) }, presenter: ControllerPresenter(), writer: writer, background: background)
        Self.makeReady(controller, current: current, writer: writer)
        var configuration = CaptureConfiguration.enabled
        configuration.ghostAlpha = 0.6
        controller.updateConfiguration(configuration)
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ghostVisible)
        XCTAssertFalse(controller.attemptAcceptance())
        background.runNext()
        XCTAssertEqual(controller.keyboardStatus(), .ready)
    }

    @MainActor
    func testVisibleTextMismatchNeverEnablesKeyboardOrClickAcceptance() {
        for visibleText in [nil, "", "hidden prefix"] as [String?] {
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let writer = ControllerWriter()
            let background = DeferredControllerExecutor()
            let presenter = ControllerPresenter()
            let inserter = ControllerInserter()
            let controller = Self.controller(capture: { .captured(current.value) }, presenter: presenter, inserter: inserter, writer: writer, background: background)
            Self.makeReady(controller, current: current, writer: writer)
            background.runNext()
            presenter.visibleText = visibleText
            XCTAssertFalse(controller.attemptAcceptance())
            let keyboard = KeyboardMonitor(sessionProvider: { controller.keyboardStatus() }, actionHandler: { controller.handle($0) })
            XCTAssertFalse(keyboard.process(.init(keyCode: 48), phase: .keyDown))
            XCTAssertFalse(keyboard.process(.init(keyCode: 48), phase: .keyUp))
            XCTAssertEqual(inserter.insertCount, 0)
        }
    }

    @MainActor
    func testAcceptanceDismissesSynchronouslyAndDefersInsertion() {
        let current = ControllerSnapshotBox(
            Self.snapshot(text: "Prueba:", x: 100, sequence: 1)
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let inserter = ControllerInserter()
        let background = DeferredControllerExecutor()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            inserter: inserter,
            writer: writer,
            background: background
        )

        Self.makeReady(controller, current: current, writer: writer)

        background.runNext()
        XCTAssertTrue(controller.attemptAcceptance())
        XCTAssertNil(presenter.visibleText)
        XCTAssertFalse(controller.attemptAcceptance())
        XCTAssertEqual(inserter.prepareCount, 1)
        XCTAssertEqual(background.pendingCount, 1)

        background.runNext()

        XCTAssertEqual(inserter.prepareCount, 2)
        XCTAssertEqual(inserter.insertCount, 1)
        XCTAssertEqual(controller.sessionState, .idle)
    }

    @MainActor
    func testOnlyVerifiedAcceptanceEntersRecentContext() {
        for succeeded in [false, true] {
            let current = ControllerSnapshotBox(Self.snapshot(text: "Prueba:", x: 100, sequence: 1))
            let writer = ControllerWriter()
            let background = DeferredControllerExecutor()
            let inserter = ControllerInserter()
            let memory = RecentWritingContext()
            var acceptedIdentities: [SuggestionRequestMessage.Identity] = []
            memory.updateConfiguration(.enabled)
            inserter.result = succeeded
                ? .inserted(method: .accessibility, snapshot: Self.snapshot(text: "Prueba:funciona", x: 150, sequence: 4))
                : .verificationFailed
            let controller = Self.controller(
                capture: { .captured(current.value) }, presenter: ControllerPresenter(),
                inserter: inserter, writer: writer, background: background,
                onAccepted: { identity, text, snapshot in
                    acceptedIdentities.append(identity)
                    memory.recordAcceptance(text: text, snapshot: snapshot, timestampMs: 100)
                }
            )
            Self.makeReady(controller, current: current, writer: writer)
            background.runNext()
            XCTAssertTrue(memory.artifacts(for: current.value, timestampMs: 100).isEmpty)
            XCTAssertTrue(controller.attemptAcceptance())
            XCTAssertTrue(memory.artifacts(for: current.value, timestampMs: 100).isEmpty)
            background.runNext()
            XCTAssertEqual(memory.artifacts(for: current.value, timestampMs: 101).map(\.text), succeeded ? ["funciona"] : [])
            XCTAssertEqual(acceptedIdentities, succeeded ? [writer.requests.last!.identity] : [])
        }
    }

    @MainActor
    func testWrongTypedCharacterCancelsInsteadOfShowingStaleGhost() {
        let current = ControllerSnapshotBox(
            Self.snapshot(text: "Prueba:", x: 100, sequence: 1)
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer
        )

        Self.makeReady(controller, current: current, writer: writer)

        XCTAssertFalse(controller.handle(.hostText("x")))
        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(controller.sessionState, .idle)
        XCTAssertEqual(writer.cancellations.count, 1)
    }

    @MainActor
    func testScrollHidesGhostWithoutCancellingCurrentSuggestion() {
        let current = ControllerSnapshotBox(
            Self.snapshot(text: "Prueba:", x: 100, sequence: 1)
        )
        let presenter = ControllerPresenter()
        let writer = ControllerWriter()
        let controller = Self.controller(
            capture: { .captured(current.value) },
            presenter: presenter,
            writer: writer
        )

        Self.makeReady(controller, current: current, writer: writer)
        let identity = controller.currentIdentity

        XCTAssertFalse(controller.handle(.hostGeometryDisturbed))

        XCTAssertNil(presenter.visibleText)
        XCTAssertEqual(controller.currentIdentity, identity)
        XCTAssertTrue(writer.cancellations.isEmpty)
    }

    @MainActor
    private static func controller(
        capture: @escaping () -> ActiveFieldCaptureResult,
        presenter: ControllerPresenter,
        inserter: ControllerInserter = ControllerInserter(),
        writer: ControllerWriter,
        foregroundApplication: @escaping () -> String? = { "com.apple.Notes" },
        userInteraction: Bool = true,
        background: DeferredControllerExecutor? = nil,
        main: DeferredControllerMainExecutor? = nil,
        cooldownClock: ControllerCooldownClock? = nil,
        timeline: (any HelperTimelineTracing)? = nil,
        contextArtifacts: @escaping SuggestionController.ContextArtifacts = { _, _ in [] },
        onAccepted: @escaping (SuggestionRequestMessage.Identity, String, ActiveFieldSnapshot) -> Void = { _, _, _ in },
        monotonicMilliseconds: @escaping () -> Double = {
            ProcessInfo.processInfo.systemUptime * 1_000
        }
    ) -> SuggestionController {
        let mainDispatcher: SuggestionController.MainDispatcher = { work in
            if let main { main.enqueue(work) }
            else { MainActor.assumeIsolated { work() } }
        }
        let backgroundDispatcher: SuggestionController.BackgroundDispatcher?
        if let background {
            backgroundDispatcher = { work in background.enqueue(work) }
        } else {
            backgroundDispatcher = { work in work() }
        }
        let controller = SuggestionController(
            capture: capture,
            presenter: presenter,
            inserter: inserter,
            writer: writer,
            diagnostics: FixtureDiagnostics(environment: [:], sink: { _ in }),
            foregroundApplication: foregroundApplication,
            contextArtifacts: contextArtifacts,
            onAccepted: onAccepted,
            quietInterval: 0.3,
            scheduleAfterHostPublication: { delay, work in cooldownClock?.schedule(delay, work) },
            scheduleCooldown: { delay, work in cooldownClock?.schedule(delay, work) },
            scheduleQuietDeadline: cooldownClock.map { clock in { delay, work in clock.schedule(delay, work) } },
            now: { cooldownClock?.now ?? Date.timeIntervalSinceReferenceDate },
            timeline: timeline,
            monotonicMilliseconds: monotonicMilliseconds,
            dispatchToMain: mainDispatcher,
            dispatchToBackground: backgroundDispatcher
        )
        if userInteraction { controller.noteUserEdit() }
        return controller
    }

    private static func decodeTimeline(_ line: String) throws -> [String: Any] {
        XCTAssertTrue(line.hasPrefix("timeline:"))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(line.dropFirst("timeline:".count).utf8)
            ) as? [String: Any]
        )
    }

    @MainActor
    private static func makeReady(
        _ controller: SuggestionController,
        current: ControllerSnapshotBox,
        writer: ControllerWriter,
        text: String = "funciona"
    ) {
        controller.updateConfiguration(.enabled)
        controller.monitor.poll(at: 0)
        current.value = snapshot(text: "Prueba:", x: 101, sequence: 2)
        controller.monitor.poll(at: 0.1)
        current.value = snapshot(text: "Prueba:", x: 101, sequence: 3)
        controller.monitor.poll(at: 0.3)
        let identity = writer.requests.last!.identity
        controller.handle(
            .suggestionFinal(.init(identity: identity, result: .text(text)))
        )
        XCTAssertNotNil(controller.currentIdentity)
    }

    private static func snapshot(
        text: String,
        x: CGFloat,
        sequence: UInt64,
        focusGeneration: UInt64 = 1,
        hasGeometry: Bool = true,
        masksHostPlaceholder: Bool = false,
        fieldContext: ActiveFieldContext? = nil
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Notes",
            elementIdentifier: "notes-field",
            focusGeneration: focusGeneration,
            textBefore: text,
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            caretBounds: hasGeometry
                ? CGRect(x: x, y: 100, width: 0, height: 18)
                : nil,
            inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
            geometryQuality: hasGeometry ? .exact : .unavailable,
            geometrySource: hasGeometry ? .zeroLengthRange : nil,
            captureSequence: sequence,
            masksHostPlaceholder: masksHostPlaceholder,
            fieldContext: fieldContext
        )
    }

    private static let derivedSubjectContext = ActiveFieldContext(
        shape: .singleLine,
        placeholder: "Subject",
        relatedFields: [
            RelatedFieldContext(
                shape: .multiline,
                label: "Message Body",
                placeholder: nil,
                text: "Hola Dana, te comparto la propuesta."
            ),
        ]
    )
}

private final class ControllerTimelineLines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ line: String) {
        lock.withLock { storage.append(line) }
    }
}

private final class ControllerSnapshotBox: @unchecked Sendable {
    var value: ActiveFieldSnapshot

    init(_ value: ActiveFieldSnapshot) {
        self.value = value
    }
}

@MainActor
private final class ControllerPresenter: GhostPresenting {
    func refreshAppearance() {}
    var visibleIdentity: SuggestionRequestMessage.Identity?
    var fittedText: String?
    var fittingFlags: [Bool] = []
    var visibleText: String?
    var visibleGlyphRegions: [CGRect] = []
    var lastRejectionReason: GhostTextPresenterRejectionReason?
    var lastParagraphLayoutFailureReason: ParagraphMirrorLayoutFailureReason?
    var lastHorizontalDrawOffset: CGFloat?
    var visibleSnapshot: ActiveFieldSnapshot?
    var advancedTexts: [String] = []
    private(set) var presentCount = 0

    func present(
        identity: SuggestionRequestMessage.Identity,
        text: String,
        snapshot: ActiveFieldSnapshot,
        protectedText: [String],
        allowsFitting: Bool
    ) -> Bool {
        presentCount += 1
        guard snapshot.geometryQuality != .unavailable,
              snapshot.geometrySource != nil,
              snapshot.caretBounds != nil
        else { return false }
        visibleIdentity = identity
        fittingFlags.append(allowsFitting)
        visibleText = allowsFitting ? (fittedText ?? text) : text
        visibleSnapshot = snapshot
        visibleGlyphRegions = [CGRect(x: 100, y: 100, width: 80, height: 18)]
        return true
    }

    func advance(
        identity: SuggestionRequestMessage.Identity,
        typed: String,
        remaining: String
    ) -> ActiveFieldSnapshot? {
        guard identity == visibleIdentity, let snapshot = visibleSnapshot else { return nil }
        advancedTexts.append(typed)
        let advanced = ActiveFieldSnapshot(
            applicationBundleIdentifier: snapshot.applicationBundleIdentifier,
            surface: snapshot.surface,
            elementIdentifier: snapshot.elementIdentifier,
            focusGeneration: snapshot.focusGeneration,
            textBefore: snapshot.textBefore + typed,
            selectedText: snapshot.selectedText,
            textAfter: snapshot.textAfter,
            selectionRange: NSRange(
                location: snapshot.selectionRange.location + typed.utf16.count,
                length: 0
            ),
            caretBounds: snapshot.caretBounds.map {
                CGRect(x: $0.minX + 8, y: $0.minY, width: 0, height: $0.height)
            },
            inputFrame: snapshot.inputFrame,
            paragraphStartBounds: snapshot.paragraphStartBounds,
            geometryQuality: snapshot.geometryQuality,
            geometrySource: snapshot.geometrySource,
            captureSequence: snapshot.captureSequence,
            textStyle: snapshot.textStyle,
            paragraphMetrics: snapshot.paragraphMetrics,
            paragraphMetricsFailureReason: snapshot.paragraphMetricsFailureReason,
            fieldKind: snapshot.fieldKind,
            publicationStructure: snapshot.publicationStructure,
            geometryStructure: snapshot.geometryStructure,
            masksHostPlaceholder: snapshot.masksHostPlaceholder
        )
        visibleText = remaining
        visibleSnapshot = advanced
        return advanced
    }

    func dismiss(identity: SuggestionRequestMessage.Identity?) -> Bool {
        if let identity, identity != visibleIdentity { return false }
        guard visibleIdentity != nil else { return false }
        clear()
        return true
    }

    func dismissForGeometryChange() -> Bool { dismiss(identity: nil) }

    func dismissForAcceptance(identity: SuggestionRequestMessage.Identity) {
        if identity == visibleIdentity { clear() }
    }

    private func clear() {
        visibleIdentity = nil
        visibleText = nil
        visibleGlyphRegions = []
        visibleSnapshot = nil
    }
}

private final class ControllerInserter: SuggestionInserting, @unchecked Sendable {
    private(set) var prepareCount = 0
    private(set) var insertCount = 0
    var result: NotesInsertionResult = .writeFailed
    var preparationResult: NotesInsertionPreparation?
    private(set) var preparationWasOnMainThread: [Bool] = []
    private(set) var preparedSnapshots: [ActiveFieldSnapshot] = []
    private(set) var insertedTexts: [String] = []
    var insertResult: ((String, PreparedNotesInsertion) -> NotesInsertionResult)?

    func prepare(for expectedSnapshot: ActiveFieldSnapshot) -> NotesInsertionPreparation {
        prepareCount += 1
        preparationWasOnMainThread.append(Thread.isMainThread)
        preparedSnapshots.append(expectedSnapshot)
        if let preparationResult { return preparationResult }
        return .prepared(.init(method: .accessibility, expectedSnapshot: expectedSnapshot))
    }

    func insert(_ text: String, prepared: PreparedNotesInsertion, isCurrent: () -> Bool) -> NotesInsertionResult {
        guard isCurrent() else { return .staleField }
        insertCount += 1
        insertedTexts.append(text)
        return insertResult?(text, prepared) ?? result
    }
}

private final class ControllerWriter: HelperMessageWriting, @unchecked Sendable {
    private(set) var requests: [SuggestionRequestMessage] = []
    private(set) var cancellations: [CancelRequestMessage] = []
    private(set) var interactions: [(InteractionOutcome, Int)] = []
    private(set) var outcomes: [InteractionOutcome] = []

    func writeSuggestionRequest(_ message: SuggestionRequestMessage) throws {
        requests.append(message)
    }

    func writeCancelRequest(_ message: CancelRequestMessage) throws {
        cancellations.append(message)
    }

    func writeInteraction(
        identity: SuggestionRequestMessage.Identity,
        outcome: InteractionOutcome,
        acceptedCharacters: Int
    ) throws { interactions.append((outcome, acceptedCharacters)); outcomes.append(outcome) }

    func writeDiagnostic(_ code: String) {}
}

private final class DeferredControllerExecutor: @unchecked Sendable {
    private var work: [@Sendable () -> Void] = []
    var pendingCount: Int { work.count }

    func enqueue(_ operation: @escaping @Sendable () -> Void) {
        work.append(operation)
    }

    func runNext() {
        guard !work.isEmpty else {
            XCTFail("Expected queued background work")
            return
        }
        work.removeFirst()()
    }
}

private final class DeferredControllerMainExecutor: @unchecked Sendable {
    var isDeferred = false
    private var work: [@MainActor @Sendable () -> Void] = []

    func enqueue(_ operation: @escaping @MainActor @Sendable () -> Void) {
        if isDeferred { work.append(operation) }
        else { MainActor.assumeIsolated { operation() } }
    }

    @MainActor
    func runAll() {
        while !work.isEmpty { work.removeFirst()() }
    }
}

private final class ControllerCaptureBox: @unchecked Sendable {
    var secure = false
}

private final class ControllerCooldownClock: @unchecked Sendable {
    var now: TimeInterval = 0
    private var pending: [(deadline: TimeInterval, work: @Sendable () -> Void)] = []

    func schedule(_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        pending.append((now + delay, work))
    }

    func advance(to deadline: TimeInterval) {
        var remaining = 100
        while let index = pending.indices.min(by: { pending[$0].deadline < pending[$1].deadline }), pending[index].deadline <= deadline {
            remaining -= 1
            guard remaining > 0 else { XCTFail("Unbounded timer scheduling"); return }
            let next = pending.remove(at: index)
            now = next.deadline
            next.work()
        }
        now = deadline
    }
}
