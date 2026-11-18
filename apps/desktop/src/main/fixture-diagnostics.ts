import type { HelperConfigurationDisabledReason } from "./helper-configuration";
import type { PrototypeSuggestionDecision } from "./prototype-suggestion-source";
import type { SuggestionCoordinatorFinalResult } from "./suggestion-coordinator";

type FixtureEnvironment = Readonly<Record<string, string | undefined>>;

type PermissionGrant = "granted" | "required";
type ResponseCategory = "final" | "failed";
type FixtureDiagnosticOutput = {
  readonly destroyed?: boolean;
  readonly writable?: boolean;
  on(event: "error", listener: (error: Error) => void): unknown;
  write(
    line: string,
    callback: (error?: Error | null) => void,
  ): unknown;
};

const helperEvents = {
  fixture_capture_captured_exact:
    "event=capture_outcome category=captured_exact",
  fixture_capture_captured_derived:
    "event=capture_outcome category=captured_derived",
  fixture_capture_captured_geometry_unavailable:
    "event=capture_outcome category=captured_geometry_unavailable",
  fixture_capture_skipped_accessibility_unavailable:
    "event=capture_outcome category=skipped_accessibility_unavailable",
  fixture_capture_skipped_unsupported_application:
    "event=capture_outcome category=skipped_unsupported_application",
  fixture_capture_skipped_unsupported_role:
    "event=capture_outcome category=skipped_unsupported_role",
  fixture_capture_skipped_secure_field:
    "event=capture_outcome category=skipped_secure_field",
  fixture_capture_skipped_value_missing:
    "event=capture_outcome category=skipped_value_missing",
  fixture_capture_skipped_range_missing:
    "event=capture_outcome category=skipped_range_missing",
  fixture_capture_skipped_range_out_of_bounds:
    "event=capture_outcome category=skipped_range_out_of_bounds",
  fixture_capture_skipped_marker_read_failed:
    "event=capture_outcome category=skipped_marker_read_failed",
  fixture_keyboard_host_text: "event=keyboard category=host_text",
  fixture_keyboard_host_ambiguous_text:
    "event=keyboard category=host_ambiguous_text",
  fixture_keyboard_host_state_changed:
    "event=keyboard category=host_state_changed",
  fixture_keyboard_dismiss_suggestion:
    "event=keyboard category=dismiss_suggestion",
  fixture_keyboard_accept_suggestion:
    "event=keyboard category=accept_suggestion",
  fixture_command_received_final: "event=helper_command category=final",
  fixture_final_result_text: "event=helper_final category=text",
  fixture_final_result_silence: "event=helper_final category=silence",
  fixture_session_accepted: "event=session_outcome category=accepted",
  fixture_session_rejected_current:
    "event=session_outcome category=rejected_current",
  fixture_session_ignored_stale:
    "event=session_outcome category=ignored_stale",
  fixture_presentation_available:
    "event=presentation_availability category=available",
  fixture_presentation_unavailable_session:
    "event=presentation_availability category=session_unavailable",
  fixture_presentation_unavailable_anchor:
    "event=presentation_availability category=anchor_unavailable",
  fixture_presentation_unavailable_reacquiring:
    "event=presentation_availability category=reacquiring_after_preview",
  fixture_present_invoked: "event=present_invoked",
  fixture_presenter_shown: "event=presenter_outcome category=shown",
  fixture_presenter_rejected: "event=presenter_outcome category=rejected",
  fixture_visual_font_exact: "event=visual_font category=exact",
  fixture_visual_font_system_fallback:
    "event=visual_font category=system_fallback",
  fixture_visual_font_estimated: "event=visual_font category=estimated",
  fixture_visual_font_unavailable: "event=visual_font category=unavailable",
  fixture_visual_horizontal_zero: "event=visual_horizontal category=zero",
  fixture_visual_horizontal_subpixel:
    "event=visual_horizontal category=subpixel",
  fixture_visual_horizontal_small: "event=visual_horizontal category=small",
  fixture_visual_horizontal_large: "event=visual_horizontal category=large",
} as const;

const publicationStructureSchema = [
  {
    code: "selection_state",
    output: "selection_state",
    values: ["collapsed", "noncollapsed"],
  },
  {
    code: "text_before",
    output: "text_before_terminal",
    values: ["empty", "newline", "space", "letter", "other"],
  },
  {
    code: "text_after",
    output: "text_after",
    values: ["empty", "nonempty"],
  },
  {
    code: "selection",
    output: "selection",
    values: ["start", "middle", "end"],
  },
  {
    code: "geometry",
    output: "geometry",
    values: ["exact", "derived", "unavailable"],
  },
  {
    code: "value",
    output: "value_terminal",
    values: ["empty", "newline", "space", "letter", "other"],
  },
] as const;

const geometryStructureSchema = [
  {
    code: "input_frame",
    output: "input_frame",
    values: ["available", "unavailable"],
  },
  {
    code: "preceding_glyph",
    output: "preceding_glyph_bounds",
    values: ["available", "missing", "invalid"],
  },
  {
    code: "following_glyph",
    output: "following_glyph_bounds",
    values: ["available", "missing", "invalid"],
  },
  {
    code: "line_edge",
    output: "line_edge_bounds",
    values: ["available", "missing", "invalid"],
  },
  {
    code: "zero_length",
    output: "zero_length_bounds",
    values: ["available", "missing", "invalid"],
  },
  {
    code: "paragraph_start",
    output: "paragraph_start",
    values: ["available", "unavailable"],
  },
  {
    code: "paragraph_metrics_reason",
    output: "paragraph_metrics_reason",
    values: [
      "empty",
      "too_long",
      "direction_unavailable",
      "paragraph_start_unavailable",
      "input_frame_unavailable",
      "caret_unavailable",
      "style_runs_unavailable",
      "style_coverage_invalid",
      "paragraph_attributes_unavailable",
      "list_unsupported",
      "line_height_invalid",
      "line_height_mismatch",
      "bounds_invalid",
    ],
  },
  {
    code: "paragraph_metrics",
    output: "paragraph_metrics",
    values: ["available", "unavailable"],
  },
  {
    code: "direction",
    output: "direction",
    values: ["left_to_right", "right_to_left", "neutral", "ambiguous"],
  },
  {
    code: "display",
    output: "display",
    values: ["match", "no_match"],
  },
  {
    code: "resolver",
    output: "resolver",
    values: [
      "not_run",
      "resolved",
      "failed_no_candidates",
      "failed_invalid_candidate_bounds",
      "failed_outside_input_frame",
      "failed_line_height_mismatch",
      "failed_display_unavailable",
      "failed_conflicting_candidates",
    ],
  },
] as const;

type HelperFixtureEvent = keyof typeof helperEvents;

class FixtureDiagnostics {
  private suggestionRequestCount = 0;

  constructor(
    private readonly enabled: boolean,
    private readonly sink: (line: string) => void,
  ) {}

  configureEffective(
    enabled: boolean,
    reasons: readonly HelperConfigurationDisabledReason[],
  ): void {
    if (!this.enabled) return;
    const reasonList = reasons.length > 0 ? reasons.join(",") : "none";
    this.emit(
      `event=configure_effective enabled=${enabled} reasons=${reasonList}`,
    );
  }

  permissionState(
    accessibility: PermissionGrant,
    inputMonitoring: PermissionGrant,
  ): void {
    if (!this.enabled) return;
    this.emit(
      `event=permission_state accessibility=${accessibility} input_monitoring=${inputMonitoring}`,
    );
  }

  suggestionRequestObserved(): void {
    if (!this.enabled) return;
    this.suggestionRequestCount += 1;
    this.emit(`event=suggestion_request count=${this.suggestionRequestCount}`);
  }

  responseSent(category: ResponseCategory): void {
    if (!this.enabled) return;
    this.emit(`event=response_sent category=${category}`);
  }

  sourceDecision(decision: PrototypeSuggestionDecision): void {
    if (!this.enabled) return;
    this.emit(
      `event=source_decision outcome=${decision.outcome} reason=${decision.reason}`,
    );
  }

  coordinatorFinalResult(result: SuggestionCoordinatorFinalResult): void {
    if (!this.enabled) return;
    this.emit(`event=coordinator_final category=${result}`);
  }

  helperEvent(code: string): void {
    if (!this.enabled) return;
    const publication = publicationStructureEvent(code);
    if (publication) {
      this.emit(publication);
      return;
    }
    const geometry = geometryStructureEvent(code);
    if (geometry) {
      this.emit(geometry);
      return;
    }
    const presenterRejectionPrefix = "fixture_presenter_rejected_reason_";
    if (code.startsWith(presenterRejectionPrefix)) {
      const reason = code.slice(presenterRejectionPrefix.length);
      const allowedReasons = [
        "stale_capture",
        "paragraph_prerequisites",
        "paragraph_layout",
        "paragraph_outside_visible_field",
        "single_line_layout",
        "display_rejected",
      ];
      if (allowedReasons.includes(reason)) {
        this.emit(`event=presenter_rejection reason=${reason}`);
      }
      return;
    }
    const paragraphLayoutFailurePrefix =
      "fixture_presenter_paragraph_layout_failure_";
    if (code.startsWith(paragraphLayoutFailurePrefix)) {
      const reason = code.slice(paragraphLayoutFailurePrefix.length);
      const allowedReasons = [
        "invalid_input",
        "line_height_mismatch",
        "font_unavailable",
        "anchor_outside_paragraph",
        "style_font_unavailable",
        "glyph_range",
        "insertion_boundary",
        "horizontal_drift",
        "vertical_drift",
        "alignment",
        "fragments",
        "used_rect",
      ];
      if (allowedReasons.includes(reason)) {
        this.emit(`event=paragraph_layout_failure reason=${reason}`);
      }
      return;
    }
    if (code in helperEvents) {
      this.emit(helperEvents[code as HelperFixtureEvent]);
    }
  }

  private emit(fields: string): void {
    try {
      this.sink(`autocompletion_fixture ${fields}\n`);
    } catch {
      // Fixture diagnostics are best-effort and must never affect the app.
    }
  }
}

function publicationStructureEvent(code: string): string | null {
  for (const phase of ["capture", "request"] as const) {
    for (const field of publicationStructureSchema) {
      const prefix = `fixture_structure_${phase}_${field.code}_`;
      if (!code.startsWith(prefix)) continue;
      const value = code.slice(prefix.length);
      if (!(field.values as readonly string[]).includes(value)) return null;
      return `event=${phase}_structure field=${field.output} category=${value}`;
    }
  }
  return null;
}

function geometryStructureEvent(code: string): string | null {
  for (const phase of ["capture", "request"] as const) {
    for (const field of geometryStructureSchema) {
      const prefix = `fixture_geometry_${phase}_${field.code}_`;
      if (!code.startsWith(prefix)) continue;
      const value = code.slice(prefix.length);
      if (!(field.values as readonly string[]).includes(value)) return null;
      return `event=${phase}_geometry field=${field.output} category=${value}`;
    }
  }
  return null;
}

export function createFixtureDiagnostics(
  environment: FixtureEnvironment,
  sink?: (line: string) => void,
): FixtureDiagnostics {
  const enabled = environment.AUTOCOMPLETION_VISUAL_FIXTURE === "1";
  return new FixtureDiagnostics(
    enabled,
    sink ?? (enabled ? createFixtureDiagnosticSink() : () => {}),
  );
}

export function createFixtureDiagnosticSink(
  output: FixtureDiagnosticOutput = process.stderr,
): (line: string) => void {
  let available = true;
  output.on("error", () => {
    available = false;
  });
  return (line) => {
    if (!available || output.destroyed || output.writable === false) return;
    try {
      output.write(line, (error) => {
        if (error) available = false;
      });
    } catch {
      available = false;
    }
  };
}
