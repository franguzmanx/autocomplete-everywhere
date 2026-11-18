import { describe, expect, test } from "vitest";

import type { ProtocolMessage } from "@autocompletion/protocol";

import {
  SuggestionActivity,
  type SuggestionOutcomeEvent,
} from "../src/main/suggestion-activity";
import type { SuggestionActivitySummary } from "../src/shared/contracts";

const identity = {
  requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
  focusSequence: 7,
  contentSignature: "0123456789abcdef0123456789abcdef",
  timestampMs: 1_000,
};

const request: Extract<ProtocolMessage, {type:"suggestion_request"}> = {
  protocolVersion: 5,
  type: "suggestion_request",
  identity,
  payload: {
    appId: "com.apple.Notes",
    surface: "text_editor",
    textBefore: "private draft",
    textAfter: "",
    selectedText: "",
    explicit: false,
    artifacts: [],
    fieldContext: { shape: "multiline", sources: [], relatedFields: [] },
  },
};

function harness(start = 1_000) {
  let now = start;
  const events: SuggestionOutcomeEvent[] = [];
  const summaries: SuggestionActivitySummary[] = [];
  const activity = new SuggestionActivity({
    now: () => now,
    onEvent: (event) => events.push(event),
    onChange: (summary) => summaries.push(summary),
  });
  return {
    activity,
    events,
    summaries,
    advance(ms: number) {
      now += ms;
    },
  };
}

describe("SuggestionActivity", () => {
  test("follows one request from capture to acceptance without content", () => {
    const { activity, events, advance } = harness();

    activity.observe(request);
    advance(420);
    activity.observe({
      protocolVersion: 5,
      type: "suggestion_final",
      identity,
      payload: { text: " te mando el resumen." },
    });
    advance(60);
    activity.observe({
      protocolVersion: 5,
      type: "interaction",
      identity,
      payload: { outcome: "shown", acceptedCharacters: 0 },
    });
    advance(900);
    activity.observe({
      protocolVersion: 5,
      type: "interaction",
      identity,
      payload: { outcome: "accepted_full", acceptedCharacters: 21 },
    });

    expect(events).toEqual([
      {
        requestId: identity.requestId,
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "requested",
      },
      {
        requestId: identity.requestId,
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "generated",
        requestToFinalMs: 420,
        suggestionCharacterCount: 21,
      },
      {
        requestId: identity.requestId,
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "shown",
        requestToFinalMs: 420,
        requestToVisibleMs: 480,
        suggestionCharacterCount: 21,
      },
      {
        requestId: identity.requestId,
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "accepted_full",
        suggestionCharacterCount: 21,
        acceptedCharacterCount: 21,
      },
    ]);
    expect(JSON.stringify(events)).not.toContain("private draft");
    expect(JSON.stringify(events)).not.toContain("te mando");

    const summary = activity.summary();
    expect(summary).toMatchObject({
      requested: 1,
      generated: 1,
      shown: 1,
      accepted: 1,
      acceptedCharacters: 21,
      lastOutcome: "accepted_full",
      requestToVisibleMs: { p50: 480, p95: 480, samples: 1 },
      requestToFinalMs: { p50: 420, p95: 420, samples: 1 },
    });
  });

  test("classifies silence, failure, and cancellation as separate content-free outcomes", () => {
    const { activity, events } = harness();
    const second = {
      ...identity,
      requestId: "5a4673ea-8f23-45a9-a293-54494656987d",
    };
    const third = {
      ...identity,
      requestId: "7d0d9d4c-0a4c-4d1f-8f8d-2f1e7c2f9a11",
    };

    activity.observe(request);
    activity.observe({
      protocolVersion: 5,
      type: "suggestion_final",
      identity,
      payload: { silenceReason: "not_useful" },
    });
    activity.observe({ ...request, identity: second });
    activity.observe({
      protocolVersion: 5,
      type: "request_failed",
      identity: second,
      payload: { code: "timeout", retryable: true },
    });
    activity.observe({ ...request, identity: third });
    activity.observe({
      protocolVersion: 5,
      type: "cancel_request",
      identity: third,
      payload: { reason: "content_changed" },
    });

    expect(events.map((event) => [event.outcome, event.errorClass])).toEqual([
      ["requested", undefined],
      ["suppressed", undefined],
      ["requested", undefined],
      ["failed", "timeout"],
      ["requested", undefined],
      ["cancelled", "content_changed"],
    ]);
    expect(activity.summary()).toMatchObject({
      requested: 3,
      suppressed: 1,
      failed: 1,
      cancelled: 1,
      shown: 0,
    });
  });

  test("ignores responses and interactions for requests it never observed", () => {
    const { activity, events, summaries } = harness();

    activity.observe({
      protocolVersion: 5,
      type: "interaction",
      identity,
      payload: { outcome: "shown", acceptedCharacters: 0 },
    });
    activity.observe({
      protocolVersion: 5,
      type: "suggestion_final",
      identity,
      payload: { text: "late" },
    });

    expect(events).toEqual([]);
    expect(summaries).toEqual([]);
  });

  test("drops implausible latencies instead of recording clock skew", () => {
    const { activity, events, advance } = harness();

    activity.observe(request);
    advance(-5);
    activity.observe({
      protocolVersion: 5,
      type: "suggestion_final",
      identity,
      payload: { text: "x" },
    });

    expect(events[1]).toEqual({
      requestId: identity.requestId,
      appId: "com.apple.Notes",
      surface: "text_editor",
      outcome: "generated",
      suggestionCharacterCount: 1,
    });
    expect(activity.summary().requestToFinalMs).toEqual({
      p50: null,
      p95: null,
      samples: 0,
    });
  });

  test("bounds remembered requests and computes nearest-rank percentiles", () => {
    const { activity, advance } = harness();

    for (let index = 0; index < 100; index += 1) {
      const current = {
        ...identity,
        requestId: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
        timestampMs: 1_000 + index * 10_000,
      };
      activity.observe({ ...request, identity: current });
      advance(10_000);
      activity.observe({
        protocolVersion: 5,
        type: "suggestion_final",
        identity: current,
        payload: { silenceReason: "not_useful" },
      });
    }

    const summary = activity.summary();
    expect(summary.requested).toBe(100);
    expect(summary.suppressed).toBe(100);
    expect(summary.requestToFinalMs.samples).toBe(100);
    expect(summary.requestToFinalMs.p50).toBeGreaterThan(0);
    expect(activity.rememberedRequestCount).toBeLessThanOrEqual(64);
  });

  test("notifies a content-free summary after every change", () => {
    const { activity, summaries } = harness();

    activity.observe(request);

    expect(summaries).toHaveLength(1);
    expect(summaries[0]).toMatchObject({ requested: 1, lastOutcome: "requested" });
    expect(JSON.stringify(summaries)).not.toContain("private draft");
    expect(JSON.stringify(summaries)).not.toContain("com.apple.Notes");
  });
});

test("counts each partial acceptance increment once and excludes private learning outcomes", () => {
  const { activity, events } = harness();
  activity.observe(request);
  for (const acceptedCharacters of [9, 8]) {
    activity.observe({protocolVersion:5,type:"interaction",identity,payload:{outcome:"accepted_partial",acceptedCharacters}});
  }
  activity.observe({protocolVersion:5,type:"interaction",identity,payload:{outcome:"edited_after_acceptance",acceptedCharacters:17}});
  expect(activity.summary().acceptedCharacters).toBe(17);
  expect(events.filter(event=>event.outcome==="accepted_partial").map(event=>event.acceptedCharacterCount)).toEqual([9,8]);
  expect(events).toHaveLength(3);
});

test("session invalidation forgets old requests so late interactions cannot cross accounts", () => {
  const {activity, events} = harness();
  activity.observe(request);
  activity.clearRequests();
  activity.observe({protocolVersion: 5, type: "interaction", identity, payload: {outcome: "shown", acceptedCharacters: 0}});
  activity.observe({protocolVersion: 5, type: "suggestion_final", identity, payload: {text: "private"}});
  expect(events).toHaveLength(1);
  expect(activity.rememberedRequestCount).toBe(0);
});
