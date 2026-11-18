import { describe, expect, test } from "vitest";

import { RuntimeDiagnostics } from "../src/main/runtime-diagnostics";
import { emptySuggestionActivity } from "../src/shared/contracts";

describe("RuntimeDiagnostics", () => {
  test("persists only content-free pipeline state", async () => {
    let written = "";
    let now = 1_788_470_000_000;
    const diagnostics = new RuntimeDiagnostics("ignored", async (_path, data) => {
      written = data;
    }, () => now++);

    diagnostics.configuration(false, ["onboarding_incomplete"]);
    diagnostics.permission("granted", "granted");
    diagnostics.pipeline("capture_observed");
    diagnostics.request("observed");
    diagnostics.request("cancelled", "content_changed");
    diagnostics.pipeline("response_final");
    diagnostics.pipeline("request_failed", "unauthorized");
    diagnostics.interaction("shown");
    diagnostics.activity({
      ...emptySuggestionActivity("2026-09-03T00:00:00.000Z"),
      requested: 3,
      shown: 1,
      requestToVisibleMs: { p50: 480, p95: 900, samples: 1 },
    });
    await diagnostics.flush();

    expect(JSON.parse(written)).toMatchObject({
      version: 2,
      configuration: {
        enabled: false,
        reasons: ["onboarding_incomplete"],
      },
      permissions: {
        accessibility: "granted",
        inputMonitoring: "granted",
      },
      request: { state: "cancelled", detail: "content_changed" },
      pipeline: { stage: "interaction", detail: "shown" },
      recentPipeline: [
        { sequence: 0, timestampMs: 1_788_470_000_000, stage: "starting" },
        { sequence: 1, timestampMs: 1_788_470_000_003, stage: "capture_observed" },
        { sequence: 2, timestampMs: 1_788_470_000_006, stage: "response_final" },
        {
          sequence: 3,
          timestampMs: 1_788_470_000_007,
          stage: "request_failed",
          detail: "unauthorized",
        },
        {sequence:4,timestampMs:1_788_470_000_008,stage:"interaction",detail:"shown"},
      ],
    });
    expect(written).not.toContain("textBeforeCursor");
    expect(written).not.toContain("suggestion");
    expect(written).not.toContain("clipboard");
  });

  test("retains a complete high-detail request trace", async () => {
    let written = "";
    const diagnostics = new RuntimeDiagnostics("ignored", async (_path, data) => {
      written = data;
    });

    for (let index = 0; index < 100; index += 1) {
      diagnostics.helperDiagnostic(`trace_${index}`);
    }
    await diagnostics.flush();

    const snapshot = JSON.parse(written);
    expect(snapshot.recentPipeline).toHaveLength(101);
    expect(snapshot.recentPipeline[0]).toMatchObject({
      sequence: 0,
      stage: "starting",
    });
    expect(snapshot.recentPipeline.at(-1)).toMatchObject({
      sequence: 100,
      stage: "helper_diagnostic",
      detail: "trace_99",
    });
  });
});

 test("records manual request routing without field or application contents", async () => {
  let written = "";
  const diagnostics = new RuntimeDiagnostics("ignored", async (_path, data) => { written = data; });
  diagnostics.pipeline("manual_request_invoked");
  diagnostics.pipeline("manual_request_blocked", "disabled");
  diagnostics.pipeline("manual_request_sent");
  await diagnostics.flush();
  expect(JSON.parse(written).recentPipeline.slice(1)).toMatchObject([
    {stage:"manual_request_invoked"}, {stage:"manual_request_blocked",detail:"disabled"}, {stage:"manual_request_sent"},
  ]);
 });

 test("preserves the latest manual route after noisy capture diagnostics", async () => {
  let written = "";
  const diagnostics = new RuntimeDiagnostics("ignored", async (_path, data) => { written = data; });
  diagnostics.pipeline("manual_request_invoked");
  diagnostics.pipeline("manual_request_sent");
  for (let i = 0; i < 300; i++) diagnostics.helperDiagnostic("fixture_change_source_content");
  await diagnostics.flush();
  const snapshot = JSON.parse(written);
  expect(snapshot.recentPipeline).toHaveLength(256);
  expect(snapshot.lastManualRequest).toMatchObject({stage:"manual_request_sent",sequence:2});
 });
