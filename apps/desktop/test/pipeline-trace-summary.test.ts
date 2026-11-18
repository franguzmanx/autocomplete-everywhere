import { describe, expect, test } from "vitest";

import { summarizePipelineTrace } from "../src/main/pipeline-trace-summary";

describe("summarizePipelineTrace", () => {
  test("excludes orphaned outcomes from the selected request cohort", () => {
    const events = [
      event("helper", "request_written", 10, "old"),
      event("helper", "presented", 110, "old"),
      event("desktop", "http_headers", 105, "old", { ttfbMs: 95 }),
      event("desktop", "helper_write", 108, "old", { result: "text" }),
      event("desktop", "aborted", 115, "old", { reason: "supersede" }),
      event("helper", "present_rejected", 116, "old", { rejection: "anchor_unavailable" }),
      event("helper", "request_written", 120, "current"),
      event("helper", "presented", 150, "current"),
      event("helper", "presented", 160, "missing_start"),
    ];
    expect(summarizePipelineTrace(events, { startWallMs: 100, endWallMs: 200 })).toEqual({
      requests: 1, presented: 1, visibleRate: 1,
      requestToVisibleMs: { p50: 30, p95: 30 },
      httpTtfbMs: { p50: null, p95: null },
      helperWrites: {}, aborts: {}, presentationRejections: {},
    });
    expect(summarizePipelineTrace(events, { startWallMs: 151 })).toMatchObject({
      requests: 0, presented: 0, visibleRate: 0,
    });
  });

  test("reports request-to-visible percentiles without excluding failed requests", () => {
    const events = [
      event("helper", "request_written", 1_000, "a"),
      event("desktop", "http_headers", 1_120, "a", { ttfbMs: 120 }),
      event("helper", "presented", 1_200, "a"),
      event("helper", "request_written", 2_000, "b"),
      event("desktop", "helper_write", 2_700, "b", { result: "failed" }),
      event("helper", "request_written", 3_000, "c"),
      event("desktop", "http_headers", 3_380, "c", { ttfbMs: 380 }),
      event("helper", "presented", 3_400, "c"),
      event("desktop", "aborted", 3_500, "c", { reason: "supersede" }),
      event("helper", "present_rejected", 4_000, "c", {
        rejection: "stale_content",
      }),
    ];

    expect(summarizePipelineTrace(events)).toEqual({
      requests: 3,
      presented: 2,
      visibleRate: 2 / 3,
      requestToVisibleMs: { p50: 200, p95: 400 },
      httpTtfbMs: { p50: 120, p95: 380 },
      helperWrites: { failed: 1 },
      aborts: { supersede: 1 },
      presentationRejections: { stale_content: 1 },
    });
  });

  test("uses the first presentation for a request and supports a wall-clock window", () => {
    const events = [
      event("helper", "request_written", 1_000, "old", {}, 10),
      event("helper", "presented", 1_100, "old", {}, 11),
      event("helper", "request_written", 2_000, "current", {}, 20),
      event("helper", "presented", 2_500, "current", {}, 21),
      event("helper", "presented", 2_700, "current", {}, 22),
    ];

    expect(summarizePipelineTrace(events, { startWallMs: 20 })).toMatchObject({
      requests: 1,
      presented: 1,
      requestToVisibleMs: { p50: 500, p95: 500 },
    });
  });
});

function event(
  proc: "helper" | "desktop",
  name: string,
  monoMs: number,
  requestId: string,
  attrs: Record<string, string | number> = {},
  wallMs = monoMs,
) {
  return { v: 1, proc, event: name, monoMs, wallMs, requestId, attrs };
}
