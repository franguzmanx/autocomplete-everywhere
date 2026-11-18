import { describe, expect, test } from "vitest";

import type {
  ProtocolMessage,
  SuggestionRequest,
} from "@autocompletion/protocol";

import { createSuggestionBootstrap } from "../src/main/suggestion-bootstrap";

const request: SuggestionRequest = {
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
    textBefore: "draft",
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

async function waitUntil(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("condition_not_reached");
}

describe("suggestion bootstrap", () => {
  test("does not create a coordinator outside explicit fixture mode", () => {
    const sent: ProtocolMessage[] = [];

    expect(
      createSuggestionBootstrap({
        environment: {},
        send: (message) => sent.push(message),
      }),
    ).toBeNull();
    expect(sent).toEqual([]);
  });

  test("routes helper requests through the fixture coordinator and sends responses", async () => {
    const sent: ProtocolMessage[] = [];
    const sourceDecisions: unknown[] = [];
    const finalResults: string[] = [];
    const coordinator = createSuggestionBootstrap({
      environment: { AUTOCOMPLETION_VISUAL_FIXTURE: "1" },
      send: (message) => sent.push(message),
      onSourceDecision: (decision) => sourceDecisions.push(decision),
      onFinalResult: (result) => finalResults.push(result),
    });
    if (!coordinator) throw new Error("fixture_coordinator_unavailable");

    coordinator.handle(request);
    await waitUntil(() =>
      sent.some((message) => message.type === "suggestion_final"),
    );

    expect(sent.map((message) => message.type)).toEqual(["suggestion_final"]);
    expect(sent[0]).toMatchObject({
      identity: request.identity,
      payload: {
        text: "En una interfaz confiable, la sugerencia permanece junto al cursor mientras escribís, se oculta ante una geometría dudosa y reaparece únicamente cuando la posición vuelve a ser estable.",
      },
    });
    expect(sourceDecisions).toEqual([{ outcome: "text", reason: "default" }]);
    expect(finalResults).toEqual(["text"]);
  });

  test("forwards helper-authored context artifacts unchanged", async () => {
    const sent: ProtocolMessage[] = [];
    let received: SuggestionRequest | undefined;
    const remoteSource = {
      async complete(enrichedRequest: SuggestionRequest) {
        received = enrichedRequest;
        return "respuesta contextual";
      },
    };
    const coordinator = createSuggestionBootstrap({
      environment: {},
      remoteSource,
      send: (message) => sent.push(message),
    });
    if (!coordinator) throw new Error("coordinator_unavailable");

    coordinator.handle({
      ...request,
      payload: {
        ...request.payload,
        textBefore: "",
        artifacts: [
          {
            id: "clipboard-current",
            kind: "clipboard",
            text: "Texto preparado para transportar 🚀",
            capturedAtMs: 1_788_530_537_021,
          },
        ],
      },
    });
    await waitUntil(() =>
      sent.some((message) => message.type === "suggestion_final"),
    );

    expect(sent).toMatchObject([
      {
        type: "suggestion_final",
        payload: { text: "respuesta contextual" },
      },
    ]);
    expect(received?.payload.artifacts).toEqual([
      {
        id: "clipboard-current",
        kind: "clipboard",
        text: "Texto preparado para transportar 🚀",
        capturedAtMs: 1_788_530_537_021,
      },
    ]);
  });

  test("stops in-flight fixture work during shutdown", async () => {
    const sent: ProtocolMessage[] = [];
    const coordinator = createSuggestionBootstrap({
      environment: { AUTOCOMPLETION_VISUAL_FIXTURE: "1" },
      send: (message) => sent.push(message),
    });
    if (!coordinator) throw new Error("fixture_coordinator_unavailable");

    coordinator.handle(request);
    coordinator.stop();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(sent).toEqual([]);
  });

  test("uses the remote source during normal execution", async () => {
    const sent: ProtocolMessage[] = [];
    const traced: unknown[] = [];
    const remoteSource = {
      async complete() {
        return " continuación real";
      },
    };
    const coordinator = createSuggestionBootstrap({
      environment: {},
      remoteSource,
      send: (message) => sent.push(message),
      trace: { record: (record) => traced.push(record) },
    });
    if (!coordinator) throw new Error("remote_coordinator_unavailable");

    coordinator.handle(request);
    await waitUntil(() =>
      sent.some((message) => message.type === "suggestion_final"),
    );

    expect(sent.at(-1)).toMatchObject({
      type: "suggestion_final",
      payload: { text: " continuación real" },
    });
    expect(traced.map((record) => (record as { event: string }).event)).toEqual([
      "request_received",
      "helper_write",
    ]);
  });

  test("keeps the explicit visual fixture ahead of the remote source", async () => {
    const remoteSource = {
      async complete() {
        return " remote";
      },
    };
    const fixtureSent: ProtocolMessage[] = [];
    const fixture = createSuggestionBootstrap({
      environment: { AUTOCOMPLETION_VISUAL_FIXTURE: "1" },
      remoteSource,
      send: (message) => fixtureSent.push(message),
    });
    if (!fixture) throw new Error("fixture_coordinator_unavailable");
    fixture.handle(request);
    await waitUntil(() =>
      fixtureSent.some((message) => message.type === "suggestion_final"),
    );
    expect(fixtureSent.at(-1)).not.toMatchObject({
      payload: { text: " remote" },
    });

  });
});
