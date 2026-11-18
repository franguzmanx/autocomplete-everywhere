import { afterEach, describe, expect, test, vi } from "vitest";

import type { SuggestionRequest } from "@autocompletion/protocol";

import {
  HttpSuggestionTransport,
  parseSuggestionApiUrl,
} from "../src/main/suggestion-transport";

const requestMessage: SuggestionRequest = {
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
    textBefore: "synthetic input",
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

describe("HttpSuggestionTransport", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  test("returns one decoded final completion", async () => {
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async () =>
        new Response(" café 東京", {
          status: 200,
          headers: { "content-type": "text/plain; charset=utf-8" },
        }),
    }) as unknown as {
      complete(request: SuggestionRequest, signal: AbortSignal): Promise<string>;
    };

    await expect(
      transport.complete(requestMessage, new AbortController().signal),
    ).resolves.toBe(" café 東京");
  });

  test("accepts only a canonical HTTPS API origin", () => {
    expect(parseSuggestionApiUrl("https://api.autocompletion.test").origin).toBe(
      "https://api.autocompletion.test",
    );
    for (const invalid of [
      "http://api.autocompletion.test",
      "https://user:pass@api.autocompletion.test",
      "https://api.autocompletion.test/private",
      "https://api.autocompletion.test/?destination=other",
      "https://127.0.0.1",
    ]) {
      expect(() => parseSuggestionApiUrl(invalid)).toThrow();
    }
  });

  test("posts the bounded protocol request with Bearer auth and returns final UTF-8", async () => {
    let submittedUrl = "";
    let submittedAuthorization = "";
    let submittedBody = "";
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async (url, init) => {
        submittedUrl = String(url);
        submittedAuthorization = new Headers(init?.headers).get("authorization") ?? "";
        submittedBody = String(init?.body);
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            controller.enqueue(new TextEncoder().encode(" café"));
            controller.enqueue(new TextEncoder().encode(" 東京"));
            controller.close();
          },
        });
        return new Response(stream, {
          status: 200,
          headers: { "content-type": "text/plain; charset=utf-8" },
        });
      },
    });

    await expect(
      transport.complete(requestMessage, new AbortController().signal),
    ).resolves.toBe(" café 東京");
    expect(submittedUrl).toBe(
      "https://api.autocompletion.test/v1/suggestions",
    );
    expect(submittedAuthorization).toBe("Bearer access-token");
    expect(JSON.parse(submittedBody)).toEqual(requestMessage);
  });

  test("traces token, HTTP headers, and body completion for the request id", async () => {
    const traced: unknown[] = [];
    let now = 100;
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: {
        getAccessToken: async () => {
          now = 108;
          return "access-token";
        },
      },
      request: async () => {
        now = 145;
        return new Response(" continuation", {
          status: 200,
          headers: {
            "content-type": "text/plain",
            "x-autocompletion-request-id": requestMessage.identity.requestId,
            "x-autocompletion-failure-kind": "invalid_output",
            "x-autocompletion-failure-reason": "ai_noobjectgeneratederror",
          },
        });
      },
      monotonicNow: () => now,
      trace: { record: (record) => traced.push(record) },
    });

    await transport.complete(requestMessage, new AbortController().signal);
    expect(traced).toEqual([
      {
        requestId: requestMessage.identity.requestId,
        event: "token_ready",
        attrs: { source: "store", ms: 8 },
      },
      {
        requestId: requestMessage.identity.requestId,
        event: "http_start",
        attrs: { attempt: "initial" },
      },
      {
        requestId: requestMessage.identity.requestId,
        event: "http_headers",
        attrs: { attempt: "initial", status: 200, ttfbMs: 37 },
      },
      {
        requestId: requestMessage.identity.requestId,
        event: "http_end",
        attrs: {
          attempt: "initial",
          status: 200,
          totalMs: 37,
          result: "complete",
        },
      },
    ]);
    expect(JSON.stringify(traced)).not.toContain("continuation");
    expect(JSON.stringify(traced)).not.toContain("synthetic input");
  });

  test.each([
    ["invalid_output", "ai_noobjectgeneratederror", { failureKind: "invalid_output", failureReason: "ai_noobjectgeneratederror" }],
    ["timeout", "timeout", { failureKind: "timeout", failureReason: "timeout" }],
    ["SYNTHETIC_PRIVATE_KIND", "SYNTHETIC_PRIVATE_REASON", {}],
  ])("traces bounded generation failure headers without body content %#", async (kind, reason, expected) => {
    const traced: unknown[] = [];
    let calls = 0;
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      trace: { record: record => traced.push(record) },
      request: async () => {
        calls++;
        return new Response("SYNTHETIC_PRIVATE_BODY", { status: 502, headers: {
          "x-autocompletion-failure-kind": kind as string,
          "x-autocompletion-failure-reason": reason as string,
        } });
      },
    });
    await expect(transport.complete(requestMessage, new AbortController().signal)).rejects.toMatchObject({ code: "server" });
    expect(calls).toBe(1);
    expect(traced).toContainEqual(expect.objectContaining({ event: "http_headers", attrs: expect.objectContaining(expected) }));
    expect(JSON.stringify(traced)).not.toContain("SYNTHETIC_PRIVATE");
  });

  test("refreshes once after 401 and never retries a second unauthorized response", async () => {
    const tokenCalls: boolean[] = [];
    let requests = 0;
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: {
        getAccessToken: async (forceRefresh = false) => {
          tokenCalls.push(forceRefresh);
          return forceRefresh ? "renewed" : "stale";
        },
      },
      request: async () => {
        requests += 1;
        return new Response(null, { status: 401 });
      },
    });

    await expect(
      transport.complete(requestMessage, new AbortController().signal),
    ).rejects.toMatchObject({ code: "unauthorized", retryable: false });
    expect(tokenCalls).toEqual([false, true]);
    expect(requests).toBe(2);
  });

  test("fails closed on an oversized response without returning its content", async () => {
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async () =>
        new Response("x".repeat(2_001), {
          status: 200,
          headers: { "content-type": "text/plain" },
        }),
    });

    await expect(
      transport.complete(requestMessage, new AbortController().signal),
    ).rejects.toMatchObject({ code: "server", retryable: false });
  });

  test("propagates caller cancellation to fetch", async () => {
    const controller = new AbortController();
    const traced: unknown[] = [];
    let received: AbortSignal | undefined;
    let markStarted!: () => void;
    const started = new Promise<void>((resolve) => {
      markStarted = resolve;
    });
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async (_url, init) => {
        received = init?.signal ?? undefined;
        markStarted();
        return new Promise<Response>((_resolve, reject) => {
          received?.addEventListener("abort", () => reject(received?.reason));
        });
      },
      trace: { record: (record) => traced.push(record) },
    });

    const reading = transport.complete(requestMessage, controller.signal);
    await started;
    controller.abort("supersede");

    await expect(reading).rejects.toBeDefined();
    expect(received?.aborted).toBe(true);
    expect(traced).toContainEqual({
      requestId: requestMessage.identity.requestId,
      event: "aborted",
      attrs: { reason: "supersede", stage: "http" },
    });
  });

  test("attributes cancellation during token loading to the token stage", async () => {
    const controller = new AbortController();
    const traced: unknown[] = [];
    let releaseToken!: () => void;
    const tokenPending = new Promise<void>((resolve) => {
      releaseToken = resolve;
    });
    let tokenStarted!: () => void;
    const started = new Promise<void>((resolve) => {
      tokenStarted = resolve;
    });
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: {
        getAccessToken: async () => {
          tokenStarted();
          await tokenPending;
          return "access-token";
        },
      },
      request: async (_url, init) => {
        throw init?.signal?.reason ?? new Error("expected_abort");
      },
      trace: { record: (record) => traced.push(record) },
    });

    const reading = transport.complete(requestMessage, controller.signal);
    await started;
    controller.abort("cancel");
    releaseToken();

    await expect(reading).rejects.toBeDefined();
    expect(traced).toContainEqual({
      requestId: requestMessage.identity.requestId,
      event: "aborted",
      attrs: { reason: "cancel", stage: "token" },
    });
  });

  test("aborts a stalled request at the desktop deadline and reports timeout", async () => {
    vi.useFakeTimers();
    let received: AbortSignal | undefined;
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async (_url, init) => {
        received = init?.signal ?? undefined;
        return new Promise<Response>((_resolve, reject) => {
          received?.addEventListener("abort", () => reject(received?.reason));
        });
      },
    });

    const reading = transport.complete(
      requestMessage,
      new AbortController().signal,
    );
    const rejection = expect(reading).rejects.toMatchObject({
      code: "timeout",
      retryable: true,
    });
    await vi.advanceTimersByTimeAsync(9_999);
    expect(received?.aborted).toBe(false);
    await vi.advanceTimersByTimeAsync(1);

    await rejection;
    expect(received?.aborted).toBe(true);
  });

  test("rejects non-text response bodies", async () => {
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async () =>
        new Response("{}", {
          headers: { "content-type": "application/json" },
        }),
    });

    await expect(
      transport.complete(requestMessage, new AbortController().signal),
    ).rejects.toMatchObject({ code: "server", retryable: false });
  });
});

import { defaultTransformSettings } from '@autocompletion/protocol';
const transformInput = { text: 'Synthetic input', transform: defaultTransformSettings().transforms[0]!, singleLine: false };
test('transform transport refreshes an expired token and validates the full result', async () => {
  const refreshes: boolean[] = [];
  let calls = 0;
  const transport = new HttpSuggestionTransport({ apiUrl: 'https://api.autocompletion.test', tokenProvider: { getAccessToken: async (refresh = false) => { refreshes.push(refresh); return 'token'; } }, request: (async (url: URL) => {
    expect(url.pathname).toBe('/v1/transforms');
    calls++;
    return calls === 1 ? new Response(null, { status: 401 }) : Response.json({ text: 'Complete rewrite' });
  }) as typeof fetch });
  expect(await transport.transform(transformInput, new AbortController().signal)).toBe('Complete rewrite');
  expect(refreshes).toEqual([false, true]);
});
test('transform transport rejects oversized responses without passing partial text', async () => {
  const transport = new HttpSuggestionTransport({ apiUrl: 'https://api.autocompletion.test', tokenProvider: { getAccessToken: async () => 'token' }, request: (async () => Response.json({ text: 'x'.repeat(65000) })) as typeof fetch });
  await expect(transport.transform(transformInput, new AbortController().signal)).rejects.toThrow('too large');
});
test('cancelled transform never starts a fetch after slow token acquisition', async () => {
  const controller = new AbortController();
  let calls = 0;
  const transport = new HttpSuggestionTransport({ apiUrl: 'https://api.autocompletion.test', tokenProvider: { getAccessToken: async () => { controller.abort(); return 'token'; } }, request: (async () => { calls++; return Response.json({ text: 'x' }); }) as typeof fetch });
  await expect(transport.transform(transformInput, controller.signal)).rejects.toThrow();
  expect(calls).toBe(0);
});

describe("outcome transport",()=>{
  test("records content-free outcome batches through the product API", async () => {
    let submittedUrl = "";
    let submittedMethod = "";
    let submittedBody = "";
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async (url, init) => {
        submittedUrl = String(url);
        submittedMethod = init?.method ?? "";
        submittedBody = String(init?.body);
        return new Response(null, { status: 204 });
      },
    });

    await transport.recordSuggestionOutcomes([
      {
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "shown",
        requestToVisibleMs: 480,
        suggestionCharacterCount: 21,
      },
    ], new AbortController().signal);

    expect(submittedUrl).toBe(
      "https://api.autocompletion.test/v1/suggestions/outcomes",
    );
    expect(submittedMethod).toBe("POST");
    expect(JSON.parse(submittedBody)).toEqual({
      events: [
        {
          requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
          appId: "com.apple.Notes",
          surface: "text_editor",
          outcome: "shown",
          requestToVisibleMs: 480,
          suggestionCharacterCount: 21,
        },
      ],
    });
  });

  test("rejects a failed outcome upload without retrying past one refresh", async () => {
    let requests = 0;
    const transport = new HttpSuggestionTransport({
      apiUrl: "https://api.autocompletion.test",
      tokenProvider: { getAccessToken: async () => "access-token" },
      request: async () => {
        requests += 1;
        return new Response(null, { status: 503 });
      },
    });

    await expect(
      transport.recordSuggestionOutcomes([
        {
          requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
          appId: "com.apple.Notes",
          surface: "text_editor",
          outcome: "requested",
        },
      ], new AbortController().signal),
    ).rejects.toThrow("Suggestion outcomes could not be recorded");
    expect(requests).toBe(1);
  });

});
