import Foundation
import XCTest
@testable import AutocompleteHelper

final class FixtureDiagnosticsTests: XCTestCase {
    func testOverflowDiagnosticContainsOnlyBoundedGeometryCategories() {
        var lines: [String] = []
        let evidence = GhostTextOverflow(
            frame: CGRect(x: 100, y: 10, width: 201.5, height: 100),
            visibleField: CGRect(x: 100, y: 50, width: 200, height: 60),
            caret: CGRect(x: 100, y: 90, width: 0, height: 20),
            lineHeight: 20, completionLines: 50
        )
        let diagnostics = FixtureDiagnostics(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"], sink: { lines.append($0) })
        diagnostics.overflow(evidence)
        diagnostics.overflow(evidence)
        XCTAssertEqual(lines, ["fixture:overflow_left_none\n", "fixture:overflow_right_small\n", "fixture:overflow_top_none\n", "fixture:overflow_bottom_multiple_lines\n", "fixture:overflow_slices_9\n", "fixture:overflow_capacity_3\n"])
        FixtureDiagnostics(environment: [:], sink: { lines.append($0) }).overflow(evidence)
        XCTAssertEqual(lines.count, 6)
    }

    func testSourceReadOutcomeIsOptInAndDeduplicated() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"], sink: { lines.append($0) })
        diagnostics.sourceRead(.deadline)
        diagnostics.sourceRead(.deadline)
        diagnostics.sourceRead(.noVisibleSources)
        diagnostics.sourceRead(.available)
        XCTAssertEqual(lines, ["fixture:source_read_deadline\n", "fixture:source_read_no_visible_sources\n", "fixture:source_read_available\n"])
        FixtureDiagnostics(environment: [:], sink: { lines.append($0) }).sourceRead(.deadline)
        XCTAssertEqual(lines.count, 3)
    }

    func testMarkerOwnershipFailuresAreDistinctAndContentFree() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"], sink: { lines.append($0) })
        for stage: WebTextReadStage in [.selectionMapping, .selectionOutsideField, .selectionAncestry, .selectionAncestryLimit] {
            diagnostics.webRead(stage)
            diagnostics.webRead(stage)
        }
        XCTAssertEqual(lines, [
            "fixture:web_read_selection_mapping\n", "fixture:web_read_selection_outside_field\n",
            "fixture:web_read_selection_ancestry\n", "fixture:web_read_selection_ancestry_limit\n",
        ])
    }

    func testWebReadStageIsDeduplicatedAndCanReportRecovery() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"], sink: { lines.append($0) })
        diagnostics.webRead(.fieldSelection)
        diagnostics.webRead(.fieldSelection)
        diagnostics.webRead(.success)
        diagnostics.webRead(.fieldSelection)
        XCTAssertEqual(lines, ["fixture:web_read_field_selection\n", "fixture:web_read_success\n", "fixture:web_read_field_selection\n"])
        FixtureDiagnostics(environment: [:], sink: { lines.append($0) }).webRead(.success)
        XCTAssertEqual(lines.count, 3)
    }

    func testSeparatesSurroundingContextChangesFromDraftEditsWithoutLoggingContent() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            sink: { lines.append($0) }
        )
        func snapshot(draft: String, related: String) -> ActiveFieldSnapshot {
            ActiveFieldSnapshot(
                applicationBundleIdentifier: "private.application", elementIdentifier: "private-field",
                focusGeneration: 1, textBefore: draft, selectedText: "", textAfter: "",
                selectionRange: NSRange(location: draft.utf16.count, length: 0),
                caretBounds: nil, inputFrame: nil, geometryQuality: .unavailable,
                geometrySource: nil, captureSequence: 1,
                fieldContext: ActiveFieldContext(shape: .multiline, relatedFields: [
                    RelatedFieldContext(shape: .multiline, label: nil, placeholder: nil, text: related)
                ])
            )
        }
        diagnostics.capture(.captured(snapshot(draft: "private draft", related: "private context A")))
        diagnostics.capture(.captured(snapshot(draft: "private draft", related: "private context B")))
        diagnostics.capture(.captured(snapshot(draft: "private draft", related: "private context B")))
        XCTAssertEqual(lines.filter { $0.contains("change_") }, ["fixture:change_related_fields\n"])
        diagnostics.capture(.captured(snapshot(draft: "private edit!", related: "private context B")))
        XCTAssertEqual(lines.filter { $0.contains("change_") }, [
            "fixture:change_related_fields\n", "fixture:change_draft\n"
        ])
        XCTAssertFalse(lines.joined().contains("private"))
        diagnostics.capture(.skipped(.secureField))
        lines.removeAll()
        diagnostics.capture(.captured(snapshot(draft: "different", related: "different")))
        XCTAssertFalse(lines.contains { $0.contains("change_") })
    }

    func testWebCaretEvidenceIsCategoricalAndDeduplicated() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"], sink: { lines.append($0) })
        let evidence = WebCaretEvidence(markerSelectionMatches: false, nodeValueMatches: true,
                                       lineValueMatches: false, nodeContained: true, nodeIsText: false,
                                       nodeCandidateAvailable: false, nodeCandidateSelected: false)
        diagnostics.webCaret(evidence)
        diagnostics.webCaret(evidence)
        XCTAssertEqual(lines, [
            "fixture:web_caret_marker_selection_no\n", "fixture:web_caret_node_value_yes\n",
            "fixture:web_caret_line_value_no\n", "fixture:web_caret_node_containment_yes\n",
            "fixture:web_caret_node_is_text_no\n",
            "fixture:web_caret_node_candidate_available_no\n", "fixture:web_caret_node_candidate_selected_no\n"
        ])
        let disabled = FixtureDiagnostics(environment: [:], sink: { lines.append($0) })
        disabled.webCaret(evidence)
        XCTAssertEqual(lines.count, 7)
    }

    func testEmitsContentFreeCategoriesOnlyWhenFixtureIsExplicit() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_VISUAL_FIXTURE": "1"],
            sink: { lines.append($0) }
        )

        diagnostics.permission(
            NativePermissionState(accessibility: .granted, inputMonitoring: .required)
        )
        diagnostics.capture(.skipped(.rangeMissing))
        diagnostics.suggestionFinalCommandReceived()
        diagnostics.suggestionFinalResult(.silence("not_useful"))
        diagnostics.sessionOutcome(.accepted)
        diagnostics.presentation(.available)
        diagnostics.presentInvoked()
        diagnostics.presenter(
            didPresent: false,
            rejectionReason: .paragraphOutsideVisibleField
        )

        XCTAssertEqual(
            lines,
            [
                "fixture:permission_accessibility_granted\n",
                "fixture:permission_input_monitoring_required\n",
                "fixture:capture_skipped_range_missing\n",
                "fixture:command_received_final\n",
                "fixture:final_result_silence\n",
                "fixture:session_accepted\n",
                "fixture:presentation_available\n",
                "fixture:present_invoked\n",
                "fixture:presenter_rejected\n",
                "fixture:presenter_rejected_reason_paragraph_outside_visible_field\n",
            ]
        )
    }

    func testDeduplicatesPollingAndStaysSilentOutsideFixtureMode() {
        var enabledLines: [String] = []
        let enabled = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_VISUAL_FIXTURE": "1"],
            sink: { enabledLines.append($0) }
        )
        enabled.capture(.skipped(.unsupportedApplication))
        enabled.capture(.skipped(.unsupportedApplication))

        var disabledLines: [String] = []
        let disabled = FixtureDiagnostics(
            environment: [:],
            sink: { disabledLines.append($0) }
        )
        disabled.capture(.skipped(.secureField))
        disabled.presenter(didPresent: true)

        XCTAssertTrue(enabled.isEnabled)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(
            enabledLines,
            ["fixture:capture_skipped_unsupported_application\n"]
        )
        XCTAssertEqual(disabledLines, [])
    }

    func testRuntimeDiagnosticsDoNotWriteFromTheKeyboardHotPath() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            sink: { lines.append($0) }
        )

        diagnostics.keyboard(.hostText("private"))
        diagnostics.capture(.skipped(.markerReadFailed))

        XCTAssertEqual(lines, ["fixture:capture_skipped_marker_read_failed\n"])
    }

    func testRetiredEngineLabSwitchDoesNotEnableDiagnostics() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_ENGINE_LAB": "1"],
            sink: { lines.append($0) }
        )

        diagnostics.capture(.skipped(.unsupportedRole))
        diagnostics.presenter(didPresent: true)
        diagnostics.visualCalibration(
            fontResolution: .systemFallback,
            horizontalOffset: 0.75
        )

        XCTAssertEqual(lines, [])
    }

    func testClassifiesEveryClosedResponseAndAnchorDecision() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_VISUAL_FIXTURE": "1"],
            sink: { lines.append($0) }
        )

        diagnostics.suggestionFinalCommandReceived()
        diagnostics.suggestionFinalResult(.text("private suggestion"))
        diagnostics.sessionOutcome(.rejectedCurrent)
        diagnostics.sessionOutcome(.ignoredStale)
        diagnostics.presentation(.sessionUnavailable)
        diagnostics.presentation(.anchorUnavailable(reacquiringAfterPreview: false))
        diagnostics.presentation(.anchorUnavailable(reacquiringAfterPreview: true))
        diagnostics.presenter(didPresent: true)

        XCTAssertEqual(
            lines,
            [
                "fixture:command_received_final\n",
                "fixture:final_result_text\n",
                "fixture:session_rejected_current\n",
                "fixture:session_ignored_stale\n",
                "fixture:presentation_unavailable_session\n",
                "fixture:presentation_unavailable_anchor\n",
                "fixture:presentation_unavailable_reacquiring\n",
                "fixture:presenter_shown\n",
            ]
        )
    }

    func testEmitsOnlyClosedPublicationStructureAtCaptureAndRequest() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_VISUAL_FIXTURE": "1"],
            sink: { lines.append($0) }
        )
        let snapshot = ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Notes",
            elementIdentifier: "notes-field",
            focusGeneration: 1,
            textBefore: "private fixture\n",
            selectedText: "",
            textAfter: "private continuation",
            selectionRange: NSRange(location: 16, length: 0),
            caretBounds: CGRect(x: 100, y: 100, width: 0, height: 18),
            geometryQuality: .exact,
            geometrySource: .zeroLengthRange,
            captureSequence: 1,
            paragraphMetricsFailureReason: .paragraphAttributesUnavailable,
            publicationStructure: ActiveFieldPublicationStructure(
                selectionPosition: .middle,
                selectionCollapsed: true,
                textBeforeTerminal: .newline,
                textAfterIsEmpty: false,
                valueTerminal: .letter
            ),
            geometryStructure: ActiveFieldGeometryStructure(
                inputFrameAvailable: true,
                direction: .leftToRight,
                zeroLengthBounds: .missing,
                precedingGlyphBounds: .available,
                followingGlyphBounds: .missing,
                displayMatched: true,
                resolverOutcome: .resolved,
                paragraphStartAvailable: true
            )
        )

        diagnostics.capture(.captured(snapshot))
        diagnostics.request(snapshot)

        XCTAssertEqual(
            lines,
            [
                "fixture:typography_authored_unavailable\n",
                "fixture:capture_captured_exact\n",
                "fixture:structure_capture_selection_middle\n",
                "fixture:structure_capture_selection_state_collapsed\n",
                "fixture:structure_capture_text_before_newline\n",
                "fixture:structure_capture_text_after_nonempty\n",
                "fixture:structure_capture_value_letter\n",
                "fixture:structure_capture_geometry_exact\n",
                "fixture:field_capture_shape_multiline\n",
                "fixture:field_capture_related_none\n",
                "fixture:geometry_capture_input_frame_available\n",
                "fixture:geometry_capture_direction_left_to_right\n",
                "fixture:geometry_capture_zero_length_missing\n",
                "fixture:geometry_capture_preceding_glyph_available\n",
                "fixture:geometry_capture_following_glyph_missing\n",
                "fixture:geometry_capture_line_edge_missing\n",
                "fixture:geometry_capture_display_match\n",
                "fixture:geometry_capture_resolver_resolved\n",
                "fixture:geometry_capture_paragraph_start_available\n",
                "fixture:geometry_capture_paragraph_metrics_unavailable\n",
                "fixture:geometry_capture_paragraph_metrics_reason_paragraph_attributes_unavailable\n",
                "fixture:structure_request_selection_middle\n",
                "fixture:structure_request_selection_state_collapsed\n",
                "fixture:structure_request_text_before_newline\n",
                "fixture:structure_request_text_after_nonempty\n",
                "fixture:structure_request_value_letter\n",
                "fixture:structure_request_geometry_exact\n",
                "fixture:field_request_shape_multiline\n",
                "fixture:field_request_related_none\n",
                "fixture:geometry_request_input_frame_available\n",
                "fixture:geometry_request_direction_left_to_right\n",
                "fixture:geometry_request_zero_length_missing\n",
                "fixture:geometry_request_preceding_glyph_available\n",
                "fixture:geometry_request_following_glyph_missing\n",
                "fixture:geometry_request_line_edge_missing\n",
                "fixture:geometry_request_display_match\n",
                "fixture:geometry_request_resolver_resolved\n",
                "fixture:geometry_request_paragraph_start_available\n",
                "fixture:geometry_request_paragraph_metrics_unavailable\n",
                "fixture:geometry_request_paragraph_metrics_reason_paragraph_attributes_unavailable\n",
            ]
        )
        XCTAssertFalse(lines.joined().contains("private"))
    }

    func testCaptureReportsOnlyContentFreeSemanticFieldEvidence() {
        var lines: [String] = []
        let diagnostics = FixtureDiagnostics(
            environment: ["AUTOCOMPLETION_RUNTIME_DIAGNOSTICS": "1"],
            sink: { lines.append($0) }
        )
        let snapshot = ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.google.Chrome",
            surface: .web,
            elementIdentifier: "gmail-subject",
            focusGeneration: 1,
            textBefore: "",
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: 0, length: 0),
            caretBounds: nil,
            geometryQuality: .unavailable,
            geometrySource: nil,
            captureSequence: 1,
            publicationStructure: ActiveFieldPublicationStructure(
                selectionPosition: .start,
                selectionCollapsed: true,
                textBeforeTerminal: .empty,
                textAfterIsEmpty: true,
                valueTerminal: .empty
            ),
            fieldContext: ActiveFieldContext(
                shape: .singleLine,
                label: nil,
                placeholder: "Subject",
                relatedFields: [
                    RelatedFieldContext(
                        shape: .multiline,
                        label: "Message Body",
                        placeholder: nil,
                        text: "private body"
                    )
                ]
            )
        )

        diagnostics.capture(.captured(snapshot))

        XCTAssertTrue(lines.contains("fixture:field_capture_shape_single_line\n"))
        XCTAssertTrue(lines.contains("fixture:field_capture_related_available\n"))
        XCTAssertFalse(lines.joined().contains("private"))
    }
}
