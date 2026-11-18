import { describe, expect, test } from "vitest";

import {
  assignBlindLabels,
  buildMetricRecord,
  intelligenceCases,
  selectArms,
} from "./intelligence-comparison";

describe("intelligence benchmark helpers", () => {
  test("defines a discriminating set of at least twelve cases", () => {
    expect(intelligenceCases.length).toBeGreaterThanOrEqual(12);
    expect(new Set(intelligenceCases.map((entry) => entry.id)).size).toBe(
      intelligenceCases.length,
    );
    for (const entry of intelligenceCases) {
      expect(entry.evaluationFocus.length).toBeGreaterThan(0);
    }
  });

  test("assigns opaque labels without losing or duplicating models", () => {
    const assignments = assignBlindLabels(
      ["model-one", "model-two", "model-three"],
      [0.9, 0.1],
    );
    expect(Object.keys(assignments).sort()).toEqual(["A", "B", "C"]);
    expect(Object.values(assignments).sort()).toEqual([
      "model-one",
      "model-three",
      "model-two",
    ]);
  });

  test("supports a two-candidate blind packet for the Flash Lite comparison", () => {
    const assignments = assignBlindLabels(["qwen", "gemini-lite"], [0.9]);
    expect(Object.keys(assignments).sort()).toEqual(["A", "B"]);
    expect(Object.values(assignments).sort()).toEqual(["gemini-lite", "qwen"]);

    expect(selectArms("lite")).toEqual([
      expect.objectContaining({
        model: "alibaba/qwen3.8-flash",
        provider: "alibaba",
        reasoning: "none",
      }),
      expect.objectContaining({
        model: "google/gemini-3.5-flash-lite",
        provider: "vertex",
        reasoning: "low",
      }),
    ]);
  });

  test("keeps generated text out of the model-attributed metric record", () => {
    const metric = buildMetricRecord({
      model: "model-one",
      provider: "provider-one",
      caseId: "implicit_intent_es",
      repetition: 1,
      output: "full synthetic suggestion",
      firstOutputMs: 100,
      validObjectMs: 125,
      inputTokens: 50,
      outputTokens: 7,
      resolvedModel: "model-one",
      resolvedProvider: "provider-one",
      providerAttemptCount: 1,
    });
    expect(metric).not.toHaveProperty("output");
    expect(JSON.stringify(metric)).not.toContain("full synthetic suggestion");
    expect(metric.outputLength).toBe(25);
  });
});
