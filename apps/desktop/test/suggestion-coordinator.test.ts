import { describe, expect, test, vi } from "vitest";

import type {
  ProtocolMessage,
  SuggestionRequest,
} from "@autocompletion/protocol";

import {
  SuggestionCoordinator,
  SuggestionRequestFailure,
} from "../src/main/suggestion-coordinator";

const firstRequest: SuggestionRequest = {
  protocolVersion: 5,
  type: "suggestion_request",
  identity: {
    requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
    focusSequence: 7,
    contentSignature: "0123456789abcdef0123456789abcdef",
    timestampMs: 1_788_000_000_000,
  },
  payload: {
    appId: "com.apple.Notes",
    surface: "text_editor",
    textBefore: "Hola Axel,",
    textAfter: "",
    selectedText: "",
    explicit: false,
    artifacts: [],
    fieldContext: {
      shape: "multiline",
      sources: [], relatedFields: [],
    },
  },
};

const secondRequest: SuggestionRequest = {
  ...firstRequest,
  identity: {
    ...firstRequest.identity,
    requestId: "5a4673ea-8f23-45a9-a293-54494656987d",
    focusSequence: 8,
    contentSignature: "abcdef0123456789abcdef0123456789",
  },
  payload: { ...firstRequest.payload, textBefore: "Hola Ana," },
};

function deferred(): { promise: Promise<void>; resolve(): void } {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

async function waitUntil(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("condition_not_reached");
}

describe("SuggestionCoordinator", () => {
  test("cancels a pending alternative by its own identity and drops a late response", async () => {
    const release = deferred();
    const sent: ProtocolMessage[] = [];
    const traces: unknown[] = [];
    let pendingSignal: AbortSignal | undefined;
    const alternative = {...firstRequest, identity: {...firstRequest.identity, requestId: secondRequest.identity.requestId},
      payload: {...firstRequest.payload, explicit:true, alternativeTo:[" SYNTHETIC_PREVIOUS_GHOST"]}};
    const coordinator = new SuggestionCoordinator({
      transport: { complete: async (request, signal) => {
        if (!request.payload.alternativeTo) return " SYNTHETIC_PREVIOUS_GHOST";
        expect(request.payload.alternativeTo).toEqual(alternative.payload.alternativeTo);
        pendingSignal = signal;
        await release.promise;
        return " late alternative";
      } },
      send: message => sent.push(message),
      trace: {record: value => traces.push(value)},
    });
    coordinator.handle(firstRequest);
    await waitUntil(() => sent.length === 1);
    coordinator.handle(alternative);
    expect(pendingSignal?.aborted).toBe(false);
    coordinator.handle({protocolVersion:5, type:"cancel_request", identity:alternative.identity, payload:{reason:"dismissed"}});
    expect(pendingSignal?.aborted).toBe(true);
    release.resolve();
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(sent).toEqual([{protocolVersion:5,type:"suggestion_final",identity:firstRequest.identity,payload:{text:" SYNTHETIC_PREVIOUS_GHOST"}}]);
    expect(JSON.stringify(traces)).not.toContain("SYNTHETIC_PREVIOUS_GHOST");
  });

  test.each([false, true])("traces request invocation mode (%s) and response without content", async (explicit) => {
    const traced: unknown[] = [];
    const coordinator = new SuggestionCoordinator({
      transport: {
        async complete() {
          return " private continuation";
        },
      },
      send: () => {},
      trace: { record: (record) => traced.push(record) },
    });

    coordinator.handle({
      ...firstRequest,
      payload: {
        ...firstRequest.payload,
        explicit,
        artifacts: [{ id: "recent-1", kind: "recent_writing", text: "Private recent writing", capturedAtMs: 1 }],
      },
    });
    await waitUntil(() => traced.length === 2);

    expect(traced).toEqual([
      {
        requestId: firstRequest.identity.requestId,
        event: "request_received",
        attrs: { focusSequence: firstRequest.identity.focusSequence, explicit, artifactCount: 1, recentWritingCount: 1 },
      },
      {
        requestId: firstRequest.identity.requestId,
        event: "helper_write",
        attrs: { result: "text" },
      },
    ]);
    expect(JSON.stringify(traced)).not.toContain("private continuation");
    expect(JSON.stringify(traced)).not.toContain("Private recent writing");
    expect(JSON.stringify(traced)).not.toContain("Hola Axel");
  });

  test("aborts the old request and drops its late completion", async () => {
    const releaseFirst = deferred();
    let firstSignal: AbortSignal | null = null;
    let firstRequestStarted = false;
    const firstRequestWasAborted = (): boolean => firstSignal?.aborted ?? false;
    const firstAbortReason = (): unknown => firstSignal?.reason;
    const sent: ProtocolMessage[] = [];
    const coordinator = new SuggestionCoordinator({
      transport: {
        async complete(request, signal) {
          if (request.identity.requestId === firstRequest.identity.requestId) {
            firstSignal = signal;
            firstRequestStarted = true;
            await releaseFirst.promise;
            return " uno tarde";
          }
          return " dos";
        },
      },
      send: (message) => sent.push(message),
    });

    coordinator.handle(firstRequest);
    await waitUntil(() => firstRequestStarted);
    coordinator.handle(secondRequest);
    await waitUntil(() =>
      sent.some(
        (message) =>
          message.type === "suggestion_final" &&
          message.identity.requestId === secondRequest.identity.requestId,
      ),
    );
    releaseFirst.resolve();
    await waitUntil(firstRequestWasAborted);
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(firstRequestWasAborted()).toBe(true);
    expect(firstAbortReason()).toBe("supersede");
    expect(JSON.stringify(sent)).not.toContain("uno tarde");
  });

  test("drops a late completion after an explicit cancellation", async () => {
    const release = deferred();
    let requestStarted = false;
    let receivedSignal: AbortSignal | undefined;
    const sent: ProtocolMessage[] = [];
    const coordinator = new SuggestionCoordinator({
      transport: {
        async complete(_request, signal) {
          receivedSignal = signal;
          requestStarted = true;
          await release.promise;
          return " stale";
        },
      },
      send: (message) => sent.push(message),
    });

    coordinator.handle(firstRequest);
    await waitUntil(() => requestStarted);
    coordinator.handle({
      protocolVersion: 5,
      type: "cancel_request",
      identity: firstRequest.identity,
      payload: { reason: "focus_changed" },
    });
    release.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(sent).toHaveLength(0);
    expect(receivedSignal?.reason).toBe("cancel");
  });

  test("emits exactly one final completion", async () => {
    const sent: ProtocolMessage[] = [];
    const coordinator = new SuggestionCoordinator({
      transport: {
        async complete() {
          return " te mando";
        },
      },
      send: (message) => sent.push(message),
    });

    coordinator.handle(firstRequest);
    await waitUntil(() => sent.some((message) => message.type === "suggestion_final"));

    expect(sent.map((message) => message.type)).toEqual(["suggestion_final"]);
    expect(sent[0]).toMatchObject({ payload: { text: " te mando" } });
  });

  test("returns only a content-free failure", async () => {
    const sent: ProtocolMessage[] = [];
    const coordinator = new SuggestionCoordinator({
      transport: {
        async complete() {
          throw new SuggestionRequestFailure("network", true);
        },
      },
      send: (message) => sent.push(message),
    });

    coordinator.handle(firstRequest);
    await waitUntil(() => sent.length === 1);

    expect(sent).toEqual([
      {
        protocolVersion: 5,
        type: "request_failed",
        identity: firstRequest.identity,
        payload: { code: "network", retryable: true },
      },
    ]);
    expect(JSON.stringify(sent)).not.toContain("Hola Axel");
  });

  test("classifies coordinator finals as text or silence without request content", async () => {
    const textResults: string[] = [];
    const textCoordinator = new SuggestionCoordinator({
      transport: {
        async complete() {
          return " continuation";
        },
      },
      send: () => {},
      onFinalResult: (result) => textResults.push(result),
    });
    textCoordinator.handle(firstRequest);
    await waitUntil(() => textResults.length === 1);

    const silenceResults: string[] = [];
    const silenceCoordinator = new SuggestionCoordinator({
      transport: {
        async complete() {
          return "";
        },
      },
      send: () => {},
      onFinalResult: (result) => silenceResults.push(result),
    });
    silenceCoordinator.handle(firstRequest);
    await waitUntil(() => silenceResults.length === 1);

    expect(textResults).toEqual(["text"]);
    expect(silenceResults).toEqual(["silence"]);
    expect(JSON.stringify([textResults, silenceResults])).not.toContain("Hola Axel");
  });

});


test("coalesces rapid automatic edits before issuing another provider request", async () => {
  vi.useFakeTimers();
  try {
    const complete = vi.fn(async (_request: SuggestionRequest, _signal: AbortSignal) => " listo");
    const coordinator = new SuggestionCoordinator({transport: {complete}, send: () => {}});
    coordinator.handle(firstRequest);
    await vi.advanceTimersByTimeAsync(50);
    for (let i = 0; i < 8; i++) {
      coordinator.handle({...firstRequest, identity: {...firstRequest.identity, requestId: `edit-${i}`},
        payload: {...firstRequest.payload, textBefore: `Draft ${i}`}});
      await vi.advanceTimersByTimeAsync(50);
    }
    expect(complete).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(250);
    expect(complete).toHaveBeenCalledTimes(2);
    expect(complete.mock.calls[1]?.[0].payload.textBefore).toBe("Draft 7");
    coordinator.stop();
  } finally { vi.useRealTimers(); }
});

test("cancelled queued edits never reach the provider", async () => {
  vi.useFakeTimers();
  try {
    const complete = vi.fn(async (_request: SuggestionRequest, _signal: AbortSignal) => " listo");
    const coordinator = new SuggestionCoordinator({transport: {complete}, send: () => {}});
    coordinator.handle(firstRequest);
    await vi.advanceTimersByTimeAsync(50);
    coordinator.handle(firstRequest);
    coordinator.stop();
    await vi.advanceTimersByTimeAsync(1000);
    expect(complete).toHaveBeenCalledTimes(1);
  } finally { vi.useRealTimers(); }
});


test("manual invocation bypasses edit coalescing without releasing stale work", async () => {
  vi.useFakeTimers();
  try {
    const complete = vi.fn(async (_request: SuggestionRequest, _signal: AbortSignal) => " listo");
    const coordinator = new SuggestionCoordinator({transport: {complete}, send: () => {}});
    coordinator.handle(firstRequest);
    await vi.advanceTimersByTimeAsync(50);
    coordinator.handle(firstRequest);
    coordinator.handle({...firstRequest, payload: {...firstRequest.payload, explicit: true}});
    expect(complete).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1000);
    expect(complete).toHaveBeenCalledTimes(2);
    coordinator.stop();
  } finally { vi.useRealTimers(); }
});
