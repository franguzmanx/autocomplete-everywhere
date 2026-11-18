import { spawn as spawnChild } from "node:child_process";
import { join } from "node:path";
import type { Writable } from "node:stream";
import { z } from "zod";

import {
  parseProtocolMessage,
  type ProtocolMessage,
} from "@autocompletion/protocol";

import type { HelperTimelineRecord } from "./pipeline-trace";

export type HelperState =
  | "not_started"
  | "starting"
  | "running"
  | "stopping"
  | "disabled";

export type HelperChild = {
  stdout: NodeJS.ReadableStream;
  stderr: NodeJS.ReadableStream;
  stdin: Writable;
  on(event: "exit", listener: (code: number | null, signal: string | null) => void): unknown;
  on(event: "error", listener: (error: Error) => void): unknown;
  kill(): boolean;
};

export type HelperDiagnostic = {
  code: string;
  byteLength?: number;
};

const publicationStructureSchema = {
  selection: ["start", "middle", "end"],
  selection_state: ["collapsed", "noncollapsed"],
  text_before: ["empty", "newline", "space", "letter", "other"],
  text_after: ["empty", "nonempty"],
  value: ["empty", "newline", "space", "letter", "other"],
  geometry: ["exact", "derived", "unavailable"],
} as const;
const publicationStructureCodes = ["capture", "request"].flatMap((phase) =>
  Object.entries(publicationStructureSchema).flatMap(([field, values]) =>
    values.map((value) => `structure_${phase}_${field}_${value}`),
  ),
);
const fieldContextCodes = ["capture", "request"].flatMap((phase) => [
  ...["single_line", "multiline"].map(
    (shape) => `field_${phase}_shape_${shape}`,
  ),
  `field_${phase}_related_none`,
  `field_${phase}_related_available`,
]);
const geometryStructureSchema = {
  input_frame: ["available", "unavailable"],
  direction: ["left_to_right", "right_to_left", "neutral", "ambiguous"],
  zero_length: ["available", "missing", "invalid"],
  preceding_glyph: ["available", "missing", "invalid"],
  following_glyph: ["available", "missing", "invalid"],
  line_edge: ["available", "missing", "invalid"],
  display: ["match", "no_match"],
  resolver: [
    "not_run",
    "resolved",
    "failed_no_candidates",
    "failed_invalid_candidate_bounds",
    "failed_outside_input_frame",
    "failed_line_height_mismatch",
    "failed_display_unavailable",
    "failed_conflicting_candidates",
  ],
  paragraph_start: ["available", "unavailable"],
  paragraph_metrics_reason: [
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
  paragraph_metrics: ["available", "unavailable"],
} as const;
const geometryStructureCodes = ["capture", "request"].flatMap((phase) =>
  Object.entries(geometryStructureSchema).flatMap(([field, values]) =>
    values.map((value) => `geometry_${phase}_${field}_${value}`),
  ),
);
const presenterRejectionReasons = [
  "stale_capture",
  "paragraph_empty_completion",
  "paragraph_focus_changed",
  "paragraph_capture_unavailable",
  "paragraph_selection_active",
  "paragraph_not_at_end",
  "paragraph_geometry_unavailable",
  "paragraph_caret_unavailable",
  "paragraph_field_unavailable",
  "paragraph_caret_invalid",
  "paragraph_field_invalid",
  "paragraph_caret_outside_field",
  "paragraph_display_unavailable",
  "paragraph_metrics_unavailable",
  "paragraph_prefix_mismatch",
  "paragraph_layout",
  "paragraph_outside_visible_field",
  "single_line_layout",
  "display_rejected",
] as const;
const paragraphLayoutFailureReasons = [
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
] as const;

const fixtureDiagnosticCodes = new Set([
  "transform_invoked", "transform_captured", "transform_requested", "transform_received",
  "transform_inserted", "transform_capture_unavailable", "transform_selection_unavailable",
  "transform_generation_failed", "transform_unchanged", "transform_source_changed",
  "transform_insertion_failed", "transform_cancelled",
  ...["available", "no_visible_sources", "deadline"].map((outcome) => `source_read_${outcome}`),
  ...["left", "right", "top", "bottom"].flatMap((edge) =>
    ["none", "subpixel", "small", "line", "multiple_lines"].map((amount) => `overflow_${edge}_${amount}`),
  ),
  ...["slices", "capacity"].flatMap((kind) =>
    Array.from({ length: 10 }, (_, count) => `overflow_${kind}_${count}`),
  ),
  ...["element", "provider", "selection", "selection_no_value", "selection_unsupported", "selection_unavailable", "selection_invalid_value", "selection_mapping", "selection_outside_field", "selection_ancestry", "selection_ancestry_limit", "element_range", "field_value", "field_selection", "focused_text", "before", "selected", "after", "success"].map(
    (stage) => `web_read_${stage}`,
  ),
  ...["field", "draft", "selection", "related_fields", "sources", "metadata", "source_membership", "source_order", "source_content"].map(
    (part) => `change_${part}`,
  ),
  ...["marker_selection", "node_value", "line_value", "node_containment", "node_is_text", "node_candidate_available", "node_candidate_selected"].flatMap(
    (part) => ["yes", "no"].map((value) => `web_caret_${part}_${value}`),
  ),
  "capture_captured_exact",
  "capture_captured_derived",
  "capture_captured_geometry_unavailable",
  "capture_skipped_accessibility_unavailable",
  "capture_skipped_unsupported_application",
  "capture_skipped_unsupported_role",
  "capture_skipped_secure_field",
  "capture_skipped_value_missing",
  "capture_skipped_range_missing",
  "capture_skipped_range_out_of_bounds",
  "capture_skipped_marker_read_failed",
  "typography_word_measurement",
  "typography_owned_node_estimated",
  "typography_owned_visual_line_measured",
  "typography_focused_range_available",
  "typography_focused_range_ineligible",
  "typography_focused_range_text_disagreement",
  "typography_focused_range_read_unavailable",
  "typography_focused_range_result_disagreement",
  "typography_focused_range_font_missing",
  "typography_attributed_bounds_invalid",
  "typography_attributed_line_missing",
  "typography_attributed_caret_missing",
  "typography_attributed_field_missing",
  "typography_attributed_caret_not_narrow",
  "typography_attributed_outside_field",
  "typography_attributed_sample_not_single_line",
  "typography_attributed_caret_outside_line",
  "typography_attributed_sample_not_adjacent",

  "typography_default_font_unavailable",
  "typography_attributed_sample_unavailable",
  "typography_attributed_font_unavailable",
  "typography_attributed_width_invalid",
  "typography_attributed_scale_outside_bounds",
  "typography_attributed_attributed_width_verified",
  "typography_empty_bold",
  "typography_empty_regular",
  "typography_empty_unavailable",
  "typography_authored_bold",
  "typography_authored_regular",
  "typography_authored_unavailable",

  "keyboard_host_text",
  "keyboard_host_ambiguous_text",
  "keyboard_host_state_changed",
  "keyboard_dismiss_suggestion",
  "keyboard_accept_suggestion",
  "keyboard_next_alternative",
  "keyboard_previous_alternative",
  "command_received_final",
  "final_result_text",
  "final_result_silence",
  "session_accepted",
  "session_rejected_current",
  "session_ignored_stale",
  "presentation_available",
  "presentation_unavailable_session",
  "presentation_unavailable_anchor",
  "presentation_unavailable_reacquiring",
  "present_invoked",
  "presenter_shown",
  "presenter_rejected",
  "visual_font_exact",
  "visual_font_system_fallback",
  "visual_font_estimated",
  "visual_font_unavailable",
  "visual_horizontal_zero",
  "visual_horizontal_subpixel",
  "visual_horizontal_small",
  "visual_horizontal_large",
  ...presenterRejectionReasons.map(
    (reason) => `presenter_rejected_reason_${reason}`,
  ),
  ...paragraphLayoutFailureReasons.map(
    (reason) => `presenter_paragraph_layout_failure_${reason}`,
  ),
  ...publicationStructureCodes,
  ...fieldContextCodes,
  ...geometryStructureCodes,
]);
const fixtureDiagnosticLines = [...fixtureDiagnosticCodes].map(
  (code) => `fixture:${code}`,
);
const nonnegativeNumber = z.number().finite().nonnegative();
const nonnegativeInteger = z.number().int().nonnegative();
const helperTimelineBase = {
  v: z.literal(1),
  proc: z.literal("helper"),
  monoMs: nonnegativeNumber,
  wallMs: nonnegativeNumber,
} as const;
const helperTimelineIdentity = {
  requestId: z.string().uuid(),
  focusSequence: nonnegativeInteger,
} as const;
const overflowAmount = z.enum(["none", "subpixel", "small", "line", "multiple_lines"]);
const helperTimelineSchema = z.discriminatedUnion("event", [
  z.strictObject({
    ...helperTimelineBase,
    focusSequence: nonnegativeInteger,
    event: z.literal("input_observed"),
    attrs: z.strictObject({
      captureSeq: nonnegativeInteger,
      captureMs: nonnegativeNumber,
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    focusSequence: nonnegativeInteger,
    event: z.literal("content_stable"),
    attrs: z.strictObject({ quietMs: nonnegativeNumber }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    focusSequence: nonnegativeInteger.optional(),
    event: z.literal("capture_skipped"),
    attrs: z.strictObject({
      reason: z.enum([
        "accessibility_unavailable",
        "unsupported_application",
        "unsupported_role",
        "secure_field",
        "value_missing",
        "range_missing",
        "range_out_of_bounds",
        "marker_read_failed",
      ]),
      consecutive: z.number().int().positive(),
      sinceLastOkMs: nonnegativeNumber.optional(),
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("request_written"),
    attrs: z.strictObject({
      surface: z.enum(["native", "web"]),
      shape: z.enum(["single_line", "multiline"]),
      textBeforeBucket: z.enum(["zero", "lt_100", "lt_1k", "lt_8k", "gte_8k"]),
      textAfterBucket: z.enum(["zero", "lt_100", "lt_1k", "lt_8k", "gte_8k"]),
      hasSelection: z.boolean(),
      related: z.number().int().min(0).max(3),
      geometry: z.enum(["exact", "derived", "unavailable"]),
      anchorResolved: z.boolean(),
      explicit: z.boolean(),
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("final_received"),
    attrs: z.strictObject({
      sinceRequestMs: nonnegativeNumber,
      disposition: z.enum(["accepted", "rejected_current", "ignored_stale"]),
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("typography_measured"),
    attrs: z.strictObject({
      empty: z.boolean(), estimated: z.boolean(), paragraph: z.boolean(),
      fontSize: nonnegativeNumber, caretHeight: nonnegativeNumber, inputHeight: nonnegativeNumber,
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("presented"),
    attrs: z.strictObject({
      sinceFinalMs: nonnegativeNumber,
      anchorWaitMs: nonnegativeNumber,
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("presentation_overflow"),
    attrs: z.strictObject({
      left: overflowAmount, right: overflowAmount, top: overflowAmount, bottom: overflowAmount,
      completionLines: z.number().int().min(0).max(9),
      availableLines: z.number().int().min(0).max(9),
      fitting: z.enum(["not_allowed", "no_visible_line", "no_safe_boundary", "relayout_rejected", "fitted"]),
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("present_rejected"),
    attrs: z.strictObject({
      sinceFinalMs: nonnegativeNumber,
      anchorWaitMs: nonnegativeNumber,
      rejection: z.enum([
        "session_unavailable",
        "anchor_unavailable",
        "source_changed",
        "anchor_reacquiring",
        "anchor_validation",
        "presenter_stale_capture",
        "presenter_paragraph_empty_completion",
        "presenter_paragraph_focus_changed",
        "presenter_paragraph_capture_unavailable",
        "presenter_paragraph_selection_active",
        "presenter_paragraph_not_at_end",
        "presenter_paragraph_geometry_unavailable",
        "presenter_paragraph_caret_unavailable",
        "presenter_paragraph_field_unavailable",
        "presenter_paragraph_caret_invalid",
        "presenter_paragraph_field_invalid",
        "presenter_paragraph_caret_outside_field",
        "presenter_paragraph_display_unavailable",
        "presenter_paragraph_metrics_unavailable",
        "presenter_paragraph_prefix_mismatch",
        "presenter_paragraph_layout",
        "presenter_paragraph_outside_visible_field",
        "presenter_single_line_layout",
        "presenter_display_rejected",
      ]),
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("cancel_written"),
    attrs: z.strictObject({
      reason: z.enum(["content_changed", "focus_changed", "dismissed", "shutdown"]),
      sessionState: z.enum(["requesting", "ready"]),
      typedAppend: z.boolean(),
    }),
  }),
  z.strictObject({
    ...helperTimelineBase,
    ...helperTimelineIdentity,
    event: z.literal("interaction"),
    attrs: z.strictObject({
      outcome: z.enum([
        "shown",
        "accepted_full",
        "accepted_partial",
        "dismissed",
        "typed_through",
        "edited_after_acceptance",
        "removed_after_acceptance",
        "observation_unavailable",
        "stale",
        "failed",
      ]),
      sinceShownMs: nonnegativeNumber,
    }),
  }),
]);

export function resolvePackagedHelperPath(resourcesPath: string): string {
  return join(resourcesPath, "native", "AutocompleteHelper");
}

type HelperProcessDependencies = {
  helperPath: string;
  parentPid?: number;
  spawn?: (path: string, args: string[]) => HelperChild;
  onMessage(message: ProtocolMessage): void;
  onDiagnostic(diagnostic: HelperDiagnostic): void;
  onTimeline?(event: HelperTimelineRecord): void;
  onReady?(): void;
  onStateChange?(state: HelperState): void;
  handshakeTimeoutMs?: number;
};

// Accommodates the bounded captured context plus five 12k alternatives,
// including worst-case JSON escaping. Count UTF-16 units, as the parser does.
const MAX_HELPER_STDOUT_LINE_LENGTH = 4_194_304;

export class HelperProcessManager {
  readonly #dependencies: Required<
    Pick<
      HelperProcessDependencies,
      | "helperPath"
      | "parentPid"
      | "spawn"
      | "handshakeTimeoutMs"
      | "onStateChange"
      | "onReady"
      | "onTimeline"
    >
  > &
    Pick<HelperProcessDependencies, "onMessage" | "onDiagnostic">;
  #state: HelperState = "not_started";
  #child: HelperChild | null = null;
  #restartCount = 0;
  #stdoutBuffer = "";
  #stderrFixtureBuffer = "";
  #handshakeTimer: NodeJS.Timeout | null = null;
  #startPromise: Promise<void> | null = null;
  #resolveStart: (() => void) | null = null;
  #rejectStart: ((error: Error) => void) | null = null;

  constructor(dependencies: HelperProcessDependencies) {
    this.#dependencies = {
      ...dependencies,
      parentPid: dependencies.parentPid ?? process.pid,
      spawn:
        dependencies.spawn ??
        ((path, args) =>
          spawnChild(path, args, {
            stdio: ["pipe", "pipe", "pipe"],
            env: {
              ...process.env,
              AUTOCOMPLETION_RUNTIME_DIAGNOSTICS: "1",
            },
          }) as HelperChild),
      handshakeTimeoutMs: dependencies.handshakeTimeoutMs ?? 2_000,
      onReady: dependencies.onReady ?? (() => {}),
      onStateChange: dependencies.onStateChange ?? (() => {}),
      onTimeline: dependencies.onTimeline ?? (() => {}),
    };
  }

  #setState(value:HelperState):void { this.#state=value; this.#dependencies.onStateChange(value); }
  async restart():Promise<void> {
    this.stop();
    const deadline=Date.now()+2_000;
    while(this.#state==="stopping" && Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,25));
    if(this.#state==="stopping")throw new Error("Helper is still stopping");
    this.#setState("not_started");return this.start();
  }

  get state(): HelperState {
    return this.#state;
  }

  start(): Promise<void> {
    if (this.#state === "running") return Promise.resolve();
    if (this.#startPromise) return this.#startPromise;
    if (this.#state === "disabled") {
      return Promise.reject(new Error("helper_disabled"));
    }

    this.#restartCount = 0;
    const startPromise = new Promise<void>((resolve, reject) => {
      this.#resolveStart = resolve;
      this.#rejectStart = reject;
    });
    this.#startPromise = startPromise;
    this.#spawn();
    return startPromise;
  }

  stop(): void {
    const child = this.#child;
    this.#clearHandshakeTimer();
    if (!child) {
      this.#setState("not_started");
      return;
    }

    this.#setState("stopping");
    child.stdin.end();
    const forceKill = setTimeout(() => {
      if (this.#child === child) child.kill();
    }, 1_000);
    forceKill.unref();
  }

  send(message: ProtocolMessage): void {
    if (this.#state !== "running" || !this.#child) {
      throw new Error("helper_not_running");
    }
    const child = this.#child;
    if (!child.stdin.writable || child.stdin.destroyed || child.stdin.writableEnded) {
      this.#fail("helper_stdin_error", child);
      return;
    }
    child.stdin.write(`${JSON.stringify(message)}\n`, (error) => {
      if (!error || this.#child !== child || this.#state === "stopping") return;
      this.#fail("helper_stdin_error", child);
    });
  }

  #spawn(): void {
    this.#setState("starting");
    this.#stdoutBuffer = "";
    this.#stderrFixtureBuffer = "";
    let child: HelperChild;
    try {
      child = this.#dependencies.spawn(this.#dependencies.helperPath, [
        "--parent-pid",
        String(this.#dependencies.parentPid),
      ]);
    } catch {
      this.#fail("helper_spawn_error", null);
      return;
    }
    this.#child = child;

    child.stdout.on("data", (chunk: Buffer | string) => {
      if (this.#child !== child) return;
      this.#consumeStdout(String(chunk));
    });
    child.stderr.on("data", (chunk: Buffer | string) => {
      if (this.#child !== child) return;
      this.#consumeStderr(String(chunk));
    });
    child.stdin.on("error", () => {
      if (this.#child !== child) return;
      if (this.#state === "stopping") {
        this.#child = null;
        this.#clearHandshakeTimer();
        this.#setState("not_started");
        return;
      }
      this.#fail("helper_stdin_error", child);
    });
    child.on("error", () => {
      if (this.#child !== child) return;
      if (this.#state === "stopping") {
        this.#child = null;
        this.#clearHandshakeTimer();
        this.#setState("not_started");
        return;
      }
      this.#fail("helper_spawn_error", child);
    });
    child.on("exit", (code, signal) => {
      if (this.#child !== child) return;
      this.#child = null;
      this.#clearHandshakeTimer();
      if (this.#state === "stopping") {
        this.#setState("not_started");
        return;
      }
      this.#fail(`helper_exit_${code ?? signal ?? "unknown"}`, child);
    });

    this.#handshakeTimer = setTimeout(
      () => this.#fail("helper_handshake_timeout", child),
      this.#dependencies.handshakeTimeoutMs,
    );
    this.#handshakeTimer.unref();
  }

  #consumeStderr(chunk: string): void {
    let candidate = this.#stderrFixtureBuffer + chunk;
    this.#stderrFixtureBuffer = "";
    const fixturePrefix = "fixture:";
    const timelinePrefix = "timeline:";
    while (true) {
      const newline = candidate.indexOf("\n");
      if (newline < 0) {
        if (
          fixtureDiagnosticLines.some((line) => line.startsWith(candidate)) ||
          timelinePrefix.startsWith(candidate) ||
          candidate.startsWith(timelinePrefix)
        ) {
          if (Buffer.byteLength(candidate) > 32_768) {
            this.#dependencies.onDiagnostic({ code: "helper_invalid_timeline" });
            return;
          }
          this.#stderrFixtureBuffer = candidate;
        } else if (candidate.length > 0) {
          this.#dependencies.onDiagnostic({
            code: "helper_stderr",
            byteLength: Buffer.byteLength(candidate),
          });
        }
        return;
      }
      const line = candidate.slice(0, newline);
      candidate = candidate.slice(newline + 1);
      const code = line.slice(fixturePrefix.length);
      if (line.startsWith(timelinePrefix)) {
        let raw: unknown;
        try {
          raw = JSON.parse(line.slice(timelinePrefix.length));
        } catch {
          raw = null;
        }
        const parsed = helperTimelineSchema.safeParse(raw);
        if (parsed.success) {
          this.#dependencies.onTimeline(parsed.data as HelperTimelineRecord);
        } else {
          this.#dependencies.onDiagnostic({ code: "helper_invalid_timeline" });
        }
      } else if (line.startsWith(fixturePrefix) && fixtureDiagnosticCodes.has(code)) {
        this.#dependencies.onDiagnostic({ code: `fixture_${code}` });
      } else {
        this.#dependencies.onDiagnostic({
          code: "helper_stderr",
          byteLength: Buffer.byteLength(`${line}\n`),
        });
      }
      if (candidate.length === 0) return;
    }
  }

  #consumeStdout(chunk: string): void {
    this.#stdoutBuffer += chunk;
    while (true) {
      const newline = this.#stdoutBuffer.indexOf("\n");
      const frameLength = newline < 0 ? this.#stdoutBuffer.length : newline;
      if (frameLength > MAX_HELPER_STDOUT_LINE_LENGTH) {
        this.#stdoutBuffer = "";
        this.#fail("helper_line_too_large", this.#child);
        return;
      }
      if (newline < 0) return;
      const line = this.#stdoutBuffer.slice(0, newline);
      this.#stdoutBuffer = this.#stdoutBuffer.slice(newline + 1);
      this.#consumeLine(line);
      if (!this.#child) return;
    }
  }

  #consumeLine(line: string): void {
    let raw: unknown;
    try {
      raw = JSON.parse(line);
    } catch {
      this.#fail("helper_invalid_json", this.#child);
      return;
    }

    const parsed = parseProtocolMessage(raw);
    if ("ok" in parsed) {
      this.#fail(`helper_${parsed.code}`, this.#child);
      return;
    }

    if (this.#state === "starting") {
      if (parsed.type !== "hello") {
        this.#fail("helper_missing_hello", this.#child);
        return;
      }
      this.#clearHandshakeTimer();
      this.#setState("running");
      this.#dependencies.onReady();
      this.#resolveStart?.();
      this.#clearStartPromise();
      return;
    }

    if (parsed.type === "hello") {
      this.#fail("helper_duplicate_hello", this.#child);
      return;
    }
    this.#dependencies.onMessage(parsed);
  }

  #fail(reason: string, child: HelperChild | null): void {
    this.#dependencies.onDiagnostic({ code: reason });
    this.#clearHandshakeTimer();
    if (child && this.#child === child) {
      this.#child = null;
      child.kill();
    }

    if (this.#restartCount < 1) {
      this.#restartCount += 1;
      this.#spawn();
      return;
    }

    this.#setState("disabled");
    this.#rejectStart?.(new Error(reason));
    this.#clearStartPromise();
  }

  #clearHandshakeTimer(): void {
    if (this.#handshakeTimer) clearTimeout(this.#handshakeTimer);
    this.#handshakeTimer = null;
  }

  #clearStartPromise(): void {
    this.#startPromise = null;
    this.#resolveStart = null;
    this.#rejectStart = null;
  }
}
