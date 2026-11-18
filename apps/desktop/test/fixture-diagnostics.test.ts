import { describe, expect, test } from "vitest";

import {
  createFixtureDiagnosticSink,
  createFixtureDiagnostics,
} from "../src/main/fixture-diagnostics";

describe("fixture diagnostics", () => {
  test("emits only content-free typed events in explicit fixture mode", () => {
    const lines: string[] = [];
    const diagnostics = createFixtureDiagnostics(
      { AUTOCOMPLETION_VISUAL_FIXTURE: "1" },
      (line) => lines.push(line),
    );

    diagnostics.configureEffective(false, ["accessibility_required"]);
    diagnostics.permissionState("granted", "required");
    diagnostics.suggestionRequestObserved();
    diagnostics.responseSent("final");
    diagnostics.sourceDecision({ outcome: "silence", reason: "newline" });
    diagnostics.coordinatorFinalResult("silence");
    diagnostics.helperEvent("fixture_capture_skipped_value_missing");
    diagnostics.helperEvent("fixture_capture_skipped_range_missing");
    diagnostics.helperEvent("fixture_capture_skipped_range_out_of_bounds");
    diagnostics.helperEvent("fixture_capture_skipped_marker_read_failed");
    diagnostics.helperEvent("fixture_structure_capture_selection_middle");
    diagnostics.helperEvent("fixture_structure_capture_selection_state_collapsed");
    diagnostics.helperEvent("fixture_structure_capture_text_before_newline");
    diagnostics.helperEvent("fixture_structure_capture_text_after_nonempty");
    diagnostics.helperEvent("fixture_structure_capture_value_letter");
    diagnostics.helperEvent("fixture_structure_capture_geometry_exact");
    diagnostics.helperEvent("fixture_structure_request_selection_middle");
    diagnostics.helperEvent("fixture_structure_request_text_before_newline");
    diagnostics.helperEvent("fixture_structure_request_text_before_private");
    diagnostics.helperEvent("fixture_geometry_capture_input_frame_available");
    diagnostics.helperEvent("fixture_geometry_capture_direction_left_to_right");
    diagnostics.helperEvent("fixture_geometry_capture_zero_length_missing");
    diagnostics.helperEvent("fixture_geometry_capture_preceding_glyph_available");
    diagnostics.helperEvent("fixture_geometry_capture_following_glyph_missing");
    diagnostics.helperEvent("fixture_geometry_capture_line_edge_available");
    diagnostics.helperEvent("fixture_geometry_capture_display_match");
    diagnostics.helperEvent("fixture_geometry_capture_resolver_resolved");
    diagnostics.helperEvent("fixture_geometry_capture_paragraph_start_available");
    diagnostics.helperEvent("fixture_geometry_capture_paragraph_metrics_unavailable");
    diagnostics.helperEvent(
      "fixture_geometry_capture_paragraph_metrics_reason_paragraph_attributes_unavailable",
    );
    diagnostics.helperEvent("fixture_geometry_request_resolver_failed_no_candidates");
    diagnostics.helperEvent("fixture_geometry_request_resolver_private");
    diagnostics.helperEvent("fixture_command_received_final");
    diagnostics.helperEvent("fixture_session_accepted");
    diagnostics.helperEvent("fixture_presentation_available");
    diagnostics.helperEvent("fixture_present_invoked");
    diagnostics.helperEvent("fixture_presenter_rejected");
    diagnostics.helperEvent("fixture_visual_font_system_fallback");
    diagnostics.helperEvent("fixture_visual_font_estimated");
    diagnostics.helperEvent("fixture_visual_horizontal_subpixel");
    diagnostics.helperEvent(
      "fixture_presenter_rejected_reason_paragraph_outside_visible_field",
    );

    expect(lines).toEqual([
      "autocompletion_fixture event=configure_effective enabled=false reasons=accessibility_required\n",
      "autocompletion_fixture event=permission_state accessibility=granted input_monitoring=required\n",
      "autocompletion_fixture event=suggestion_request count=1\n",
      "autocompletion_fixture event=response_sent category=final\n",
      "autocompletion_fixture event=source_decision outcome=silence reason=newline\n",
      "autocompletion_fixture event=coordinator_final category=silence\n",
      "autocompletion_fixture event=capture_outcome category=skipped_value_missing\n",
      "autocompletion_fixture event=capture_outcome category=skipped_range_missing\n",
      "autocompletion_fixture event=capture_outcome category=skipped_range_out_of_bounds\n",
      "autocompletion_fixture event=capture_outcome category=skipped_marker_read_failed\n",
      "autocompletion_fixture event=capture_structure field=selection category=middle\n",
      "autocompletion_fixture event=capture_structure field=selection_state category=collapsed\n",
      "autocompletion_fixture event=capture_structure field=text_before_terminal category=newline\n",
      "autocompletion_fixture event=capture_structure field=text_after category=nonempty\n",
      "autocompletion_fixture event=capture_structure field=value_terminal category=letter\n",
      "autocompletion_fixture event=capture_structure field=geometry category=exact\n",
      "autocompletion_fixture event=request_structure field=selection category=middle\n",
      "autocompletion_fixture event=request_structure field=text_before_terminal category=newline\n",
      "autocompletion_fixture event=capture_geometry field=input_frame category=available\n",
      "autocompletion_fixture event=capture_geometry field=direction category=left_to_right\n",
      "autocompletion_fixture event=capture_geometry field=zero_length_bounds category=missing\n",
      "autocompletion_fixture event=capture_geometry field=preceding_glyph_bounds category=available\n",
      "autocompletion_fixture event=capture_geometry field=following_glyph_bounds category=missing\n",
      "autocompletion_fixture event=capture_geometry field=line_edge_bounds category=available\n",
      "autocompletion_fixture event=capture_geometry field=display category=match\n",
      "autocompletion_fixture event=capture_geometry field=resolver category=resolved\n",
      "autocompletion_fixture event=capture_geometry field=paragraph_start category=available\n",
      "autocompletion_fixture event=capture_geometry field=paragraph_metrics category=unavailable\n",
      "autocompletion_fixture event=capture_geometry field=paragraph_metrics_reason category=paragraph_attributes_unavailable\n",
      "autocompletion_fixture event=request_geometry field=resolver category=failed_no_candidates\n",
      "autocompletion_fixture event=helper_command category=final\n",
      "autocompletion_fixture event=session_outcome category=accepted\n",
      "autocompletion_fixture event=presentation_availability category=available\n",
      "autocompletion_fixture event=present_invoked\n",
      "autocompletion_fixture event=presenter_outcome category=rejected\n",
      "autocompletion_fixture event=visual_font category=system_fallback\n",
      "autocompletion_fixture event=visual_font category=estimated\n",
      "autocompletion_fixture event=visual_horizontal category=subpixel\n",
      "autocompletion_fixture event=presenter_rejection reason=paragraph_outside_visible_field\n",
    ]);
    expect(lines.join(" ")).not.toContain("private field");
  });

  test("emits nothing outside explicit fixture mode", () => {
    const lines: string[] = [];
    const diagnostics = createFixtureDiagnostics({}, (line) => lines.push(line));

    diagnostics.configureEffective(true, []);
    diagnostics.permissionState("granted", "granted");
    diagnostics.suggestionRequestObserved();
    diagnostics.responseSent("final");
    diagnostics.sourceDecision({ outcome: "text", reason: "default" });
    diagnostics.coordinatorFinalResult("text");
    diagnostics.helperEvent("fixture_capture_captured_exact");

    expect(lines).toEqual([]);
  });

  test("the retired engine lab switch enables nothing", () => {
    const lines: string[] = [];
    const diagnostics = createFixtureDiagnostics(
      { AUTOCOMPLETION_ENGINE_LAB: "1" },
      (line) => lines.push(line),
    );

    diagnostics.suggestionRequestObserved();
    diagnostics.coordinatorFinalResult("text");

    expect(lines).toEqual([]);
  });

  test("a closed diagnostic sink cannot crash fixture mode", () => {
    const closedPipe = Object.assign(new Error("write EPIPE"), {
      code: "EPIPE",
    });
    const diagnostics = createFixtureDiagnostics(
      { AUTOCOMPLETION_VISUAL_FIXTURE: "1" },
      () => {
        throw closedPipe;
      },
    );

    expect(() => diagnostics.suggestionRequestObserved()).not.toThrow();
    expect(() => diagnostics.responseSent("final")).not.toThrow();
  });

  test("the fixture stderr sink absorbs asynchronous EPIPE errors", () => {
    const listeners: Array<(error: Error) => void> = [];
    const closedPipe = Object.assign(new Error("write EPIPE"), {
      code: "EPIPE",
    });
    const output = {
      writable: true,
      destroyed: false,
      on: (_event: "error", listener: (error: Error) => void) => {
        listeners.push(listener);
      },
      write: (_line: string, callback: (error?: Error | null) => void) => {
        callback(closedPipe);
        for (const listener of listeners) listener(closedPipe);
        return false;
      },
    };
    const sink = createFixtureDiagnosticSink(output);

    expect(() => sink("content-free fixture event\n")).not.toThrow();
    expect(() => sink("another event\n")).not.toThrow();
  });
});
