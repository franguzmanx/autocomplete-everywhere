import Foundation
import CoreText

enum WebTextReadStage: String {
    case element, provider, selection
    case selectionNoValue = "selection_no_value", selectionUnsupported = "selection_unsupported"
    case selectionUnavailable = "selection_unavailable", selectionInvalidValue = "selection_invalid_value"
    case selectionMapping = "selection_mapping", selectionOutsideField = "selection_outside_field"
    case selectionAncestry = "selection_ancestry", selectionAncestryLimit = "selection_ancestry_limit"
    case elementRange = "element_range", fieldValue = "field_value"
    case fieldSelection = "field_selection", focusedText = "focused_text"
    case before, selected, after, success
}

enum FixturePresentationAvailability {
    case available
    case sessionUnavailable
    case anchorUnavailable(reacquiringAfterPreview: Bool)
}

enum FixtureFontResolution: String {
    case exact
    case systemFallback = "system_fallback"
    case estimated
    case unavailable
}

final class FixtureDiagnostics: @unchecked Sendable {
    typealias Sink = (String) -> Void

    private enum CaptureCategory: String, Equatable {
        case capturedExact = "capture_captured_exact"
        case capturedDerived = "capture_captured_derived"
        case capturedGeometryUnavailable = "capture_captured_geometry_unavailable"
        case skippedAccessibilityUnavailable = "capture_skipped_accessibility_unavailable"
        case skippedUnsupportedApplication = "capture_skipped_unsupported_application"
        case skippedUnsupportedRole = "capture_skipped_unsupported_role"
        case skippedSecureField = "capture_skipped_secure_field"
        case skippedValueMissing = "capture_skipped_value_missing"
        case skippedRangeMissing = "capture_skipped_range_missing"
        case skippedRangeOutOfBounds = "capture_skipped_range_out_of_bounds"
        case skippedMarkerReadFailed = "capture_skipped_marker_read_failed"
    }

    private let enabled: Bool
    private let keyboardEnabled: Bool
    private let sink: Sink
    private let lock = NSLock()
    private var lastFontMeasurementCode: String?
    private var lastTypographyCode: String?
    private var lastCaptureSnapshot: ActiveFieldSnapshot?
    private var lastWebCaretEvidence: WebCaretEvidence?
    private var lastWebReadStage: WebTextReadStage?
    private var lastSourceReadOutcome: SourceReadOutcome?
    private var lastOverflow: GhostTextOverflow?
    private var lastCaptureCategory: CaptureCategory?
    private var lastCaptureStructure: PublicationFingerprint?
    private var lastCaptureGeometryStructure: ActiveFieldGeometryStructure?

    private struct PublicationFingerprint: Equatable {
        let structure: ActiveFieldPublicationStructure
        let geometryQuality: GeometryQuality
    }

    func fontMeasurement(_ code: String) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard code != lastFontMeasurementCode else { return }
        lastFontMeasurementCode = code
        sink("fixture:\(code)\n")
    }

    var isEnabled: Bool { enabled }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sink: @escaping Sink = { line in
            guard let data = line.data(using: .utf8) else { return }
            FileHandle.standardError.write(data)
        }
    ) {
        enabled = environment["AUTOCOMPLETION_VISUAL_FIXTURE"] == "1"
            || environment["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS"] == "1"
        keyboardEnabled = environment["AUTOCOMPLETION_VISUAL_FIXTURE"] == "1"
        self.sink = sink
    }

    func permission(_ state: NativePermissionState) {
        write([
            "permission_accessibility_\(state.accessibility.rawValue)",
            "permission_input_monitoring_\(state.inputMonitoring.rawValue)",
        ])
    }

    func keyboard(_ action: KeyboardAction) {
        guard keyboardEnabled else { return }
        let code = switch action {
        case .hostText: "keyboard_host_text"
        case .hostAmbiguousText: "keyboard_host_ambiguous_text"
        case .hostStateChanged: "keyboard_host_state_changed"
        case .hostGeometryDisturbed: "keyboard_host_geometry_disturbed"
        case .dismissSuggestion: "keyboard_dismiss_suggestion"
        case .acceptSuggestion: "keyboard_accept_suggestion"
        case .acceptNextWord: "keyboard_accept_next_word"
        case .nextAlternative: "keyboard_next_alternative"
        case .previousAlternative: "keyboard_previous_alternative"
        }
        write([code])
    }

    func capture(_ result: ActiveFieldCaptureResult) {
        let category = Self.captureCategory(for: result)
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        if case let .captured(snapshot) = result {
            let empty = snapshot.textBefore.isEmpty && snapshot.selectedText.isEmpty && snapshot.textAfter.isEmpty
            let weight: String
            if let style = snapshot.textStyle {
                let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
                weight = CTFontGetSymbolicTraits(font).contains(.traitBold) ? "bold" : "regular"
            } else { weight = "unavailable" }
            let typographyCode = "typography_\(empty ? "empty" : "authored")_\(weight)"
            if typographyCode != lastTypographyCode {
                sink("fixture:\(typographyCode)\n")
                lastTypographyCode = typographyCode
            }

            if let previous = lastCaptureSnapshot {
                var changes: [String] = []
                if previous.applicationBundleIdentifier != snapshot.applicationBundleIdentifier
                    || previous.elementIdentifier != snapshot.elementIdentifier
                    || previous.focusGeneration != snapshot.focusGeneration { changes.append("field") }
                if previous.textBefore != snapshot.textBefore || previous.selectedText != snapshot.selectedText
                    || previous.textAfter != snapshot.textAfter { changes.append("draft") }
                if previous.selectionRange != snapshot.selectionRange { changes.append("selection") }
                if previous.fieldContext.relatedFields != snapshot.fieldContext.relatedFields { changes.append("related_fields") }
                if previous.fieldContext.sources != snapshot.fieldContext.sources {
                    changes.append("sources")
                    let oldSources = previous.fieldContext.sources.sorted { $0.id < $1.id }
                    let newSources = snapshot.fieldContext.sources.sorted { $0.id < $1.id }
                    if oldSources.map(\.id) != newSources.map(\.id) { changes.append("source_membership") }
                    else if oldSources == newSources { changes.append("source_order") }
                    else { changes.append("source_content") }
                }
                if previous.fieldContext.shape != snapshot.fieldContext.shape
                    || previous.fieldContext.label != snapshot.fieldContext.label
                    || previous.fieldContext.placeholder != snapshot.fieldContext.placeholder { changes.append("metadata") }
                for change in changes { sink("fixture:change_\(change)\n") }
            }
            lastCaptureSnapshot = snapshot
        } else {
            lastCaptureSnapshot = nil
            lastWebCaretEvidence = nil
        }
        if category != lastCaptureCategory {
            lastCaptureCategory = category
            sink("fixture:\(category.rawValue)\n")
        }
        guard case let .captured(snapshot) = result,
              let structure = snapshot.publicationStructure
        else {
            lastCaptureStructure = nil
            lastCaptureGeometryStructure = nil
            return
        }
        let fingerprint = PublicationFingerprint(
            structure: structure,
            geometryQuality: snapshot.geometryQuality
        )
        if fingerprint != lastCaptureStructure {
            lastCaptureStructure = fingerprint
            for code in Self.publicationCodes(phase: "capture", snapshot: snapshot) {
                sink("fixture:\(code)\n")
            }
        }
        if snapshot.geometryStructure != lastCaptureGeometryStructure {
            lastCaptureGeometryStructure = snapshot.geometryStructure
            for code in Self.geometryCodes(phase: "capture", snapshot: snapshot) {
                sink("fixture:\(code)\n")
            }
        }
    }

    func webCaret(_ evidence: WebCaretEvidence) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, evidence != lastWebCaretEvidence else { return }
        lastWebCaretEvidence = evidence
        for (name, matches) in [
            ("marker_selection", evidence.markerSelectionMatches),
            ("node_value", evidence.nodeValueMatches),
            ("line_value", evidence.lineValueMatches),
            ("node_containment", evidence.nodeContained),
            ("node_is_text", evidence.nodeIsText),
            ("node_candidate_available", evidence.nodeCandidateAvailable),
            ("node_candidate_selected", evidence.nodeCandidateSelected),
        ] {
            sink("fixture:web_caret_\(name)_\(matches ? "yes" : "no")\n")
        }
    }

    func sourceRead(_ outcome: SourceReadOutcome) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, outcome != lastSourceReadOutcome else { return }
        lastSourceReadOutcome = outcome
        sink("fixture:source_read_\(outcome.rawValue)\n")
    }

    func webRead(_ stage: WebTextReadStage) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, stage != lastWebReadStage else { return }
        lastWebReadStage = stage
        sink("fixture:web_read_\(stage.rawValue)\n")
    }

    func request(_ snapshot: ActiveFieldSnapshot) {
        write(
            Self.publicationCodes(phase: "request", snapshot: snapshot)
                + Self.geometryCodes(phase: "request", snapshot: snapshot)
        )
    }

    func overflow(_ evidence: GhostTextOverflow) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, evidence != lastOverflow else { return }
        lastOverflow = evidence
        for (edge, amount) in [("left", evidence.left), ("right", evidence.right), ("top", evidence.top), ("bottom", evidence.bottom)] {
            sink("fixture:overflow_\(edge)_\(amount.rawValue)\n")
        }
        sink("fixture:overflow_slices_\(evidence.completionLines)\n")
        sink("fixture:overflow_capacity_\(evidence.availableLines)\n")
    }

    func presenter(
        didPresent: Bool,
        rejectionReason: GhostTextPresenterRejectionReason? = nil,
        paragraphLayoutFailureReason: ParagraphMirrorLayoutFailureReason? = nil
    ) {
        if didPresent {
            write(["presenter_shown"])
            return
        }
        var codes = ["presenter_rejected"]
        if let rejectionReason {
            codes.append("presenter_rejected_reason_\(rejectionReason.rawValue)")
        }
        if let paragraphLayoutFailureReason {
            codes.append(
                "presenter_paragraph_layout_failure_\(paragraphLayoutFailureReason.rawValue)"
            )
        }
        write(codes)
    }

    func visualCalibration(
        fontResolution: FixtureFontResolution,
        horizontalOffset: CGFloat?
    ) {
        visualCalibration(
            fontResolution: fontResolution,
            typographyIsEstimated: false,
            horizontalOffset: horizontalOffset
        )
    }

    func visualCalibration(
        fontResolution: FixtureFontResolution,
        typographyIsEstimated: Bool,
        horizontalOffset: CGFloat?
    ) {
        let fontResolution = typographyIsEstimated
            ? FixtureFontResolution.estimated
            : fontResolution
        let horizontalCategory: String
        guard let horizontalOffset, horizontalOffset.isFinite else {
            write(["visual_font_\(fontResolution.rawValue)"])
            return
        }
        switch abs(horizontalOffset) {
        case ...0.01:
            horizontalCategory = "zero"
        case ...1:
            horizontalCategory = "subpixel"
        case ...2:
            horizontalCategory = "small"
        default:
            horizontalCategory = "large"
        }
        write([
            "visual_font_\(fontResolution.rawValue)",
            "visual_horizontal_\(horizontalCategory)",
        ])
    }

    func suggestionFinalCommandReceived() {
        write(["command_received_final"])
    }

    func suggestionFinalResult(_ result: SuggestionFinalResult) {
        switch result {
        case .text:
            write(["final_result_text"])
        case .silence:
            write(["final_result_silence"])
        }
    }

    func sessionOutcome(_ disposition: SuggestionResponseDisposition) {
        let code: String
        switch disposition {
        case .accepted:
            code = "session_accepted"
        case .rejectedCurrent:
            code = "session_rejected_current"
        case .ignoredStale:
            code = "session_ignored_stale"
        }
        write([code])
    }

    func presentation(_ availability: FixturePresentationAvailability) {
        let code: String
        switch availability {
        case .available:
            code = "presentation_available"
        case .sessionUnavailable:
            code = "presentation_unavailable_session"
        case let .anchorUnavailable(reacquiringAfterPreview):
            code = reacquiringAfterPreview
                ? "presentation_unavailable_reacquiring"
                : "presentation_unavailable_anchor"
        }
        write([code])
    }

    func transform(_ outcome: TransformDiagnostic) {
        write(["transform_\(outcome.rawValue)"])
    }

    func presentInvoked() {
        write(["present_invoked"])
    }

    private func write(_ codes: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        for code in codes {
            sink("fixture:\(code)\n")
        }
    }

    private static func captureCategory(
        for result: ActiveFieldCaptureResult
    ) -> CaptureCategory {
        switch result {
        case let .captured(snapshot):
            switch snapshot.geometryQuality {
            case .exact:
                return .capturedExact
            case .derived:
                return .capturedDerived
            case .unavailable:
                return .capturedGeometryUnavailable
            }
        case let .skipped(reason):
            switch reason {
            case .accessibilityUnavailable:
                return .skippedAccessibilityUnavailable
            case .unsupportedApplication:
                return .skippedUnsupportedApplication
            case .unsupportedRole:
                return .skippedUnsupportedRole
            case .secureField:
                return .skippedSecureField
            case .valueMissing:
                return .skippedValueMissing
            case .rangeMissing:
                return .skippedRangeMissing
            case .rangeOutOfBounds:
                return .skippedRangeOutOfBounds
            case .markerReadFailed:
                return .skippedMarkerReadFailed
            }
        }
    }

    private static func publicationCodes(
        phase: String,
        snapshot: ActiveFieldSnapshot
    ) -> [String] {
        guard let structure = snapshot.publicationStructure else { return [] }
        let selectionState = structure.selectionCollapsed
            ? "collapsed"
            : "noncollapsed"
        let textAfter = structure.textAfterIsEmpty ? "empty" : "nonempty"
        let geometry = switch snapshot.geometryQuality {
        case .exact: "exact"
        case .derived: "derived"
        case .unavailable: "unavailable"
        }
        var codes = [
            "structure_\(phase)_selection_\(structure.selectionPosition.rawValue)",
            "structure_\(phase)_selection_state_\(selectionState)",
            "structure_\(phase)_text_before_\(structure.textBeforeTerminal.rawValue)",
            "structure_\(phase)_text_after_\(textAfter)",
            "structure_\(phase)_value_\(structure.valueTerminal.rawValue)",
            "structure_\(phase)_geometry_\(geometry)",
            "field_\(phase)_shape_\(snapshot.fieldContext.shape.rawValue)",
        ]
        if snapshot.fieldContext.relatedFields.isEmpty {
            codes.append("field_\(phase)_related_none")
        } else {
            codes.append("field_\(phase)_related_available")
        }
        return codes
    }

    private static func geometryCodes(
        phase: String,
        snapshot: ActiveFieldSnapshot
    ) -> [String] {
        guard let structure = snapshot.geometryStructure else { return [] }
        let inputFrame = structure.inputFrameAvailable ? "available" : "unavailable"
        let direction = switch structure.direction {
        case .leftToRight: "left_to_right"
        case .rightToLeft: "right_to_left"
        case .neutral: "neutral"
        case .ambiguous: "ambiguous"
        }
        let display = structure.displayMatched ? "match" : "no_match"
        let resolver = switch structure.resolverOutcome {
        case .notRun: "not_run"
        case .resolved: "resolved"
        case let .failed(reason): "failed_\(failureCode(reason))"
        }
        let paragraphStart = structure.paragraphStartAvailable
            ? "available"
            : "unavailable"
        let paragraphMetrics = snapshot.paragraphMetrics == nil
            ? "unavailable"
            : "available"
        var codes = [
            "geometry_\(phase)_input_frame_\(inputFrame)",
            "geometry_\(phase)_direction_\(direction)",
            "geometry_\(phase)_zero_length_\(structure.zeroLengthBounds.rawValue)",
            "geometry_\(phase)_preceding_glyph_\(structure.precedingGlyphBounds.rawValue)",
            "geometry_\(phase)_following_glyph_\(structure.followingGlyphBounds.rawValue)",
            "geometry_\(phase)_line_edge_\(structure.lineEdgeBounds.rawValue)",
            "geometry_\(phase)_display_\(display)",
            "geometry_\(phase)_resolver_\(resolver)",
            "geometry_\(phase)_paragraph_start_\(paragraphStart)",
            "geometry_\(phase)_paragraph_metrics_\(paragraphMetrics)",
        ]
        if let reason = snapshot.paragraphMetricsFailureReason {
            codes.append(
                "geometry_\(phase)_paragraph_metrics_reason_\(reason.rawValue)"
            )
        }
        return codes
    }

    private static func failureCode(
        _ reason: CaretGeometryFailureReason
    ) -> String {
        switch reason {
        case .noCandidates: "no_candidates"
        case .invalidCandidateBounds: "invalid_candidate_bounds"
        case .outsideInputFrame: "outside_input_frame"
        case .lineHeightMismatch: "line_height_mismatch"
        case .displayUnavailable: "display_unavailable"
        case .conflictingCandidates: "conflicting_candidates"
        }
    }
}
