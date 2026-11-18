import Foundation
import XCTest
@testable import AutocompleteHelper

final class ActiveFieldMonitorTests: XCTestCase {
    func testInstantRequestsOnFirstCaptureWithoutWaitingAndDoesNotDuplicate() {
        var delivered = 0
        var snapshot = Self.snapshot(textBefore: "Hello")
        let monitor = ActiveFieldMonitor(capture: { .captured(snapshot) }, onStableSnapshot: { _, _ in delivered += 1 })
        var configuration = CaptureConfiguration.enabled
        configuration.quietPeriodMs = 0
        monitor.updateConfiguration(configuration)
        monitor.poll(at: 0)
        XCTAssertEqual(delivered, 1)
        monitor.poll(at: 0)
        XCTAssertEqual(delivered, 1)
        snapshot = Self.snapshot(textBefore: "Hello there")
        monitor.poll(at: 0.01)
        XCTAssertEqual(delivered, 2)
    }

    func testConfiguredTimingChangesNativeStabilityDeadline() {
        var delivered = 0
        let monitor = ActiveFieldMonitor(capture: { .captured(Self.snapshot(textBefore: "A reply")) }, onStableSnapshot: { _, _ in delivered += 1 })
        var configuration = CaptureConfiguration.enabled
        configuration.quietPeriodMs = 700
        monitor.updateConfiguration(configuration)
        monitor.poll(at: 0); monitor.poll(at: 0.3)
        XCTAssertEqual(delivered, 0)
        monitor.poll(at: 0.7)
        XCTAssertEqual(delivered, 1)
        configuration.quietPeriodMs = 150
        monitor.updateConfiguration(configuration)
        monitor.poll(at: 1); monitor.poll(at: 1.16)
        XCTAssertEqual(delivered, 2)
    }

    func testTracesObservedStableAndSkippedCapturesWithoutContent() throws {
        let lines = MonitorTimelineLines()
        var monotonicMs = 100.0
        var result: ActiveFieldCaptureResult = .captured(
            Self.snapshot(textBefore: "DO NOT LOG THIS", captureSequence: 9)
        )
        let tracer = HelperTimelineTracer(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            monotonicMilliseconds: { monotonicMs },
            wallMilliseconds: { 1_788_530_537_021 },
            dispatch: { work in work() },
            sink: { lines.append($0) }
        )
        let monitor = ActiveFieldMonitor(
            capture: {
                monotonicMs += 12.5
                return result
            },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            timeline: tracer,
            monotonicMilliseconds: { monotonicMs }
        )
        monitor.updateConfiguration(.enabled)

        monitor.poll(at: 0)
        monitor.poll(at: 0.3)
        result = .skipped(.rangeMissing)
        monitor.poll(at: 0.31)

        let events = try lines.values.map(Self.decodeTimeline)
        XCTAssertEqual(
            events.map { $0["event"] as? String },
            ["input_observed", "content_stable", "capture_skipped"]
        )
        let observed = try XCTUnwrap(events[0]["attrs"] as? [String: Any])
        XCTAssertEqual(observed["captureSeq"] as? Int, 9)
        XCTAssertEqual(observed["captureMs"] as? Double, 12.5)
        let stable = try XCTUnwrap(events[1]["attrs"] as? [String: Any])
        XCTAssertEqual(stable["quietMs"] as? Double, 300)
        let skipped = try XCTUnwrap(events[2]["attrs"] as? [String: Any])
        XCTAssertEqual(skipped["reason"] as? String, "range_missing")
        XCTAssertEqual(skipped["consecutive"] as? Int, 1)
        XCTAssertEqual(skipped["sinceLastOkMs"] as? Double, 12.5)
        XCTAssertFalse(lines.values.joined().contains("DO NOT LOG THIS"))
    }

    func testDoesNotReadAccessibilityWhileDisabled() {
        var captureCount = 0
        let monitor = ActiveFieldMonitor(
            capture: {
                captureCount += 1
                return .captured(Self.snapshot(textBefore: "fixture"))
            },
            onStableSnapshot: { _, _ in }
        )

        monitor.poll(at: 0)

        XCTAssertEqual(captureCount, 0)
    }

    private static func decodeTimeline(_ line: String) throws -> [String: Any] {
        XCTAssertTrue(line.hasPrefix("timeline:"))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(line.dropFirst("timeline:".count).utf8)
            ) as? [String: Any]
        )
    }

    func testEmitsOnlyAfterTheSnapshotRemainsStableForTheQuietInterval() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18)
        )
        var emitted: [ActiveFieldSnapshot] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.poll(at: 0)
        monitor.poll(at: 0.29)
        XCTAssertTrue(emitted.isEmpty)
        monitor.poll(at: 0.3)
        XCTAssertEqual(emitted.map(\.textBefore), ["Hello"])

        current = Self.snapshot(
            textBefore: "Hello world",
            caretBounds: CGRect(x: 180, y: 100, width: 0, height: 18)
        )
        monitor.poll(at: 0.31)
        monitor.poll(at: 0.6)
        XCTAssertEqual(emitted.map(\.textBefore), ["Hello"])
        monitor.poll(at: 0.61)
        XCTAssertEqual(emitted.map(\.textBefore), ["Hello", "Hello world"])
    }

    func testSchedulesAnExactOneShotDeadlineAndConfirmsTheSnapshotBeforeEmission() throws {
        var currentTime = 10.0
        var captureCount = 0
        var requestedDelays: [TimeInterval] = []
        var scheduled: [() -> Void] = []
        var emitted: [ActiveFieldSnapshot] = []
        let monitor = ActiveFieldMonitor(
            capture: {
                captureCount += 1
                return .captured(Self.snapshot(textBefore: "Hello"))
            },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) },
            scheduleQuietDeadline: { delay, work in
                requestedDelays.append(delay)
                scheduled.append(work)
            },
            now: { currentTime }
        )
        monitor.updateConfiguration(.enabled)

        monitor.poll(at: currentTime)

        XCTAssertEqual(try XCTUnwrap(requestedDelays.first), 0.3, accuracy: 0.000_001)
        XCTAssertEqual(captureCount, 1)
        XCTAssertTrue(emitted.isEmpty)

        currentTime = 10.3
        scheduled[0]()

        XCTAssertEqual(captureCount, 2)
        XCTAssertEqual(emitted.map(\.textBefore), ["Hello"])
    }

    func testNewInputInvalidatesThePendingQuietDeadlineBeforeAnotherCapture() {
        var captureCount = 0
        var scheduled: (() -> Void)?
        let monitor = ActiveFieldMonitor(
            capture: {
                captureCount += 1
                return .captured(Self.snapshot(textBefore: "Hello"))
            },
            onStableSnapshot: { _, _ in },
            scheduleAfterHostPublication: { _, _ in },
            scheduleQuietDeadline: { _, work in scheduled = work },
            now: { 0 }
        )
        monitor.updateConfiguration(.enabled)
        monitor.poll(at: 0)

        monitor.refreshAfterInput()
        scheduled?()

        XCTAssertEqual(captureCount, 1)
    }

    func testDisableAndStopInvalidatePendingQuietDeadlines() {
        var captureCount = 0
        var scheduled: [() -> Void] = []
        let monitor = ActiveFieldMonitor(
            capture: {
                captureCount += 1
                return .captured(Self.snapshot(textBefore: "Hello"))
            },
            onStableSnapshot: { _, _ in },
            scheduleQuietDeadline: { _, work in scheduled.append(work) },
            now: { 0 }
        )
        monitor.updateConfiguration(.enabled)
        monitor.poll(at: 0)
        monitor.updateConfiguration(.disabled)
        scheduled[0]()
        XCTAssertEqual(captureCount, 1)

        monitor.updateConfiguration(.enabled)
        monitor.poll(at: 1)
        monitor.stop()
        scheduled[1]()
        XCTAssertEqual(captureCount, 2)
    }

    func testSkippedOrDisabledFieldsDiscardPendingPrivateText() {
        var result: ActiveFieldCaptureResult = .captured(
            Self.snapshot(textBefore: "private fixture")
        )
        var emitted = 0
        let monitor = ActiveFieldMonitor(
            capture: { result },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in emitted += 1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.poll(at: 0)
        result = .skipped(.secureField)
        monitor.poll(at: 0.1)
        result = .captured(Self.snapshot(textBefore: "private fixture"))
        monitor.poll(at: 0.2)
        monitor.updateConfiguration(.disabled)
        monitor.poll(at: 1)

        XCTAssertEqual(emitted, 0)
    }

    func testInvalidatesImmediatelyWhenObservedContentOrFocusChanges() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18)
        )
        var invalidated: [ActiveFieldSnapshot?] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            onInvalidated: { snapshot, _ in invalidated.append(snapshot) }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        current = Self.snapshot(textBefore: "Hello changed")
        monitor.poll(at: 0.31)
        current = Self.snapshot(textBefore: "Other", focusGeneration: 2)
        monitor.poll(at: 0.32)

        XCTAssertEqual(invalidated.compactMap { $0?.textBefore }, ["Hello changed", "Other"])
    }

    func testSkippedFieldInvalidatesAnEmittedSnapshotOnce() {
        var result: ActiveFieldCaptureResult = .captured(
            Self.snapshot(textBefore: "Hello")
        )
        var invalidationCount = 0
        let monitor = ActiveFieldMonitor(
            capture: { result },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            onInvalidated: { snapshot, _ in
                XCTAssertNil(snapshot)
                invalidationCount += 1
            }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        result = .skipped(.unsupportedApplication)
        monitor.poll(at: 0.31)
        monitor.poll(at: 0.32)

        XCTAssertEqual(invalidationCount, 1)
    }

    func testVerifiedInsertedSnapshotIsNotImmediatelyReemitted() {
        let inserted = Self.snapshot(textBefore: "Hello completed")
        var emitted: [ActiveFieldSnapshot] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(inserted) },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.markHandled(inserted)
        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        XCTAssertTrue(emitted.isEmpty)
    }

    func testDoesNotCaptureWhileInsertionIsInProgress() {
        var captureCount = 0
        let monitor = ActiveFieldMonitor(
            capture: {
                captureCount += 1
                return .captured(Self.snapshot(textBefore: "Hello"))
            },
            onStableSnapshot: { _, _ in }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.setInsertionInProgress(true)
        monitor.poll(at: 0)
        monitor.setInsertionInProgress(false)
        monitor.poll(at: 0.1)

        XCTAssertEqual(captureCount, 1)
    }

    func testMarkingATypeThroughSnapshotHandledPreventsAReplacementRequest() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18)
        )
        var emitted: [ActiveFieldSnapshot] = []
        var monitor: ActiveFieldMonitor!
        monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) },
            onInvalidated: { snapshot, _ in
                if let snapshot { monitor.markHandled(snapshot) }
            }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        current = Self.snapshot(
            textBefore: "Hello w",
            caretBounds: CGRect(x: 132, y: 100, width: 0, height: 18)
        )
        monitor.poll(at: 0.31)
        monitor.poll(at: 0.61)

        XCTAssertEqual(emitted.map(\.textBefore), ["Hello"])
    }

    func testSameContentGeometryChangeReanchorsWithoutRequestingAgain() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        var emitted: [ActiveFieldSnapshot] = []
        var reanchored: [ActiveFieldSnapshot] = []
        var invalidated = 0
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) },
            onGeometryChanged: { snapshot, _ in reanchored.append(snapshot) },
            onInvalidated: { _, _ in invalidated += 1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 220, y: 160, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        monitor.poll(at: 0.31)

        XCTAssertTrue(reanchored.isEmpty)

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 221, y: 160, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        monitor.poll(at: 0.32)

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(reanchored.map(\.caretBounds), [current.caretBounds])
        XCTAssertEqual(invalidated, 0)
    }

    func testUpdatingTheSameSurroundingTextCannotStarveAnUnchangedDraft() {
        var current = Self.snapshot(textBefore: "My reply", fieldContext: Self.subjectContext(body: "Original context"))
        var emitted: [ActiveFieldSnapshot] = []
        var invalidated = 0
        let monitor = ActiveFieldMonitor(capture: { .captured(current) }, quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) },
            onInvalidated: { _, _ in invalidated += 1 })
        monitor.updateConfiguration(.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(textBefore: "My reply", fieldContext: Self.subjectContext(body: "Latest context before quiet"))
        monitor.poll(at: 0.2)
        monitor.poll(at: 0.3)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.fieldContext.relatedFields.first?.text, "Latest context before quiet")
        for tick in 1...10 {
            current = Self.snapshot(textBefore: "My reply", fieldContext: Self.subjectContext(body: "Surrounding update \(tick)"))
            monitor.poll(at: Double(tick))
            monitor.poll(at: Double(tick) + 0.31)
        }
        XCTAssertEqual(emitted.count, 1, "Do not repeatedly supersede an in-flight suggestion for the same draft")
        XCTAssertEqual(invalidated, 0)
        current = Self.snapshot(textBefore: "My edited reply", fieldContext: Self.subjectContext(body: "Newest context"))
        monitor.poll(at: 11)
        monitor.poll(at: 11.31)
        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(invalidated, 1)
        XCTAssertEqual(emitted.last?.fieldContext.relatedFields.first?.text, "Newest context")
    }

    func testRelatedContextEnrichmentImmediatelyInvalidatesTheField() {
        var current = Self.snapshot(
            textBefore: "",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            fieldContext: Self.subjectContext(body: "")
        )
        var emitted: [ActiveFieldSnapshot] = []
        var invalidated = 0
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) },
            onInvalidated: { _, _ in invalidated += 1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        current = Self.snapshot(
            textBefore: "",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            fieldContext: Self.subjectContext(body: "Mensaje para derivar")
        )
        monitor.poll(at: 0.31)
        monitor.poll(at: 0.61)

        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(emitted.last?.fieldContext.relatedFields.first?.text, "Mensaje para derivar")
        XCTAssertEqual(invalidated, 1)
    }

    func testOneFarOutlierCannotMoveAVisibleAnchor() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        var reanchored: [ActiveFieldSnapshot] = []
        var hidden = 0
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            onGeometryChanged: { snapshot, _ in reanchored.append(snapshot) },
            onGeometryHidden: { _ in hidden += 1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 900, y: 500, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        monitor.poll(at: 0.31)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240)
        )
        monitor.poll(at: 0.32)

        XCTAssertTrue(reanchored.isEmpty)
        XCTAssertEqual(hidden, 0)
    }

    func testTransientGeometryJitterDoesNotAdvanceTheFieldRevision() {
        let generation = ActiveFieldGeneration()
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 1
        )
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            generation: generation
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 2
        )
        monitor.poll(at: 0.1)
        let stableFieldRevision = generation.current

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 900, y: 500, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
            captureSequence: 3
        )
        monitor.poll(at: 0.2)

        XCTAssertEqual(generation.current, stableFieldRevision)
    }

    func testInitialFarSampleCannotBecomeTheStableSnapshot() {
        let samples = [
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 900, y: 500, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
                captureSequence: 1
            ),
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
                captureSequence: 2
            ),
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 121, y: 100, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
                captureSequence: 3
            ),
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
                captureSequence: 4
            ),
        ]
        var index = 0
        var emitted: [ActiveFieldSnapshot] = []
        let monitor = ActiveFieldMonitor(
            capture: {
                defer { index = min(index + 1, samples.count - 1) }
                return .captured(samples[index])
            },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.poll(at: 0)
        monitor.poll(at: 0.1)
        monitor.poll(at: 0.2)
        monitor.poll(at: 0.3)

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.caretBounds?.minX, 121)
        XCTAssertEqual(emitted.first?.captureSequence, 3)
    }

    func testContentChangeReanchorsToAuthoritativeCaretAfterTwoSamples() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 1
        )
        var reanchored: [ActiveFieldSnapshot] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryChanged: { snapshot, _ in reanchored.append(snapshot) }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)

        current = Self.snapshot(
            textBefore: "Hello f",
            caretBounds: CGRect(x: 132, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 3
        )
        monitor.poll(at: 0.02)
        current = Self.snapshot(
            textBefore: "Hello f",
            caretBounds: CGRect(x: 133, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 4
        )
        monitor.poll(at: 0.03)

        XCTAssertEqual(reanchored.map { $0.caretBounds?.minX }, [133])
        XCTAssertEqual(reanchored.map(\.captureSequence), [4])
    }

    func testGeometryProvenanceChangeKeepsAConcordantFieldAnchor() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 1
        )
        var hidden = 0
        var reanchored: [UInt64] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryChanged: { snapshot, _ in
                reanchored.append(snapshot.captureSequence)
            },
            onGeometryHidden: { _ in hidden += 1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 3,
            geometryQuality: .derived,
            geometrySource: .precedingGrapheme
        )
        monitor.poll(at: 0.02)
        XCTAssertEqual(hidden, 0)
        XCTAssertTrue(reanchored.isEmpty)
        XCTAssertEqual(
            monitor.stabilizedSnapshot(matching: current)?.captureSequence,
            3
        )

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 121, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 4,
            geometryQuality: .derived,
            geometrySource: .precedingGrapheme
        )
        monitor.poll(at: 0.03)
        XCTAssertTrue(reanchored.isEmpty)
        XCTAssertEqual(
            monitor.stabilizedSnapshot(matching: current)?.captureSequence,
            4
        )
    }

    func testConcordantCaptureRefreshesAcceptedSnapshotMetadata() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            captureSequence: 1
        )
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)
        let accepted = current

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 121, y: 100, width: 0, height: 18),
            captureSequence: 3
        )
        monitor.poll(at: 0.02)

        XCTAssertEqual(
            monitor.stabilizedSnapshot(matching: accepted)?.captureSequence,
            3
        )
        XCTAssertEqual(
            monitor.stabilizedSnapshot(matching: accepted)?.caretBounds?.minX,
            121
        )
    }

    func testStableContentCanBeEmittedBeforeInlineGeometryIsAvailable() {
        let unavailable = Self.snapshot(textBefore: "Hello", captureSequence: 1)
        var emitted: [ActiveFieldSnapshot] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(unavailable) },
            quietInterval: 0.3,
            onStableSnapshot: { snapshot, _ in emitted.append(snapshot) }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.poll(at: 0)
        monitor.poll(at: 0.3)

        XCTAssertEqual(emitted.map(\.textBefore), ["Hello"])
        XCTAssertNil(monitor.stabilizedSnapshot(matching: unavailable))
    }

    func testRefreshAfterInputSchedulesTwoCorroborationReadsAfterHostPublication() {
        var captureCount = 0
        var requestedDelays: [TimeInterval] = []
        var scheduled: [() -> Void] = []
        let monitor = ActiveFieldMonitor(
            capture: {
                captureCount += 1
                return .captured(Self.snapshot(textBefore: "Hello f"))
            },
            onStableSnapshot: { _, _ in },
            scheduleAfterHostPublication: { delay, work in
                requestedDelays.append(delay)
                scheduled.append(work)
            },
            now: { 0.1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.refreshAfterInput()

        XCTAssertEqual(captureCount, 0)
        XCTAssertEqual(requestedDelays, [0.012, 0.045])
        XCTAssertEqual(scheduled.count, 2)
        scheduled[0]()
        XCTAssertEqual(captureCount, 1)
        scheduled[1]()
        XCTAssertEqual(captureCount, 2)
    }

    func testNewerInputCancelsOlderScheduledPostInputCaptures() {
        var captures = 0
        var scheduled: [() -> Void] = []
        let monitor = ActiveFieldMonitor(
            capture: {
                captures += 1
                return .captured(Self.snapshot(textBefore: "latest"))
            },
            onStableSnapshot: { _, _ in },
            scheduleAfterHostPublication: { _, work in scheduled.append(work) },
            now: { 0.1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.refreshAfterInput()
        monitor.refreshAfterInput()
        XCTAssertEqual(scheduled.count, 4)

        scheduled[0]()
        scheduled[1]()
        XCTAssertEqual(captures, 0)
        scheduled[2]()
        XCTAssertEqual(captures, 1)
        scheduled[3]()
        XCTAssertEqual(captures, 2)
    }

    func testTransientFocusReadFailuresHoldTheObservation() {
        var monotonicMs = 0.0
        var result: ActiveFieldCaptureResult = .captured(
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18)
            )
        )
        var invalidations = 0
        var hidden = 0
        let generation = ActiveFieldGeneration()
        let monitor = ActiveFieldMonitor(
            capture: { result },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            onGeometryHidden: { _ in hidden += 1 },
            onInvalidated: { _, _ in invalidations += 1 },
            generation: generation,
            monotonicMilliseconds: { monotonicMs }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.1)
        let stable = generation.current

        result = .skipped(.accessibilityUnavailable)
        monotonicMs = 12
        monitor.poll(at: 0.2)
        monotonicMs = 45
        monitor.poll(at: 0.3)
        XCTAssertEqual(invalidations, 0)
        XCTAssertEqual(hidden, 0)
        XCTAssertEqual(generation.current, stable)

        result = .captured(
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
                captureSequence: 5
            )
        )
        monotonicMs = 60
        monitor.poll(at: 0.4)
        XCTAssertEqual(invalidations, 0)
        XCTAssertNotNil(monitor.stabilizedSnapshot(matching: Self.snapshot(textBefore: "Hello")))

        result = .skipped(.accessibilityUnavailable)
        monotonicMs = 70
        monitor.poll(at: 0.5)
        monotonicMs = 200
        monitor.poll(at: 0.6)
        monotonicMs = 321
        monitor.poll(at: 0.7)
        XCTAssertEqual(invalidations, 1)
        XCTAssertNil(monitor.stabilizedSnapshot(matching: Self.snapshot(textBefore: "Hello")))
    }

    func testTransientReadFailuresUseElapsedTimeAndRecoveryResetsTheWindow() {
        var monotonicMs = 0.0
        var result: ActiveFieldCaptureResult = .captured(
            Self.snapshot(textBefore: "Hello")
        )
        var invalidations = 0
        let monitor = ActiveFieldMonitor(
            capture: { result },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            onInvalidated: { _, _ in invalidations += 1 },
            monotonicMilliseconds: { monotonicMs },
            now: { monotonicMs / 1_000 }
        )
        monitor.updateConfiguration(.enabled)
        monitor.poll(at: 0)

        result = .skipped(.rangeMissing)
        for elapsed in [12.0, 45.0, 100.0] {
            monotonicMs = elapsed
            monitor.poll(at: elapsed / 1_000)
        }
        XCTAssertEqual(invalidations, 0)

        monotonicMs = 120
        result = .captured(Self.snapshot(textBefore: "Hello", captureSequence: 5))
        monitor.poll(at: 0.12)

        result = .skipped(.markerReadFailed)
        monotonicMs = 140
        monitor.poll(at: 0.14)
        monotonicMs = 389
        monitor.poll(at: 0.389)
        XCTAssertEqual(invalidations, 0)

        monotonicMs = 391
        monitor.poll(at: 0.391)
        XCTAssertEqual(invalidations, 1)
    }

    func testTransientRangeFailureHoldsTheVisibleObservation() {
        var result: ActiveFieldCaptureResult = .captured(
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18)
            )
        )
        var invalidations = 0
        let generation = ActiveFieldGeneration()
        let monitor = ActiveFieldMonitor(
            capture: { result },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            onInvalidated: { _, _ in invalidations += 1 },
            generation: generation
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        monitor.poll(at: 0.1)
        let stable = generation.current

        result = .skipped(.rangeMissing)
        monitor.poll(at: 0.2)
        monitor.poll(at: 0.3)

        XCTAssertEqual(invalidations, 0)
        XCTAssertEqual(generation.current, stable)
        XCTAssertNotNil(
            monitor.stabilizedSnapshot(matching: Self.snapshot(textBefore: "Hello"))
        )

        result = .captured(
            Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
                captureSequence: 5
            )
        )
        monitor.poll(at: 0.4)

        XCTAssertEqual(invalidations, 0)
        XCTAssertNotNil(monitor.stabilizedSnapshot(matching: Self.snapshot(textBefore: "Hello")))
    }

    func testSecureProhibitedAndExcludedFieldsInvalidateImmediately() {
        for reason in [
            ActiveFieldSkipReason.secureField,
            .unsupportedRole,
            .unsupportedApplication,
        ] {
            var result: ActiveFieldCaptureResult = .captured(
                Self.snapshot(textBefore: "Hello")
            )
            var invalidations = 0
            let monitor = ActiveFieldMonitor(
                capture: { result },
                quietInterval: 0.3,
                onStableSnapshot: { _, _ in },
                onInvalidated: { _, _ in invalidations += 1 }
            )
            monitor.updateConfiguration(.enabled)
            monitor.poll(at: 0)

            result = .skipped(reason)
            monitor.poll(at: 0.1)

            XCTAssertEqual(invalidations, 1, "\(reason)")
        }
    }

    func testExpectedPredictionIsConfirmedByOneConcordantAuthoritativeSample() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            captureSequence: 1
        )
        var hidden = 0
        var reanchored: [CGFloat] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryChanged: { snapshot, _ in
                reanchored.append(snapshot.caretBounds?.minX ?? -1)
            },
            onGeometryHidden: { _ in hidden += 1 },
            scheduleAfterHostPublication: { _, _ in }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)

        monitor.expect(
            Self.snapshot(
                textBefore: "Hello f",
                caretBounds: CGRect(x: 129, y: 100, width: 0, height: 18),
                captureSequence: 2
            )
        )
        monitor.refreshAfterInput()
        current = Self.snapshot(
            textBefore: "Hello f",
            caretBounds: CGRect(x: 128.5, y: 100, width: 0, height: 18),
            captureSequence: 3
        )
        monitor.poll(at: 0.02)

        XCTAssertEqual(hidden, 0)
        XCTAssertEqual(reanchored, [128.5])
        XCTAssertEqual(
            monitor.stabilizedSnapshot(matching: current)?.captureSequence,
            3
        )
    }

    func testExpectedPredictionThatTheHostContradictsIsHidden() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            captureSequence: 1
        )
        var hidden = 0
        var reanchored: [CGFloat] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryChanged: { snapshot, _ in
                reanchored.append(snapshot.caretBounds?.minX ?? -1)
            },
            onGeometryHidden: { _ in hidden += 1 },
            scheduleAfterHostPublication: { _, _ in }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)

        monitor.expect(
            Self.snapshot(
                textBefore: "Hello f",
                caretBounds: CGRect(x: 129, y: 100, width: 0, height: 18),
                captureSequence: 2
            )
        )
        monitor.refreshAfterInput()
        // The host wrapped the word to the next line instead.
        current = Self.snapshot(
            textBefore: "Hello f",
            caretBounds: CGRect(x: 48, y: 118, width: 0, height: 18),
            captureSequence: 3
        )
        monitor.poll(at: 0.02)
        XCTAssertEqual(hidden, 1)
        XCTAssertTrue(reanchored.isEmpty)

        current = Self.snapshot(
            textBefore: "Hello f",
            caretBounds: CGRect(x: 48.5, y: 118, width: 0, height: 18),
            captureSequence: 4
        )
        monitor.poll(at: 0.03)
        XCTAssertEqual(reanchored, [48.5])
    }

    func testRequestedReanchorRepublishesTheUnchangedStableAnchor() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            captureSequence: 1
        )
        var reanchored: [UInt64] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryChanged: { snapshot, _ in
                reanchored.append(snapshot.captureSequence)
            }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            captureSequence: 3
        )
        monitor.poll(at: 0.02)
        XCTAssertTrue(reanchored.isEmpty)

        monitor.requestReanchor()
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            captureSequence: 4
        )
        monitor.poll(at: 0.03)

        XCTAssertEqual(reanchored, [4])
    }

    func testOutOfOrderPostInputClosuresOnlyRunTheNewestGeneration() {
        var captures = 0
        var scheduled: [() -> Void] = []
        let monitor = ActiveFieldMonitor(
            capture: {
                captures += 1
                return .captured(Self.snapshot(textBefore: "latest"))
            },
            onStableSnapshot: { _, _ in },
            scheduleAfterHostPublication: { _, work in scheduled.append(work) }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)

        monitor.refreshAfterInput()
        monitor.refreshAfterInput()
        scheduled[1]()
        scheduled[0]()
        XCTAssertEqual(captures, 0)
        scheduled[3]()
        scheduled[2]()

        XCTAssertEqual(captures, 2)
    }

    func testDisableReenableInvalidatesScheduledPostInputCapture() {
        var captures = 0
        var scheduled: (() -> Void)?
        let monitor = ActiveFieldMonitor(
            capture: {
                captures += 1
                return .captured(Self.snapshot(textBefore: "latest"))
            },
            onStableSnapshot: { _, _ in },
            scheduleAfterHostPublication: { _, work in scheduled = work }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.refreshAfterInput()

        monitor.updateConfiguration(.disabled)
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        scheduled?()

        XCTAssertEqual(captures, 0)
    }

    func testInsertionBoundaryInvalidatesScheduledPostInputCapture() {
        var captures = 0
        var scheduled: (() -> Void)?
        let monitor = ActiveFieldMonitor(
            capture: {
                captures += 1
                return .captured(Self.snapshot(textBefore: "latest"))
            },
            onStableSnapshot: { _, _ in },
            scheduleAfterHostPublication: { _, work in scheduled = work }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.refreshAfterInput()

        monitor.setInsertionInProgress(true)
        monitor.setInsertionInProgress(false)
        scheduled?()

        XCTAssertEqual(captures, 0)
    }

    func testAlreadyEnqueuedCallbackIsRejectedAfterNewInputGeneration() {
        let generation = ActiveFieldGeneration()
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            captureSequence: 1
        )
        var enqueued: [() -> Void] = []
        var deliveries = 0
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            quietInterval: 0.3,
            onStableSnapshot: { _, callbackGeneration in
                enqueued.append {
                    if generation.isCurrent(callbackGeneration) {
                        deliveries += 1
                    }
                }
            },
            generation: generation,
            scheduleAfterHostPublication: { _, _ in }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 121, y: 100, width: 0, height: 18),
            captureSequence: 2
        )
        monitor.poll(at: 0.3)
        XCTAssertEqual(enqueued.count, 1)

        monitor.refreshAfterInput()
        enqueued[0]()

        XCTAssertEqual(deliveries, 0)
    }

    func testSupersededInFlightCaptureCannotClearCurrentObservation() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            captureSequence: 1
        )
        var supersedeDuringCapture = false
        var invalidated: [String] = []
        var monitor: ActiveFieldMonitor!
        monitor = ActiveFieldMonitor(
            capture: {
                if supersedeDuringCapture {
                    supersedeDuringCapture = false
                    monitor.refreshAfterInput()
                }
                return .captured(current)
            },
            quietInterval: 0.3,
            onStableSnapshot: { _, _ in },
            onInvalidated: { snapshot, _ in
                if let snapshot { invalidated.append(snapshot.textBefore) }
            },
            scheduleAfterHostPublication: { _, _ in }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 121, y: 100, width: 0, height: 18),
            captureSequence: 2
        )
        monitor.poll(at: 0.3)

        supersedeDuringCapture = true
        current = Self.snapshot(
            textBefore: "stale",
            caretBounds: CGRect(x: 130, y: 100, width: 0, height: 18),
            captureSequence: 3
        )
        monitor.poll(at: 0.31)

        current = Self.snapshot(
            textBefore: "latest",
            caretBounds: CGRect(x: 140, y: 100, width: 0, height: 18),
            captureSequence: 4
        )
        monitor.poll(at: 0.32)

        XCTAssertEqual(invalidated, ["latest"])
    }

    func testMissingGeometryHidesAnAcceptedAnchorImmediately() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 1
        )
        var hidden = 0
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryHidden: { _ in hidden += 1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)

        current = Self.snapshot(
            textBefore: "Hello",
            captureSequence: 3
        )
        monitor.poll(at: 0.02)

        XCTAssertEqual(hidden, 1)
    }

    func testWindowMovementHidesThenRequiresTwoConcordantSamplesToReanchor() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 1
        )
        var hidden = 0
        var reanchored: [CGRect?] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryChanged: { snapshot, _ in
                reanchored.append(snapshot.caretBounds)
            },
            onGeometryHidden: { _ in hidden += 1 }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 320, y: 180, width: 0, height: 18),
            inputFrame: CGRect(x: 240, y: 140, width: 360, height: 240),
            captureSequence: 3
        )
        monitor.poll(at: 0.02)
        XCTAssertEqual(hidden, 1)
        XCTAssertTrue(reanchored.isEmpty)

        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 320.5, y: 180, width: 0, height: 18),
            inputFrame: CGRect(x: 240, y: 140, width: 360, height: 240),
            captureSequence: 4
        )
        monitor.poll(at: 0.03)

        XCTAssertEqual(reanchored, [current.caretBounds])
    }

    func testContentInvalidationIsPublishedBeforeAnchorHide() {
        var current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 1
        )
        var events: [String] = []
        let monitor = ActiveFieldMonitor(
            capture: { .captured(current) },
            onStableSnapshot: { _, _ in },
            onGeometryHidden: { _ in events.append("hidden") },
            onInvalidated: { _, _ in events.append("invalidated") }
        )
        monitor.updateConfiguration(CaptureConfiguration.enabled)
        monitor.poll(at: 0)
        current = Self.snapshot(
            textBefore: "Hello",
            caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 2
        )
        monitor.poll(at: 0.01)

        current = Self.snapshot(
            textBefore: "Hello f",
            caretBounds: CGRect(x: 128, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
            captureSequence: 3
        )
        monitor.poll(at: 0.02)

        XCTAssertEqual(events, ["invalidated", "hidden"])
    }

    func testParagraphRenderMetricChangesDoNotDestabilizeAConcordantCaret() {
        var tail = ActiveFieldParagraphAttributes.plain
        tail.tailIndent = -24
        var spaced = ActiveFieldParagraphAttributes.plain
        spaced.lineSpacing = 4
        var listed = ActiveFieldParagraphAttributes.plain
        listed.listMarker = "•"
        listed.listLevel = 1

        for (label, changedAttributes) in [
            ("tail-indent", tail),
            ("line-spacing", spaced),
            ("list-style", listed),
        ] {
            var current = Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
                captureSequence: 1,
                paragraphMetrics: Self.paragraphMetrics()
            )
            var hidden = 0
            var reanchored: [UInt64] = []
            let monitor = ActiveFieldMonitor(
                capture: { .captured(current) },
                onStableSnapshot: { _, _ in },
                onGeometryChanged: { snapshot, _ in
                    reanchored.append(snapshot.captureSequence)
                },
                onGeometryHidden: { _ in hidden += 1 }
            )
            monitor.updateConfiguration(CaptureConfiguration.enabled)
            monitor.poll(at: 0)
            current = Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
                captureSequence: 2,
                paragraphMetrics: Self.paragraphMetrics()
            )
            monitor.poll(at: 0.01)

            current = Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120, y: 100, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
                captureSequence: 3,
                paragraphMetrics: Self.paragraphMetrics(
                    attributes: changedAttributes
                )
            )
            monitor.poll(at: 0.02)
            XCTAssertEqual(hidden, 0, label)
            XCTAssertTrue(reanchored.isEmpty, label)
            XCTAssertEqual(
                monitor.stabilizedSnapshot(matching: current)?.captureSequence,
                3,
                label
            )

            current = Self.snapshot(
                textBefore: "Hello",
                caretBounds: CGRect(x: 120.5, y: 100, width: 0, height: 18),
                inputFrame: CGRect(x: 40, y: 60, width: 360, height: 240),
                captureSequence: 4,
                paragraphMetrics: Self.paragraphMetrics(
                    attributes: changedAttributes
                )
            )
            monitor.poll(at: 0.03)
            XCTAssertTrue(reanchored.isEmpty, label)
        }
    }

    func testParagraphRenderFingerprintContainsNoParagraphText() {
        var first = Self.paragraphMetrics()
        first.textBeforeCaret = "fixture A"
        var second = Self.paragraphMetrics()
        second.textBeforeCaret = "fixture B"
        let firstSnapshot = Self.snapshot(
            textBefore: "same host context",
            paragraphMetrics: first
        )
        let secondSnapshot = Self.snapshot(
            textBefore: "same host context",
            paragraphMetrics: second
        )

        XCTAssertEqual(
            firstSnapshot.paragraphRenderFingerprint,
            secondSnapshot.paragraphRenderFingerprint
        )
    }

    func testSourceTextUpdatesPreserveDraftButChangingReplyTargetInvalidatesIt() {
        func snapshot(id: String, body: String, otherFirst: Bool = false) -> ActiveFieldSnapshot {
            let source = FieldSource(id: id, containerId: "conversation", relation: .sharedContainer, text: body)
            let other = FieldSource(id: "hint", containerId: "composer", relation: .describedBy, text: "Helper hint")
            return Self.snapshot(textBefore: "My reply", fieldContext: ActiveFieldContext(
                shape: .multiline, sources: otherFirst ? [other, source] : [source, other]))
        }
        let first = snapshot(id: "message-a", body: "Original message")
        let streaming = snapshot(id: "message-a", body: "Message updated while generating", otherFirst: true)
        let newTarget = snapshot(id: "message-b", body: "Different conversation")
        XCTAssertEqual(first.contentSignature, streaming.contentSignature)
        XCTAssertNotEqual(first.contentSignature, newTarget.contentSignature)
        XCTAssertNotEqual(first.fieldContext, streaming.fieldContext)
    }

    func testRelatedContextRevisionIsSeparateFromDraftInsertionIdentity() {
        let first = Self.snapshot(
            textBefore: "",
            fieldContext: Self.subjectContext(body: "Primera versión del mensaje")
        )
        let second = Self.snapshot(
            textBefore: "",
            fieldContext: Self.subjectContext(body: "Mensaje actualizado")
        )

        XCTAssertEqual(first.contentSignature, second.contentSignature)
        XCTAssertNotEqual(first.fieldContext, second.fieldContext)
        XCTAssertEqual(first.requestSignature, second.requestSignature)
    }

    private static func snapshot(
        textBefore: String,
        focusGeneration: UInt64 = 1,
        caretBounds: CGRect? = nil,
        inputFrame: CGRect? = nil,
        captureSequence: UInt64 = 0,
        paragraphMetrics: ActiveFieldParagraphMetrics? = nil,
        geometryQuality: GeometryQuality? = nil,
        geometrySource: CaretGeometrySource? = nil,
        fieldContext: ActiveFieldContext? = nil
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Notes",
            elementIdentifier: "notes-field",
            focusGeneration: focusGeneration,
            textBefore: textBefore,
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: textBefore.utf16.count, length: 0),
            caretBounds: caretBounds,
            inputFrame: inputFrame,
            geometryQuality: geometryQuality
                ?? (caretBounds == nil ? .unavailable : .exact),
            geometrySource: geometrySource
                ?? (caretBounds == nil ? nil : .zeroLengthRange),
            captureSequence: captureSequence,
            paragraphMetrics: paragraphMetrics,
            fieldContext: fieldContext
        )
    }

    private static func subjectContext(body: String) -> ActiveFieldContext {
        ActiveFieldContext(
            shape: .singleLine,
            placeholder: "Subject",
            relatedFields: [
                RelatedFieldContext(
                    shape: .multiline,
                    label: "Message Body",
                    placeholder: nil,
                    text: body
                )
            ]
        )
    }

    private static func paragraphMetrics(
        attributes: ActiveFieldParagraphAttributes = .plain
    ) -> ActiveFieldParagraphMetrics {
        let style = ActiveFieldTextStyle(
            fontName: ".AppleSystemUIFont",
            fontSize: 13
        )
        return ActiveFieldParagraphMetrics(
            textBeforeCaret: "Hello",
            origin: CGPoint(x: 40, y: 118),
            width: 360,
            lineHeight: 18,
            writingDirection: .leftToRight,
            textStyle: style,
            prefixStyleRuns: [
                .init(
                    range: NSRange(location: 0, length: 5),
                    style: style
                ),
            ],
            attributes: attributes
        )
    }
}

private final class MonitorTimelineLines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ line: String) {
        lock.withLock { storage.append(line) }
    }
}
