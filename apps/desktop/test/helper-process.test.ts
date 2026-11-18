import { readFileSync } from "node:fs";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";

import { describe, expect, test, vi } from "vitest";

import {
  HelperProcessManager,
  resolvePackagedHelperPath,
  type HelperChild,
} from "../src/main/helper-process";

const validHello = JSON.stringify({
  protocolVersion: 5,
  type: "hello",
  payload: {
    platform: "macos",
    helperVersion: "0.0.1",
    capabilities: ["lifecycle"],
  },
});

class FakeChild extends EventEmitter implements HelperChild {
  stdout = new PassThrough();
  stderr = new PassThrough();
  stdin = new PassThrough();
  kill = vi.fn(() => true);
}

function managerWith(children: FakeChild[], onReady = vi.fn()) {
  const diagnostics: unknown[] = [];
  const timelines: unknown[] = [];
  const onMessage = vi.fn();
  const spawn = vi.fn(() => {
    const child = children.shift();
    if (!child) throw new Error("No fake child available");
    return child;
  });
  const manager = new HelperProcessManager({
    helperPath: "/app/AutocompleteHelper",
    parentPid: 4242,
    spawn,
    onMessage,
    onDiagnostic: (diagnostic) => diagnostics.push(diagnostic),
    onTimeline: (event) => timelines.push(event),
    onReady,
    handshakeTimeoutMs: 100,
  });
  return { manager, spawn, diagnostics, timelines, onMessage, onReady };
}

describe("helper process lifecycle", () => {
  test("accepts one valid hello and passes the parent PID", async () => {
    const child = new FakeChild();
    const { manager, spawn } = managerWith([child]);
    const started = manager.start();
    child.stdout.write(`${validHello}\n`);
    await started;

    expect(manager.state).toBe("running");
    expect(spawn).toHaveBeenCalledWith("/app/AutocompleteHelper", [
      "--parent-pid",
      "4242",
    ]);
    expect(resolvePackagedHelperPath("/app/resources")).toBe(
      "/app/resources/native/AutocompleteHelper",
    );
  });

  test("restarts once after malformed stdout", async () => {
    const first = new FakeChild();
    const second = new FakeChild();
    const { manager, spawn } = managerWith([first, second]);
    const started = manager.start();
    first.stdout.write("not-json\n");
    second.stdout.write(`${validHello}\n`);
    await started;

    expect(spawn).toHaveBeenCalledTimes(2);
    expect(first.kill).toHaveBeenCalledOnce();
    expect(manager.state).toBe("running");
  });

  test("announces readiness again after a running helper is replaced", async () => {
    const first = new FakeChild();
    const second = new FakeChild();
    const { manager, onReady } = managerWith([first, second]);
    const started = manager.start();
    first.stdout.write(`${validHello}\n`);
    await started;

    first.emit("exit", 1, null);
    second.stdout.write(`${validHello}\n`);

    expect(manager.state).toBe("running");
    expect(onReady).toHaveBeenCalledTimes(2);
  });

  test("turns a broken stdin pipe into a controlled helper restart", async () => {
    const first = new FakeChild();
    const second = new FakeChild();
    const { manager, diagnostics } = managerWith([first, second]);
    const started = manager.start();
    first.stdout.write(`${validHello}\n`);
    await started;

    expect(() => first.stdin.emit("error", Object.assign(new Error("broken pipe"), {
      code: "EPIPE",
    }))).not.toThrow();
    second.stdout.write(`${validHello}\n`);

    expect(manager.state).toBe("running");
    expect(diagnostics).toContainEqual({ code: "helper_stdin_error" });
  });

  test("restarts once when the helper launch emits an error", async () => {
    const first = new FakeChild();
    const second = new FakeChild();
    const { manager, spawn, diagnostics } = managerWith([first, second]);
    const started = manager.start();

    expect(() =>
      first.emit("error", new Error("private helper launch details")),
    ).not.toThrow();
    second.stdout.write(`${validHello}\n`);
    await started;

    expect(spawn).toHaveBeenCalledTimes(2);
    expect(manager.state).toBe("running");
    expect(diagnostics).toContainEqual({ code: "helper_spawn_error" });
    expect(JSON.stringify(diagnostics)).not.toContain(
      "private helper launch details",
    );
  });

  test("disables after the controlled restart also emits a launch error", async () => {
    const first = new FakeChild();
    const second = new FakeChild();
    const { manager, spawn, diagnostics } = managerWith([first, second]);
    const started = manager.start();

    expect(() =>
      first.emit("error", new Error("first launch details")),
    ).not.toThrow();
    expect(() =>
      second.emit("error", new Error("second launch details")),
    ).not.toThrow();

    await expect(started).rejects.toThrow("helper_spawn_error");
    expect(spawn).toHaveBeenCalledTimes(2);
    expect(manager.state).toBe("disabled");
    expect(diagnostics).toEqual([
      { code: "helper_spawn_error" },
      { code: "helper_spawn_error" },
    ]);
    expect(JSON.stringify(diagnostics)).not.toContain("launch details");
  });

  test("turns synchronous spawn failures into a bounded start rejection", async () => {
    const diagnostics: unknown[] = [];
    const spawn = vi.fn(() => {
      throw new Error("private synchronous launch details");
    });
    const manager = new HelperProcessManager({
      helperPath: "/app/AutocompleteHelper",
      parentPid: 4242,
      spawn,
      onMessage: vi.fn(),
      onDiagnostic: (diagnostic) => diagnostics.push(diagnostic),
      handshakeTimeoutMs: 100,
    });

    const started = manager.start();

    await expect(started).rejects.toThrow("helper_spawn_error");
    expect(spawn).toHaveBeenCalledTimes(2);
    expect(manager.state).toBe("disabled");
    expect(diagnostics).toEqual([
      { code: "helper_spawn_error" },
      { code: "helper_spawn_error" },
    ]);
    expect(JSON.stringify(diagnostics)).not.toContain(
      "private synchronous launch details",
    );
  });

  test("disables after the controlled restart also has a protocol mismatch", async () => {
    const first = new FakeChild();
    const second = new FakeChild();
    const { manager } = managerWith([first, second]);
    const started = manager.start();
    first.stdout.write('{"protocolVersion":1,"type":"hello"}\n');
    second.stdout.write('{"protocolVersion":1,"type":"hello"}\n');

    await expect(started).rejects.toThrow("helper_protocol_version_mismatch");
    expect(manager.state).toBe("disabled");
  });

  test("forwards only known alternative-navigation diagnostics", async () => {
    const child = new FakeChild();
    const { manager, diagnostics } = managerWith([child]);
    const started = manager.start();
    child.stdout.write(`${validHello}\n`);
    await started;
    child.stderr.write("fixture:keyboard_next_alternative\nfixture:keyboard_previous_alternative\n");
    expect(diagnostics).toEqual([
      {code:"fixture_keyboard_next_alternative"}, {code:"fixture_keyboard_previous_alternative"},
    ]);
    manager.stop();
  });

  test("never forwards helper stderr content", async () => {
    const child = new FakeChild();
    const { manager, diagnostics } = managerWith([child]);
    const started = manager.start();
    child.stderr.write("captured private field text");
    child.stdout.write(`${validHello}\n`);
    await started;

    expect(diagnostics).toContainEqual({ code: "helper_stderr", byteLength: 27 });
    expect(JSON.stringify(diagnostics)).not.toContain("private field");
  });

  test("retains rendered font measurements and rejects message content", async () => {
    const child = new FakeChild();
    const { manager, diagnostics, timelines } = managerWith([child]);
    const started = manager.start();
    const envelope = { v: 1, proc: "helper", event: "typography_measured",
      requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63", focusSequence: 7,
      monoMs: 100, wallMs: 100,
      attrs: { empty: true, estimated: true, paragraph: false, fontSize: 31, caretHeight: 40, inputHeight: 100 } };
    child.stderr.write(`timeline:${JSON.stringify(envelope)}\n`);
    child.stderr.write(`timeline:${JSON.stringify({ ...envelope, attrs: { ...envelope.attrs, text: "PRIVATE" } })}\n`);
    child.stdout.write(`${validHello}\n`); await started;
    expect(timelines).toEqual([envelope]);
    expect(diagnostics).toEqual([{ code: "helper_invalid_timeline" }]);
    expect(JSON.stringify({ timelines, diagnostics })).not.toContain("PRIVATE");
    manager.stop();
  });

  test("retains bounded overflow evidence with its request and rejects extra content", async () => {
    const child = new FakeChild();
    const { manager, diagnostics, timelines } = managerWith([child]);
    const started = manager.start();
    const envelope = { v: 1, proc: "helper", event: "presentation_overflow",
      requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63", focusSequence: 7,
      monoMs: 100, wallMs: 100,
      attrs: { left: "none", right: "small", top: "none", bottom: "multiple_lines", completionLines: 3, availableLines: 1, fitting: "no_visible_line" } };
    const line = `timeline:${JSON.stringify(envelope)}\n`;
    child.stderr.write(line.slice(0, 25)); child.stderr.write(line.slice(25));
    for (const attrs of [{ ...envelope.attrs, text: "PRIVATE" }, { ...envelope.attrs, availableLines: 99 }]) {
      child.stderr.write(`timeline:${JSON.stringify({ ...envelope, attrs })}\n`);
    }
    child.stdout.write(`${validHello}\n`); await started;
    expect(timelines).toEqual([envelope]);
    expect(diagnostics).toEqual([{code: "helper_invalid_timeline"}, {code: "helper_invalid_timeline"}]);
    expect(JSON.stringify({timelines, diagnostics})).not.toContain("PRIVATE");
    manager.stop();
  });

  test("forwards a fragmented content-free helper timeline envelope", async () => {
    const child = new FakeChild();
    const { manager, diagnostics, timelines } = managerWith([child]);
    const started = manager.start();
    const envelope = {
      v: 1,
      requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
      focusSequence: 7,
      proc: "helper",
      event: "request_written",
      monoMs: 12_300.5,
      wallMs: 1_788_540_000_123,
      attrs: {
        surface: "web",
        shape: "multiline",
        textBeforeBucket: "zero",
        textAfterBucket: "lt_1k",
        hasSelection: false,
        related: 3,
        geometry: "derived",
        anchorResolved: true,
        explicit: true,
      },
    };
    const line = `timeline:${JSON.stringify(envelope)}\n`;
    child.stderr.write(line.slice(0, 19));
    child.stderr.write(line.slice(19));
    child.stdout.write(`${validHello}\n`);
    await started;

    expect(timelines).toEqual([envelope]);
    expect(diagnostics).toEqual([]);
  });

  test.each([
    "value_missing",
    "range_missing",
    "range_out_of_bounds",
    "marker_read_failed",
  ])("accepts the helper capture skip reason %s", async (reason) => {
    const child = new FakeChild();
    const { manager, diagnostics, timelines } = managerWith([child]);
    const started = manager.start();
    const envelope = {
      v: 1,
      proc: "helper",
      event: "capture_skipped",
      monoMs: 12_300.5,
      wallMs: 1_788_540_000_123,
      attrs: { reason, consecutive: 1 },
    };
    child.stderr.write(`timeline:${JSON.stringify(envelope)}\n`);
    child.stdout.write(`${validHello}\n`);
    await started;

    expect(timelines).toEqual([envelope]);
    expect(diagnostics).toEqual([]);
  });

  test("forwards only bounded marker ownership failure categories", async () => {
    const child = new FakeChild();
    const { manager, diagnostics } = managerWith([child]);
    const started = manager.start();
    const stages = ["selection_mapping", "selection_outside_field", "selection_ancestry", "selection_ancestry_limit"];
    child.stderr.write(stages.map(stage => `fixture:web_read_${stage}\n`).join(""));
    child.stderr.write("fixture:web_read_private-draft\n");
    child.stdout.write(`${validHello}\n`);
    await started;
    expect(diagnostics.filter((entry) => typeof entry === "object" && entry !== null
      && "code" in entry && typeof entry.code === "string" && entry.code.startsWith("fixture_")))
      .toEqual(stages.map(stage => ({code: `fixture_web_read_${stage}`})));
    expect(JSON.stringify(diagnostics)).not.toContain("private-draft");
  });

  test("forwards bounded overflow and source evidence even across stderr chunks", async () => {
    const child = new FakeChild();
    const { manager, diagnostics } = managerWith([child]);
    const started = manager.start();
    child.stderr.write("fixture:overflow_bot");
    child.stderr.write("tom_multiple_lines\nfixture:overflow_slices_3\nfixture:overflow_capacity_1\nfixture:source_read_deadline\n");
    child.stderr.write("fixture:overflow_slices_999\nfixture:source_read_private\n");
    child.stdout.write(`${validHello}\n`);
    await started;
    expect(diagnostics.filter((entry) => typeof entry === "object" && entry !== null
      && "code" in entry && typeof entry.code === "string" && entry.code.startsWith("fixture_"))).toEqual([
      { code: "fixture_overflow_bottom_multiple_lines" },
      { code: "fixture_overflow_slices_3" },
      { code: "fixture_overflow_capacity_1" },
      { code: "fixture_source_read_deadline" },
    ]);
    expect(JSON.stringify(diagnostics)).not.toContain("private");
  });

  test("forwards only allowlisted fixture diagnostics from helper stderr", async () => {
    const child = new FakeChild();
    const { manager, diagnostics } = managerWith([child]);
    const started = manager.start();
    child.stderr.write("fixture:capture_skipped_value_");
    child.stderr.write(
      "missing\nfixture:capture_skipped_range_missing\nfixture:capture_skipped_range_out_of_bounds\nfixture:capture_skipped_marker_read_failed\nfixture:capture_skipped_secure_field\nfixture:capture_skipped_unsupported_role\nfixture:structure_capture_selection_middle\nfixture:structure_request_text_before_newline\nfixture:field_capture_shape_single_line\nfixture:field_capture_related_available\nfixture:geometry_capture_preceding_glyph_missing\nfixture:geometry_capture_paragraph_metrics_unavailable\nfixture:geometry_capture_paragraph_metrics_reason_paragraph_attributes_unavailable\nfixture:geometry_request_resolver_failed_no_candidates\nfixture:command_received_final\nfixture:final_result_silence\nfixture:session_accepted\nfixture:presentation_unavailable_anchor\nfixture:present_invoked\nfixture:presenter_rejected\nfixture:presenter_rejected_reason_paragraph_outside_visible_field\n",
    );
    child.stderr.write("fixture:structure_request_text_before_private\n");
    child.stderr.write("fixture:geometry_request_resolver_private\n");
    child.stderr.write("fixture:change_sources\nfixture:web_caret_marker_selection_no\n");
    child.stderr.write("fixture:web_read_field_selection\nfixture:web_read_success\nfixture:web_read_private\n");
    child.stderr.write("fixture:change_private\nfixture:web_caret_marker_selection_private\n");
    child.stderr.write("fixture:private_field_value\n");
    child.stdout.write(`${validHello}\n`);
    await started;

    expect(diagnostics).toContainEqual({
      code: "fixture_capture_skipped_value_missing",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_capture_skipped_range_missing",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_capture_skipped_range_out_of_bounds",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_capture_skipped_marker_read_failed",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_capture_skipped_secure_field",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_capture_skipped_unsupported_role",
    });
    expect(diagnostics).toContainEqual({ code: "fixture_change_sources" });
    expect(diagnostics).toContainEqual({ code: "fixture_web_caret_marker_selection_no" });
    expect(diagnostics).toContainEqual({ code: "fixture_web_read_field_selection" });
    expect(diagnostics).toContainEqual({ code: "fixture_web_read_success" });
    expect(JSON.stringify(diagnostics)).not.toContain("private");
    expect(diagnostics).toContainEqual({ code: "fixture_presenter_rejected" });
    expect(diagnostics).toContainEqual({
      code: "fixture_presenter_rejected_reason_paragraph_outside_visible_field",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_structure_capture_selection_middle",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_structure_request_text_before_newline",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_geometry_capture_preceding_glyph_missing",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_geometry_capture_paragraph_metrics_unavailable",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_geometry_capture_paragraph_metrics_reason_paragraph_attributes_unavailable",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_field_capture_shape_single_line",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_field_capture_related_available",
    });
    expect(diagnostics).toContainEqual({
      code: "fixture_geometry_request_resolver_failed_no_candidates",
    });
    expect(diagnostics).toContainEqual({ code: "fixture_command_received_final" });
    expect(diagnostics).toContainEqual({ code: "fixture_final_result_silence" });
    expect(diagnostics).toContainEqual({ code: "fixture_session_accepted" });
    expect(diagnostics).toContainEqual({
      code: "fixture_presentation_unavailable_anchor",
    });
    expect(diagnostics).toContainEqual({ code: "fixture_present_invoked" });
    expect(diagnostics).toContainEqual({
      code: "helper_stderr",
      byteLength: 28,
    });
    expect(JSON.stringify(diagnostics)).not.toContain("private_field_value");
    expect(JSON.stringify(diagnostics)).not.toContain("text_before_private");
    expect(JSON.stringify(diagnostics)).not.toContain("resolver_private");
  });

  test("closes stdin and does not restart during clean shutdown", async () => {
    const child = new FakeChild();
    const { manager, spawn } = managerWith([child]);
    const started = manager.start();
    child.stdout.write(`${validHello}\n`);
    await started;

    manager.stop();
    child.emit("exit", 0, null);

    expect(child.stdin.writableEnded).toBe(true);
    expect(spawn).toHaveBeenCalledOnce();
    expect(manager.state).toBe("not_started");
  });

  test("does not restart when the child errors during clean shutdown", async () => {
    const child = new FakeChild();
    const { manager, spawn, diagnostics } = managerWith([child]);
    const started = manager.start();
    child.stdout.write(`${validHello}\n`);
    await started;

    manager.stop();
    expect(() =>
      child.emit("error", new Error("shutdown details")),
    ).not.toThrow();

    expect(spawn).toHaveBeenCalledOnce();
    expect(manager.state).toBe("not_started");
    expect(diagnostics).toEqual([]);
  });

  test("accepts a fully escaped alternative request across stdout chunks", async () => {
    const child = new FakeChild();
    const { manager, onMessage, diagnostics } = managerWith([child]);
    const started = manager.start();
    child.stdout.write(`${validHello}\n`);
    await started;
    const request = {
      protocolVersion:5, type:"suggestion_request",
      identity:{requestId:"da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",focusSequence:1,contentSignature:"0123456789abcdef",timestampMs:1},
      payload:{appId:"com.apple.Notes",surface:"text_editor",textBefore:"界".repeat(8000),textAfter:"界".repeat(2000),selectedText:"界".repeat(2000),
        explicit:true, alternativeTo:Array(5).fill("界".repeat(12000)),artifacts:[],
        fieldContext:{shape:"multiline",sources:[],relatedFields:[]}},
    };
    const line = JSON.stringify(request).replaceAll("界", "\\u754c") + "\n";
    for (let offset = 0; offset < line.length; offset += 4096) child.stdout.write(line.slice(offset, offset + 4096));
    expect(onMessage).toHaveBeenCalledWith(request);
    expect(manager.state).toBe("running");
    expect(diagnostics).toEqual([]);
    manager.stop();
  });

  test.each(["", "\n"])("rejects an oversized stdout frame before parsing, terminator %j", async (terminator) => {
    const child = new FakeChild();
    const replacement = new FakeChild();
    const { manager, diagnostics } = managerWith([child,replacement]);
    const started = manager.start();
    child.stdout.write(`${validHello}\n`);
    await started;
    child.stdout.write("x".repeat(4_194_305) + terminator);
    expect(child.kill).toHaveBeenCalledOnce();
    expect(diagnostics).toContainEqual({code:"helper_line_too_large"});
    manager.stop();
  });

  test("accepts a bounded Unicode request larger than 32 KiB", async () => {
    const child = new FakeChild();
    const { manager, onMessage } = managerWith([child]);
    const started = manager.start();
    child.stdout.write(`${validHello}\n`);
    await started;
    const request = {
      protocolVersion: 5,
      type: "suggestion_request",
      identity: {
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        focusSequence: 1,
        contentSignature: "0123456789abcdef0123456789abcdef",
        timestampMs: 1_788_000_000_000,
      },
      payload: {
        appId: "com.apple.Notes",
        surface: "text_editor",
        textBefore: "界".repeat(8_000),
        textAfter: "界".repeat(2_000),
        selectedText: "界".repeat(2_000),
        explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "multiline",
          sources: [], relatedFields: [],
        },
      },
    };

    child.stdout.write(`${JSON.stringify(request)}\n`);

    expect(onMessage).toHaveBeenCalledWith(request);
    expect(manager.state).toBe("running");
  });
});

test("corrections stay on the private message path and observation outcomes remain content-free", async () => {
  const child = new FakeChild(); const {manager,onMessage,diagnostics,timelines}=managerWith([child]);
  const started=manager.start(); child.stdout.write(`${validHello}\n`); await started;
  const requestId="00000000-0000-4000-8000-000000000001";
  child.stdout.write(`${JSON.stringify({protocolVersion:5,type:"correction_observed",identity:{requestId,focusSequence:1,contentSignature:"0123456789abcdef",timestampMs:1},payload:{appId:"com.example.Editor",sessionId:requestId,before:"PRIVATE BEFORE",after:"PRIVATE AFTER",observedAtMs:1}})}\n`);
  expect(onMessage).toHaveBeenCalledOnce(); expect(diagnostics).toEqual([]); expect(timelines).toEqual([]);
  for(const outcome of ["edited_after_acceptance","removed_after_acceptance","observation_unavailable"]){
    child.stderr.write(`timeline:${JSON.stringify({v:1,proc:"helper",monoMs:1,wallMs:1,requestId,focusSequence:1,event:"interaction",attrs:{outcome,sinceShownMs:1}})}\n`);
  }
  expect(timelines).toHaveLength(3); expect(JSON.stringify({diagnostics,timelines})).not.toContain("PRIVATE"); manager.stop();
});

 test("preserves source-change presentation rejection from the native helper", async () => {
  const child = new FakeChild();
  const { manager, diagnostics, timelines } = managerWith([child]);
  const started = manager.start();
  const envelope = {
    v: 1, proc: "helper", requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
    focusSequence: 7, monoMs: 12300, wallMs: 1788540000123,
    event: "present_rejected",
    attrs: { sinceFinalMs: 1, anchorWaitMs: 1, rejection: "source_changed" },
  };
  child.stderr.write(`timeline:${JSON.stringify(envelope)}\n`);
  child.stdout.write(`${validHello}\n`);
  await started;
  expect(timelines).toEqual([envelope]);
  expect(diagnostics).toEqual([]);
  manager.stop();
});

 test.each(["selection_no_value", "selection_unsupported", "selection_unavailable", "selection_invalid_value"])("preserves categorical marker selection failure %s", async (stage) => {
  const child = new FakeChild();
  const { manager, diagnostics } = managerWith([child]);
  const started = manager.start();
  child.stderr.write(`fixture:web_read_${stage}\n`);
  child.stdout.write(`${validHello}\n`);
  await started;
  expect(diagnostics).toEqual([{code: `fixture_web_read_${stage}`}]);
  manager.stop();
});


test("accepts every native presentation rejection without retaining private content", async () => {
  const swift = readFileSync(new URL("../../../native/macos/Sources/AutocompleteHelper/HelperTimelineTracer.swift", import.meta.url), "utf8");
  const cases = swift.split("enum HelperPresentationRejection:")[1]!.split("protocol HelperTimelineTracing")[0]!;
  const reasons = [...cases.matchAll(/case \w+ = "([a-z_]+)"/g)].map(match => match[1]!);
  expect(reasons.length).toBeGreaterThan(20);
  const child = new FakeChild();
  const { manager, diagnostics, timelines } = managerWith([child]);
  const started = manager.start(); child.stdout.write(`${validHello}\n`); await started;
  for (const rejection of reasons) {
    const envelope = {v:1,proc:"helper",monoMs:1,wallMs:1,
      requestId:"da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",focusSequence:7,
      event:"present_rejected",attrs:{sinceFinalMs:0,anchorWaitMs:0,rejection}};
    child.stderr.write(`timeline:${JSON.stringify(envelope)}\n`);
  }
  expect(timelines).toHaveLength(reasons.length);
  expect(diagnostics).toEqual([]);
  manager.stop();
});
