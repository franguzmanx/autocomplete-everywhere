import Foundation
import XCTest
@testable import AutocompleteHelper

final class HelperTimelineTracerTests: XCTestCase {
    func testOverflowTimelineRetainsRequestAndOnlyBoundedMeasurements() throws {
        let lines = LockedTimelineLines()
        let tracer = HelperTimelineTracer(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            dispatch: { $0() }, sink: { lines.append($0) })
        let identity = SuggestionRequestMessage.Identity(requestId: "8D475E53-0134-444C-9EF3-529AF64903F1",
            focusSequence: 7, contentSignature: "PRIVATE", timestampMs: 100)
        tracer.presentationOverflow(identity: identity, overflow: GhostTextOverflow(
            frame: CGRect(x: 0, y: -40, width: 101.5, height: 60),
            visibleField: CGRect(x: 0, y: 0, width: 100, height: 20),
            caret: CGRect(x: 0, y: 0, width: 1, height: 20), lineHeight: 20, completionLines: 3))
        let event = try Self.decode(XCTUnwrap(lines.values.first))
        XCTAssertEqual(event["event"] as? String, "presentation_overflow")
        XCTAssertEqual(event["requestId"] as? String, identity.requestId)
        let attrs = try XCTUnwrap(event["attrs"] as? [String: Any])
        XCTAssertEqual(attrs["right"] as? String, "small")
        XCTAssertEqual(attrs["bottom"] as? String, "multiple_lines")
        XCTAssertEqual(attrs["availableLines"] as? Int, 1)
        XCTAssertEqual(Set(attrs.keys), Set(["left", "right", "top", "bottom", "completionLines", "availableLines", "fitting"]))
        XCTAssertEqual(attrs["fitting"] as? String, GhostTextOverflow.Fitting.notAllowed.rawValue)
        XCTAssertFalse(lines.values.joined().contains("PRIVATE"))
    }

    func testRepeatedIdleSkipsKeepPeriodicCountsWithoutWritingEveryPoll() throws {
        let lines = LockedTimelineLines()
        var now = 0.0
        let tracer = HelperTimelineTracer(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            monotonicMilliseconds: { now }, dispatch: { $0() }, sink: { lines.append($0) }
        )
        for sample in 0..<100 {
            now = Double(sample * 100)
            tracer.captureSkipped(focusSequence: nil, reason: .unsupportedApplication,
                                  consecutive: sample + 1, sinceLastOKMilliseconds: nil)
        }
        let events = try lines.values.map(Self.decode)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.compactMap { ($0["attrs"] as? [String: Any])?["consecutive"] as? Int }, [1, 51])
    }

    func testSkipTransitionsAndNewFailureEpisodeAreReportedImmediately() throws {
        let lines = LockedTimelineLines()
        let tracer = HelperTimelineTracer(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            monotonicMilliseconds: { 100 }, dispatch: { $0() }, sink: { lines.append($0) }
        )
        for (focus, reason, count) in [
            (UInt64(1), ActiveFieldSkipReason.valueMissing, 1),
            (1, .valueMissing, 2),
            (1, .rangeMissing, 3),
            (2, .rangeMissing, 4),
            (2, .rangeMissing, 5),
            (2, .rangeMissing, 1)
        ] {
            tracer.captureSkipped(focusSequence: focus, reason: reason,
                                  consecutive: count, sinceLastOKMilliseconds: nil)
        }
        let events = try lines.values.map(Self.decode)
        XCTAssertEqual(events.compactMap { ($0["attrs"] as? [String: Any])?["consecutive"] as? Int }, [1, 3, 4, 1])
    }

    func testEmitsOnlyAllowlistedContentFreeTimelineFields() throws {
        let lines = LockedTimelineLines()
        var monotonicMs = 100.0
        var wallMs: Int64 = 1_788_530_537_021
        let tracer = HelperTimelineTracer(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            monotonicMilliseconds: { monotonicMs },
            wallMilliseconds: { wallMs },
            dispatch: { work in work() },
            sink: { lines.append($0) }
        )
        let identity = SuggestionRequestMessage.Identity(
            requestId: "8D475E53-0134-444C-9EF3-529AF64903F1",
            focusSequence: 7,
            contentSignature: String(repeating: "a", count: 64),
            timestampMs: wallMs
        )

        tracer.inputObserved(
            focusSequence: 7,
            captureSequence: 11,
            captureMilliseconds: 12.5
        )
        tracer.contentStable(focusSequence: 7, quietMilliseconds: 305)
        tracer.requestWritten(
            identity: identity,
            surface: .web,
            shape: .multiline,
            textBeforeUTF16Count: 47,
            textAfterUTF16Count: 0,
            hasSelection: false,
            relatedFieldCount: 4,
            geometryQuality: .derived,
            anchorResolved: true,
            explicit: true
        )
        monotonicMs = 400
        wallMs += 300
        tracer.responseReceived(
            identity: identity,
            disposition: .accepted
        )
        monotonicMs = 425
        wallMs += 25
        tracer.presented(identity: identity)
        monotonicMs = 600
        wallMs += 175
        tracer.interaction(identity: identity, outcome: .acceptedFull)

        let events = try lines.values.map(Self.decode)
        XCTAssertEqual(
            events.map { $0["event"] as? String },
            [
                "input_observed",
                "content_stable",
                "request_written",
                "final_received",
                "presented",
                "interaction",
            ]
        )
        XCTAssertEqual(events[0]["focusSequence"] as? Int, 7)
        XCTAssertNil(events[0]["requestId"])
        XCTAssertEqual(events[2]["requestId"] as? String, identity.requestId)
        XCTAssertEqual(events[2]["proc"] as? String, "helper")
        XCTAssertEqual(events[2]["v"] as? Int, 1)

        let requestAttrs = try XCTUnwrap(events[2]["attrs"] as? [String: Any])
        XCTAssertEqual(requestAttrs["surface"] as? String, "web")
        XCTAssertEqual(requestAttrs["shape"] as? String, "multiline")
        XCTAssertEqual(requestAttrs["textBeforeBucket"] as? String, "lt_100")
        XCTAssertEqual(requestAttrs["textAfterBucket"] as? String, "zero")
        XCTAssertEqual(requestAttrs["hasSelection"] as? Bool, false)
        XCTAssertEqual(requestAttrs["related"] as? Int, 3)
        XCTAssertEqual(requestAttrs["geometry"] as? String, "derived")
        XCTAssertEqual(requestAttrs["anchorResolved"] as? Bool, true)
        XCTAssertEqual(requestAttrs["explicit"] as? Bool, true)

        let finalAttrs = try XCTUnwrap(events[3]["attrs"] as? [String: Any])
        XCTAssertEqual(finalAttrs["sinceRequestMs"] as? Double, 300)
        XCTAssertEqual(finalAttrs["disposition"] as? String, "accepted")
        let presentedAttrs = try XCTUnwrap(events[4]["attrs"] as? [String: Any])
        XCTAssertEqual(presentedAttrs["sinceFinalMs"] as? Double, 25)
        XCTAssertEqual(presentedAttrs["anchorWaitMs"] as? Double, 25)
        let interactionAttrs = try XCTUnwrap(events[5]["attrs"] as? [String: Any])
        XCTAssertEqual(interactionAttrs["outcome"] as? String, "accepted_full")
        XCTAssertEqual(interactionAttrs["sinceShownMs"] as? Double, 175)

        let serialized = lines.values.joined()
        XCTAssertFalse(serialized.contains("TOP SECRET"))
        XCTAssertFalse(serialized.contains("com.apple.Notes"))
        XCTAssertFalse(serialized.contains(identity.contentSignature))
    }

    func testCapturesSkipCancellationAndPresentationRejectionAsCodes() throws {
        let lines = LockedTimelineLines()
        var monotonicMs = 100.0
        let tracer = HelperTimelineTracer(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            monotonicMilliseconds: { monotonicMs },
            wallMilliseconds: { 1_788_530_537_021 },
            dispatch: { work in work() },
            sink: { lines.append($0) }
        )
        let identity = SuggestionRequestMessage.Identity(
            requestId: "8D475E53-0134-444C-9EF3-529AF64903F1",
            focusSequence: 7,
            contentSignature: String(repeating: "b", count: 64),
            timestampMs: 1_788_530_537_021
        )

        tracer.captureSkipped(
            focusSequence: 7,
            reason: .rangeOutOfBounds,
            consecutive: 3,
            sinceLastOKMilliseconds: 91
        )
        tracer.requestWritten(
            identity: identity,
            surface: .native,
            shape: .singleLine,
            textBeforeUTF16Count: 0,
            textAfterUTF16Count: 120,
            hasSelection: true,
            relatedFieldCount: 0,
            geometryQuality: .unavailable,
            anchorResolved: false,
            explicit: false
        )
        monotonicMs = 240
        tracer.presentRejected(
            identity: identity,
            rejection: .anchorUnavailable,
            anchorWaitMilliseconds: 140
        )
        monotonicMs = 250
        tracer.cancelWritten(
            identity: identity,
            reason: .contentChanged,
            typedAppend: true
        )

        let events = try lines.values.map(Self.decode)
        XCTAssertEqual(
            events.map { $0["event"] as? String },
            ["capture_skipped", "request_written", "present_rejected", "cancel_written"]
        )
        let skipAttrs = try XCTUnwrap(events[0]["attrs"] as? [String: Any])
        XCTAssertEqual(skipAttrs["reason"] as? String, "range_out_of_bounds")
        XCTAssertEqual(skipAttrs["consecutive"] as? Int, 3)
        XCTAssertEqual(skipAttrs["sinceLastOkMs"] as? Double, 91)
        let requestAttrs = try XCTUnwrap(events[1]["attrs"] as? [String: Any])
        XCTAssertEqual(requestAttrs["textBeforeBucket"] as? String, "zero")
        XCTAssertEqual(requestAttrs["textAfterBucket"] as? String, "lt_1k")
        XCTAssertEqual(requestAttrs["hasSelection"] as? Bool, true)
        XCTAssertEqual(requestAttrs["explicit"] as? Bool, false)
        let rejectionAttrs = try XCTUnwrap(events[2]["attrs"] as? [String: Any])
        XCTAssertEqual(rejectionAttrs["rejection"] as? String, "anchor_unavailable")
        XCTAssertEqual(rejectionAttrs["sinceFinalMs"] as? Double, 140)
        XCTAssertEqual(rejectionAttrs["anchorWaitMs"] as? Double, 140)
        let cancelAttrs = try XCTUnwrap(events[3]["attrs"] as? [String: Any])
        XCTAssertEqual(cancelAttrs["reason"] as? String, "content_changed")
        XCTAssertEqual(cancelAttrs["sessionState"] as? String, "requesting")
        XCTAssertEqual(cancelAttrs["typedAppend"] as? Bool, true)
    }

    func testIsSilentWhenRuntimeDiagnosticsAreDisabled() {
        let lines = LockedTimelineLines()
        let tracer = HelperTimelineTracer(
            environment: [:],
            dispatch: { work in work() },
            sink: { lines.append($0) }
        )

        tracer.inputObserved(
            focusSequence: 1,
            captureSequence: 1,
            captureMilliseconds: 1
        )

        XCTAssertTrue(lines.values.isEmpty)
    }

    private static func decode(_ line: String) throws -> [String: Any] {
        XCTAssertTrue(line.hasPrefix("timeline:"))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(line.dropFirst("timeline:".count).utf8)
            ) as? [String: Any]
        )
    }
}

private final class LockedTimelineLines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ line: String) {
        lock.withLock { storage.append(line) }
    }
}
