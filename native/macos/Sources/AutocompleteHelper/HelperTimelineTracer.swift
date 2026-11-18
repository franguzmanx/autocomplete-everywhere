import Foundation

enum HelperPresentationRejection: String, Sendable {
    case sessionUnavailable = "session_unavailable"
    case anchorUnavailable = "anchor_unavailable"
    case sourceChanged = "source_changed"
    case anchorReacquiring = "anchor_reacquiring"
    case anchorValidation = "anchor_validation"
    case presenterStaleCapture = "presenter_stale_capture"
    case presenterParagraphEmptyCompletion = "presenter_paragraph_empty_completion"
    case presenterParagraphFocusChanged = "presenter_paragraph_focus_changed"
    case presenterParagraphCaptureUnavailable = "presenter_paragraph_capture_unavailable"
    case presenterParagraphSelectionActive = "presenter_paragraph_selection_active"
    case presenterParagraphNotAtEnd = "presenter_paragraph_not_at_end"
    case presenterParagraphGeometryUnavailable = "presenter_paragraph_geometry_unavailable"
    case presenterParagraphCaretUnavailable = "presenter_paragraph_caret_unavailable"
    case presenterParagraphFieldUnavailable = "presenter_paragraph_field_unavailable"
    case presenterParagraphCaretInvalid = "presenter_paragraph_caret_invalid"
    case presenterParagraphFieldInvalid = "presenter_paragraph_field_invalid"
    case presenterParagraphCaretOutsideField = "presenter_paragraph_caret_outside_field"
    case presenterParagraphDisplayUnavailable = "presenter_paragraph_display_unavailable"
    case presenterParagraphMetricsUnavailable = "presenter_paragraph_metrics_unavailable"
    case presenterParagraphPrefixMismatch = "presenter_paragraph_prefix_mismatch"
    case presenterParagraphLayout = "presenter_paragraph_layout"
    case presenterParagraphOutsideVisibleField = "presenter_paragraph_outside_visible_field"
    case presenterSingleLineLayout = "presenter_single_line_layout"
    case presenterDisplayRejected = "presenter_display_rejected"
}

protocol HelperTimelineTracing: AnyObject, Sendable {
    func inputObserved(
        focusSequence: UInt64,
        captureSequence: UInt64,
        captureMilliseconds: Double
    )
    func contentStable(focusSequence: UInt64, quietMilliseconds: Double)
    func captureSkipped(
        focusSequence: UInt64?,
        reason: ActiveFieldSkipReason,
        consecutive: Int,
        sinceLastOKMilliseconds: Double?
    )
    func requestWritten(
        identity: SuggestionRequestMessage.Identity,
        surface: WritingSurface,
        shape: ActiveFieldShape,
        textBeforeUTF16Count: Int,
        textAfterUTF16Count: Int,
        hasSelection: Bool,
        relatedFieldCount: Int,
        geometryQuality: GeometryQuality,
        anchorResolved: Bool,
        explicit: Bool
    )
    func responseReceived(
        identity: SuggestionRequestMessage.Identity,
        disposition: SuggestionResponseDisposition
    )
    func presentRejected(
        identity: SuggestionRequestMessage.Identity,
        rejection: HelperPresentationRejection,
        anchorWaitMilliseconds: Double?
    )
    func presented(identity: SuggestionRequestMessage.Identity)
    func cancelWritten(
        identity: SuggestionRequestMessage.Identity,
        reason: CancelRequestReason,
        typedAppend: Bool
    )
    func interaction(
        identity: SuggestionRequestMessage.Identity,
        outcome: InteractionOutcome
    )
}

final class HelperTimelineTracer: HelperTimelineTracing, @unchecked Sendable {
    typealias Dispatcher = (@escaping @Sendable () -> Void) -> Void
    typealias Sink = @Sendable (String) -> Void

    private enum RequestState: String {
        case requesting
        case ready
    }

    private struct RequestTiming {
        var requestMs: Double
        var finalMs: Double?
        var shownMs: Double?
        var state: RequestState
    }

    private enum Value: Encodable {
        case string(String)
        case integer(Int)
        case unsigned(UInt64)
        case double(Double)
        case boolean(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value): try container.encode(value)
            case let .integer(value): try container.encode(value)
            case let .unsigned(value): try container.encode(value)
            case let .double(value): try container.encode(value)
            case let .boolean(value): try container.encode(value)
            }
        }
    }

    private struct Event: Encodable {
        let v = 1
        let requestId: String?
        let focusSequence: UInt64?
        let proc = "helper"
        let event: String
        let monoMs: Double
        let wallMs: Int64
        let attrs: [String: Value]
    }

    private let enabled: Bool
    private let monotonicMilliseconds: () -> Double
    private let wallMilliseconds: () -> Int64
    private let dispatch: Dispatcher
    private let sink: Sink
    private let lock = NSLock()
    private var requests: [String: RequestTiming] = [:]
    private var lastSkip: (focus: UInt64?, reason: ActiveFieldSkipReason, count: Int, emittedMs: Double)?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        monotonicMilliseconds: @escaping () -> Double = {
            ProcessInfo.processInfo.systemUptime * 1_000
        },
        wallMilliseconds: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        },
        dispatch: Dispatcher? = nil,
        sink: @escaping Sink = { line in
            guard let data = line.data(using: .utf8) else { return }
            FileHandle.standardError.write(data)
        }
    ) {
        enabled = environment["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS"] == "1"
        self.monotonicMilliseconds = monotonicMilliseconds
        self.wallMilliseconds = wallMilliseconds
        if let dispatch {
            self.dispatch = dispatch
        } else {
            let queue = DispatchQueue(label: "com.autocompletion.helper-timeline")
            self.dispatch = { work in queue.async(execute: work) }
        }
        self.sink = sink
    }

    func inputObserved(
        focusSequence: UInt64,
        captureSequence: UInt64,
        captureMilliseconds: Double
    ) {
        emit(
            event: "input_observed",
            focusSequence: focusSequence,
            attrs: [
                "captureSeq": .unsigned(captureSequence),
                "captureMs": .double(Self.duration(captureMilliseconds)),
            ]
        )
    }

    func contentStable(focusSequence: UInt64, quietMilliseconds: Double) {
        emit(
            event: "content_stable",
            focusSequence: focusSequence,
            attrs: ["quietMs": .double(Self.duration(quietMilliseconds))]
        )
    }

    func captureSkipped(
        focusSequence: UInt64?,
        reason: ActiveFieldSkipReason,
        consecutive: Int,
        sinceLastOKMilliseconds: Double?
    ) {
        guard enabled else { return }
        let now = monotonicMilliseconds()
        let count = max(1, consecutive)
        let shouldEmit = lock.withLock {
            if let previous = lastSkip,
               previous.focus == focusSequence, previous.reason == reason,
               count > previous.count, now - previous.emittedMs < 5_000 {
                lastSkip = (focusSequence, reason, count, previous.emittedMs)
                return false
            }
            lastSkip = (focusSequence, reason, count, now)
            return true
        }
        guard shouldEmit else { return }
        var attrs: [String: Value] = [
            "reason": .string(Self.skipReason(reason)),
            "consecutive": .integer(count),
        ]
        if let sinceLastOKMilliseconds {
            attrs["sinceLastOkMs"] = .double(Self.duration(sinceLastOKMilliseconds))
        }
        emit(event: "capture_skipped", focusSequence: focusSequence, monoMs: now, attrs: attrs)
    }

    func requestWritten(
        identity: SuggestionRequestMessage.Identity,
        surface: WritingSurface,
        shape: ActiveFieldShape,
        textBeforeUTF16Count: Int,
        textAfterUTF16Count: Int,
        hasSelection: Bool,
        relatedFieldCount: Int,
        geometryQuality: GeometryQuality,
        anchorResolved: Bool,
        explicit: Bool
    ) {
        let requestMs = monotonicMilliseconds()
        lock.withLock {
            if requests.count >= 128,
               let oldest = requests.min(by: { $0.value.requestMs < $1.value.requestMs })?.key
            {
                requests.removeValue(forKey: oldest)
            }
            requests[identity.requestId] = RequestTiming(
                requestMs: requestMs,
                state: .requesting
            )
        }
        emit(
            event: "request_written",
            identity: identity,
            monoMs: requestMs,
            attrs: [
                "surface": .string(surface.rawValue),
                "shape": .string(shape.rawValue),
                "textBeforeBucket": .string(Self.textBucket(textBeforeUTF16Count)),
                "textAfterBucket": .string(Self.textBucket(textAfterUTF16Count)),
                "hasSelection": .boolean(hasSelection),
                "related": .integer(min(max(relatedFieldCount, 0), 3)),
                "geometry": .string(Self.geometry(geometryQuality)),
                "anchorResolved": .boolean(anchorResolved),
                "explicit": .boolean(explicit),
            ]
        )
    }

    func responseReceived(
        identity: SuggestionRequestMessage.Identity,
        disposition: SuggestionResponseDisposition
    ) {
        let now = monotonicMilliseconds()
        let sinceRequest = lock.withLock { () -> Double in
            guard var timing = requests[identity.requestId] else {
                return Self.duration(Double(wallMilliseconds() - identity.timestampMs))
            }
            if disposition == .accepted {
                timing.state = .ready
                timing.finalMs = now
                requests[identity.requestId] = timing
            }
            return Self.duration(now - timing.requestMs)
        }
        emit(
            event: "final_received",
            identity: identity,
            monoMs: now,
            attrs: [
                "sinceRequestMs": .double(sinceRequest),
                "disposition": .string(Self.disposition(disposition)),
            ]
        )
    }

    func presentRejected(
        identity: SuggestionRequestMessage.Identity,
        rejection: HelperPresentationRejection,
        anchorWaitMilliseconds: Double?
    ) {
        let now = monotonicMilliseconds()
        let sinceFinal = lock.withLock {
            let timing = requests[identity.requestId]
            return Self.duration(now - (timing?.finalMs ?? timing?.requestMs ?? now))
        }
        emit(
            event: "present_rejected",
            identity: identity,
            monoMs: now,
            attrs: [
                "sinceFinalMs": .double(sinceFinal),
                "anchorWaitMs": .double(
                    Self.duration(anchorWaitMilliseconds ?? sinceFinal)
                ),
                "rejection": .string(rejection.rawValue),
            ]
        )
    }

    func typography(identity: SuggestionRequestMessage.Identity, measurement: GhostTypographyMeasurement) {
        emit(event: "typography_measured", identity: identity, attrs: [
            "empty": .boolean(measurement.empty), "estimated": .boolean(measurement.estimated),
            "fontSize": .double(measurement.fontSize), "caretHeight": .double(measurement.caretHeight),
            "inputHeight": .double(measurement.inputHeight), "paragraph": .boolean(measurement.paragraph)
        ])
    }

    func presentationOverflow(identity: SuggestionRequestMessage.Identity, overflow: GhostTextOverflow) {
        emit(event: "presentation_overflow", identity: identity, attrs: [
            "left": .string(overflow.left.rawValue), "right": .string(overflow.right.rawValue),
            "top": .string(overflow.top.rawValue), "bottom": .string(overflow.bottom.rawValue),
            "completionLines": .integer(overflow.completionLines),
            "availableLines": .integer(overflow.availableLines),
            "fitting": .string(overflow.fitting.rawValue),
        ])
    }

    func presented(identity: SuggestionRequestMessage.Identity) {
        let now = monotonicMilliseconds()
        let sinceFinal = lock.withLock { () -> Double in
            guard var timing = requests[identity.requestId] else { return 0 }
            let elapsed = Self.duration(now - (timing.finalMs ?? timing.requestMs))
            if timing.shownMs == nil { timing.shownMs = now }
            requests[identity.requestId] = timing
            return elapsed
        }
        emit(
            event: "presented",
            identity: identity,
            monoMs: now,
            attrs: [
                "sinceFinalMs": .double(sinceFinal),
                "anchorWaitMs": .double(sinceFinal),
            ]
        )
    }

    func cancelWritten(
        identity: SuggestionRequestMessage.Identity,
        reason: CancelRequestReason,
        typedAppend: Bool
    ) {
        let state = lock.withLock {
            requests[identity.requestId]?.state ?? .requesting
        }
        emit(
            event: "cancel_written",
            identity: identity,
            attrs: [
                "reason": .string(reason.rawValue),
                "sessionState": .string(state.rawValue),
                "typedAppend": .boolean(typedAppend),
            ]
        )
    }

    func interaction(
        identity: SuggestionRequestMessage.Identity,
        outcome: InteractionOutcome
    ) {
        let now = monotonicMilliseconds()
        let sinceShown = lock.withLock { () -> Double in
            let elapsed = requests[identity.requestId]?.shownMs.map {
                Self.duration(now - $0)
            } ?? 0
            switch outcome {
            case .shown:
                break
            case .acceptedFull, .acceptedPartial, .dismissed, .typedThrough, .stale, .failed,
                 .editedAfterAcceptance, .removedAfterAcceptance, .observationUnavailable:
                requests.removeValue(forKey: identity.requestId)
            }
            return elapsed
        }
        emit(
            event: "interaction",
            identity: identity,
            monoMs: now,
            attrs: [
                "outcome": .string(outcome.rawValue),
                "sinceShownMs": .double(sinceShown),
            ]
        )
    }

    private func emit(
        event: String,
        identity: SuggestionRequestMessage.Identity? = nil,
        focusSequence: UInt64? = nil,
        monoMs: Double? = nil,
        attrs: [String: Value]
    ) {
        guard enabled else { return }
        let envelope = Event(
            requestId: identity?.requestId,
            focusSequence: identity?.focusSequence ?? focusSequence,
            event: event,
            monoMs: monoMs ?? monotonicMilliseconds(),
            wallMs: wallMilliseconds(),
            attrs: attrs
        )
        let sink = self.sink
        dispatch {
            let encoder = JSONEncoder()
            guard var data = try? encoder.encode(envelope) else { return }
            data.append(0x0A)
            guard let json = String(data: data, encoding: .utf8) else { return }
            sink("timeline:\(json)")
        }
    }

    private static func duration(_ value: Double) -> Double {
        max(0, (value * 100).rounded() / 100)
    }

    private static func textBucket(_ count: Int) -> String {
        switch max(0, count) {
        case 0: "zero"
        case ..<100: "lt_100"
        case ..<1_000: "lt_1k"
        case ..<8_000: "lt_8k"
        default: "gte_8k"
        }
    }

    private static func geometry(_ quality: GeometryQuality) -> String {
        switch quality {
        case .exact: "exact"
        case .derived: "derived"
        case .unavailable: "unavailable"
        }
    }

    private static func skipReason(_ reason: ActiveFieldSkipReason) -> String {
        switch reason {
        case .accessibilityUnavailable: "accessibility_unavailable"
        case .unsupportedApplication: "unsupported_application"
        case .unsupportedRole: "unsupported_role"
        case .secureField: "secure_field"
        case .valueMissing: "value_missing"
        case .rangeMissing: "range_missing"
        case .rangeOutOfBounds: "range_out_of_bounds"
        case .markerReadFailed: "marker_read_failed"
        }
    }

    private static func disposition(_ disposition: SuggestionResponseDisposition) -> String {
        switch disposition {
        case .accepted: "accepted"
        case .rejectedCurrent: "rejected_current"
        case .ignoredStale: "ignored_stale"
        }
    }
}
