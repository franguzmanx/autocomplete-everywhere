import { GeminiSuggestionGenerator } from "../src/models/generate";
import { describe, expect, test } from "vitest";

import {
  createApp,
  SuggestionGenerationError,
  type SuggestionGenerator,
} from "../src/app";

const identity = {
  requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
  focusSequence: 7,
  contentSignature: "0123456789abcdef0123456789abcdef",
  timestampMs: 1_788_000_000_000,
};

const validRequest = {
  protocolVersion: 5,
  type: "suggestion_request",
  identity,
  payload: {
    appId: "com.apple.Notes",
    surface: "text_editor",
    textBefore: "Hola Axel,",
    textAfter: "",
    selectedText: "",
    explicit: false,
    artifacts: [],
    fieldContext: { sources: [],
      shape: "multiline",
      relatedFields: [],
    },
  },
};

function generator(chunks: string[]): SuggestionGenerator {
  return {
    async complete() {
      return chunks.join("");
    },
  };
}


const authenticated = async () => ({
  userId: "user_a",
});

describe("API", () => {
  test("forwards alternative intent through validation with the original writing evidence", async () => {
    let calls = 0;
    const alternativeTo = [" te escribo mañana."];
    const app = createApp({ authenticate: authenticated, generator: { async complete(input) {
      calls++;
      expect(input.request.payload.alternativeTo).toEqual(alternativeTo);
      expect(input.request.payload.artifacts).toEqual([]);
      expect(input.request.payload.textBefore).toBe(validRequest.payload.textBefore);
      return " vuelvo a escribirte mañana.";
    } } });
    const response = await app.request("/v1/suggestions", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({...validRequest, payload: {...validRequest.payload, explicit:true, alternativeTo}}),
    });
    expect(response.status).toBe(200);
    expect(await response.text()).toBe(" vuelvo a escribirte mañana.");
    expect(calls).toBe(1);
  });

  test.each(["text_editor", "web_textarea"])(
    "preserves a complete continuation in an already started %s multiline field",
    async (surface) => {
      const continuation = "\n\n" + "El informe incluye las observaciones verificadas y las acciones pendientes. ".repeat(5) + "\n\nSaludos.";
      const app = createApp({
        authenticate: authenticated,
        generator: {
          async complete(input) {
            expect(input.outputBudget.scope).toBe("block");
            return continuation;
          },
        },
      });
      const response = await app.request("/v1/suggestions", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          ...validRequest,
          payload: { ...validRequest.payload, surface },
        }),
      });
      expect(response.status).toBe(200);
      expect(await response.text()).toBe(continuation);
    },
  );

  test("reports health without authentication", async () => {
    const app = createApp({
      authenticate: async () => null,
      generator: generator([]),
    });

    const response = await app.request("/health");

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  test("authenticates before parsing an invalid request body", async () => {
    let authenticationCalls = 0;
    const app = createApp({
      authenticate: async () => {
        authenticationCalls += 1;
        return null;
      },
      generator: generator([]),
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "not-json",
    });

    expect(response.status).toBe(401);
    expect(authenticationCalls).toBe(1);
  });

  test("fails closed when the authentication service is unavailable", async () => {
    const app = createApp({
      authenticate: async () => {
        throw new Error("credentials unavailable");
      },
      generator: generator([]),
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validRequest),
    });

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "auth_unavailable" });
  });

  test("rejects an invalid or unknown surface", async () => {
    const app = createApp({
      authenticate: authenticated,
      generator: generator([]),
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: { ...validRequest.payload, surface: "unknown" },
      }),
    });

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_request" });
  });

  test("rejects a secure-field marker even when the rest is valid", async () => {
    const app = createApp({
      authenticate: authenticated,
      generator: generator([]),
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...validRequest, secureField: true }),
    });

    expect(response.status).toBe(400);
  });

  test("returns a valid continuation as one plain-text response", async () => {
    let receivedUserId = "";
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete(input) {
          receivedUserId = input.userId;
          return " te mando el resumen hoy.";
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: {
        authorization: "Bearer valid",
        "content-type": "application/json",
      },
      body: JSON.stringify(validRequest),
    });

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/plain");
    expect(await response.text()).toBe(" te mando el resumen hoy.");
    expect(receivedUserId).toBe("user_a");
  });

  test("correlates the response and records the content-free API lifecycle", async () => {
    const entries: unknown[] = [];
    let wallMs = 10_100;
    let monoMs = 100;
    const trace = {
      region: "iad1",
      instanceStartedWallMs: 10_000,
      now: () => ({ wallMs, monoMs }),
      claimCold: () => true,
      write: (entry: unknown) => entries.push(entry),
    };
    const app = createApp({
      authenticate: async () => {
        wallMs += 10;
        monoMs += 10;
        return { userId: "user_a" };
      },
      generator: {
        async complete() {
          wallMs += 30;
          monoMs += 30;
          wallMs += 5;
          monoMs += 5;
          return "SYNTHETIC_PRIVATE_SUGGESTION";
        },
      },
      trace,
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validRequest),
    });
    await response.text();

    expect(response.headers.get("x-autocompletion-request-id")).toBe(
      identity.requestId,
    );
    expect(entries).toEqual([
      {
        v: 1,
        requestId: identity.requestId,
        proc: "api",
        event: "received",
        wallMs: 10_100,
        monoMs: 100,
        attrs: { region: "iad1", cold: true, instanceAgeMs: 100 },
      },
      {
        v: 1,
        requestId: identity.requestId,
        proc: "api",
        event: "auth_done",
        wallMs: 10_110,
        monoMs: 110,
        attrs: { ms: 10, source: "origin" },
      },
      {
        v: 1,
        requestId: identity.requestId,
        proc: "api",
        event: "model_valid_object",
        wallMs: 10_145,
        monoMs: 145,
        attrs: { validObjectMs: 35 },
      },
      {
        v: 1,
        requestId: identity.requestId,
        proc: "api",
        event: "model_done",
        wallMs: 10_145,
        monoMs: 145,
        attrs: { totalMs: 35 },
      },
      {
        v: 1,
        requestId: identity.requestId,
        proc: "api",
        event: "response_end",
        wallMs: 10_145,
        monoMs: 145,
        attrs: { ms: 45, result: "text" },
      },
    ]);
    expect(JSON.stringify(entries)).not.toContain("SYNTHETIC_PRIVATE");
  });

  test.each(["```invalid candidate", "Hola Axel,", "\u0000invalid candidate", { text: "\u0000invalid artifact", preservesExactArtifacts: true }, { text: "" }, null, 123])("rejects a malformed final candidate %#", async (candidate) => {
    const app = createApp({ authenticate: authenticated, generator: { complete: async () => candidate } as SuggestionGenerator });
    const response = await app.request("/v1/suggestions", { method: "POST", body: JSON.stringify(validRequest) });
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "generation_failed" });
  });

  test.each(["\u000b", "\u000chello", "hello\u000b"])("returns an error for raw controls in a plain-text completion %#", async (text) => {
    const model = new GeminiSuggestionGenerator(() => ({} as never), { generate: async () => ({ text }) });
    const app = createApp({ authenticate: authenticated, generator: model });
    const response = await app.request("/v1/suggestions", { method: "POST", body: JSON.stringify({ ...validRequest, payload: { ...validRequest.payload, fieldContext: { ...validRequest.payload.fieldContext, shape: "single_line" } } }) });
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "generation_failed" });
  });

  test.each([undefined, ""])("preserves deliberate empty success %#", async (candidate) => {
    const app = createApp({ authenticate: authenticated, generator: { complete: async () => candidate } });
    const response = await app.request("/v1/suggestions", { method: "POST", body: JSON.stringify(validRequest) });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/plain");
    expect(await response.text()).toBe("");
    expect(response.headers.get("x-autocompletion-failure-kind")).toBeNull();
    expect(response.headers.get("x-autocompletion-failure-reason")).toBeNull();
  });

  test("records cancellation when the client aborts during generation", async () => {
    const controller = new AbortController();
    const entries: unknown[] = [];
    const app = createApp({ authenticate: authenticated, generator: { async complete() { controller.abort(); return undefined; } }, trace: { region: "test", instanceStartedWallMs: 0, now: () => ({ wallMs: 10, monoMs: 10 }), claimCold: () => false, write: (entry) => entries.push(entry) } });
    const response = await app.request(new Request("http://localhost/v1/suggestions", { method: "POST", body: JSON.stringify(validRequest), signal: controller.signal }));
    expect(response.status).toBe(499);
    expect(entries).toContainEqual(expect.objectContaining({ event: "response_end", attrs: { ms: 0, result: "cancelled", clientAborted: true } }));
  });

  test.each([
    { output: undefined, kind: "invalid_output" },
    { output: { offer: true, parts: [{ artifact: "missing" }] }, kind: "invalid_output" },
    { error: new DOMException("SYNTHETIC_PRIVATE_TIMEOUT", "TimeoutError"), kind: "timeout" },
  ])("traces a final generation failure as $kind without private content", async ({ output, error, kind }) => {
    const entries: unknown[] = [];
    const model = new GeminiSuggestionGenerator(() => ({} as never), { generate: async () => { if (error) throw error; return { output }; } });
    const app = createApp({ authenticate: authenticated, generator: model, trace: { region: "test", instanceStartedWallMs: 0, now: () => ({ wallMs: 10, monoMs: 10 }), claimCold: () => false, write: (entry) => entries.push(entry) } });
    const response = await app.request("/v1/suggestions", { method: "POST", body: JSON.stringify(validRequest) });
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "generation_failed" });
    expect(entries).toContainEqual(expect.objectContaining({ event: "response_end", attrs: expect.objectContaining({ result: "error", kind }) }));
    expect(entries).not.toContainEqual(expect.objectContaining({ event: "model_valid_object" }));
    expect(JSON.stringify(entries)).not.toContain("SYNTHETIC_PRIVATE");
  });

  test.each([
    [new SuggestionGenerationError("invalid_output", "ai_nooutputgeneratederror"), "invalid_output", "ai_nooutputgeneratederror"],
    [new SuggestionGenerationError("invalid_output", "ai_noobjectgeneratederror"), "invalid_output", "ai_noobjectgeneratederror"],
    [new SuggestionGenerationError("timeout", "timeout"), "timeout", "timeout"],
    [new SuggestionGenerationError("invalid_output", "SYNTHETIC_PRIVATE_REASON"), "invalid_output", "unknown"],
    [new SuggestionGenerationError("SYNTHETIC_PRIVATE_KIND" as never, "SYNTHETIC_PRIVATE_REASON"), "provider_error", "unknown"],
    [new Error("SYNTHETIC_PRIVATE_PROVIDER_MESSAGE"), "provider_error", "unknown"],
  ])("exposes only bounded failure diagnostics across HTTP %#", async (error, kind, reason) => {
    const app = createApp({ authenticate: authenticated, generator: { async complete() { throw error; } } });
    const response = await app.request("/v1/suggestions", { method: "POST", body: JSON.stringify(validRequest) });
    expect(response.status).toBe(502);
    expect(response.headers.get("x-autocompletion-failure-kind")).toBe(kind);
    expect(response.headers.get("x-autocompletion-failure-reason")).toBe(reason);
    expect(JSON.stringify([...response.headers])).not.toContain("SYNTHETIC_PRIVATE");
    expect(await response.json()).toEqual({ error: "generation_failed" });
  });

  test("reports a generation failure before committing an empty success response", async () => {
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete() {
          throw new Error("SYNTHETIC_PRIVATE_PROVIDER_MESSAGE");
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validRequest),
    });

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "generation_failed" });
  });

  test("returns silence without calling the model when the field has no context", async () => {
    let generationCalls = 0;
    let contextReads = 0;
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete() {
          generationCalls += 1;
          return "Por favor, escribe el texto que deseas continuar.";
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: {
          ...validRequest.payload,
          textBefore: "",
          textAfter: "",
          selectedText: "",
        },
      }),
    });

    expect(response.status).toBe(200);
    expect(await response.text()).toBe("");
    expect(contextReads).toBe(0);
    expect(generationCalls).toBe(0);
  });

  test("sends an empty field and its related context through one generation call", async () => {
    let receivedShape = "";
    let receivedRelatedText = "";
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete(input) {
          receivedShape = input.request.payload.fieldContext.shape;
          receivedRelatedText =
            input.request.payload.fieldContext.relatedFields[0]?.text ?? "";
          return "Propuesta actualizada para septiembre";
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: {
          ...validRequest.payload,
          textBefore: "",
          textAfter: "",
          selectedText: "",
          fieldContext: { sources: [],
            shape: "single_line",
            placeholder: "Subject",
            relatedFields: [
              {
                shape: "multiline",
                label: "Message Body",
                text: "Hola Dana, te comparto la propuesta actualizada para septiembre.",
              },
            ],
          },
        },
      }),
    });

    expect(response.status).toBe(200);
    expect(await response.text()).toBe("Propuesta actualizada para septiembre");
    expect(receivedShape).toBe("single_line");
    expect(receivedRelatedText).toBe(
      "Hola Dana, te comparto la propuesta actualizada para septiembre.",
    );
  });

  test("bounds a derived subject to one concise line", async () => {
    const app = createApp({
      authenticate: authenticated,
      generator: generator([
        "  Propuesta actualizada para septiembre",
        "\nEsta segunda línea no pertenece al asunto",
      ]),
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: {
          ...validRequest.payload,
          textBefore: "",
          fieldContext: { sources: [],
            shape: "single_line",
            placeholder: "Subject",
            relatedFields: [
              {
                shape: "multiline",
                label: "Message Body",
                text: "Hola Dana, te comparto la propuesta.",
              },
            ],
          },
        },
      }),
    });

    expect(await response.text()).toBe("Propuesta actualizada para septiembre");
  });

  test("allows a complete block in an empty native multiline field with authored evidence", async () => {
    let receivedBudget: unknown;
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete(input) {
          receivedBudget = input.outputBudget;
          return "Hola Dana, te comparto la propuesta actualizada.\n\nEl siguiente paso es revisar el cronograma.";
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: {
          ...validRequest.payload,
          textBefore: "",
          fieldContext: { sources: [],
            shape: "multiline",
            label: "Message Body",
            relatedFields: [
              {
                shape: "single_line",
                placeholder: "Subject",
                text: "Propuesta actualizada",
              },
            ],
          },
        },
      }),
    });

    expect(await response.text()).toBe(
      "Hola Dana, te comparto la propuesta actualizada.\n\nEl siguiente paso es revisar el cronograma.",
    );
    expect(receivedBudget).toEqual({
      scope: "block",
      maxCharacters: 2_000,
      allowsNewlines: true,
    });
  });

  test("uses an authored artifact as evidence for an empty native field and preserves exact bytes", async () => {
    const artifactText = "Hola Dana,\r\n\r\nTabla:\t€ 1.250 🚀";
    let receivedBudget: unknown;
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete(input) {
          receivedBudget = input.outputBudget;
          return artifactText;
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: {
          ...validRequest.payload,
          textBefore: "",
          artifacts: [
            {
              id: "clipboard-current",
              kind: "clipboard",
              text: artifactText,
              capturedAtMs: 1_788_000_000_000,
            },
          ],
          fieldContext: { sources: [], shape: "multiline", relatedFields: [] },
        },
      }),
    });

    expect(response.status).toBe(200);
    expect(await response.text()).toBe(artifactText);
    expect(receivedBudget).toEqual({
      scope: "block",
      maxCharacters: 2_000 + artifactText.length,
      allowsNewlines: true,
    });
  });

  test("uses the full artifact budget in an empty web multiline field without an explicit trigger", async () => {
    const artifactText = `${"A".repeat(1_500)}\r\n\r\n${"B".repeat(1_500)}`;
    let receivedBudget: unknown;
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete(input) {
          receivedBudget = input.outputBudget;
          return artifactText;
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: {
          ...validRequest.payload,
          surface: "web_textarea",
          textBefore: "",
          artifacts: [
            {
              id: "clipboard-current",
              kind: "clipboard",
              text: artifactText,
              capturedAtMs: 1_788_000_000_000,
            },
          ],
          fieldContext: { sources: [], shape: "multiline", relatedFields: [] },
        },
      }),
    });

    expect(response.status).toBe(200);
    expect(await response.text()).toBe(artifactText);
    expect(receivedBudget).toEqual({
      scope: "block",
      maxCharacters: 2_000 + artifactText.length,
      allowsNewlines: true,
    });
  });

  test("allows an explicit complete block in an empty web multiline field with evidence", async () => {
    let receivedBudget: unknown;
    const app = createApp({
      authenticate: authenticated,
      generator: {
        async complete(input) {
          receivedBudget = input.outputBudget;
          return "Primera línea segura.\nEsta línea no debe ofrecerse todavía.";
        },
      },
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...validRequest,
        payload: {
          ...validRequest.payload,
          surface: "web_textarea",
          textBefore: "",
          explicit: true,
          fieldContext: { sources: [],
            shape: "multiline",
            label: "Message Body",
            relatedFields: [
              {
                shape: "single_line",
                label: "Topic",
                text: "Propuesta actualizada",
              },
            ],
          },
        },
      }),
    });

    expect(await response.text()).toBe(
      "Primera línea segura.\nEsta línea no debe ofrecerse todavía.",
    );
    expect(receivedBudget).toEqual({
      scope: "block",
      maxCharacters: 2_000,
      allowsNewlines: true,
    });
  });

  test("strips a repeated prompt prefix from the final candidate", async () => {
    const app = createApp({
      authenticate: authenticated,
      generator: generator(["Hola", " Axel, te mando", " el resumen."]),
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validRequest),
    });

    expect(await response.text()).toBe(" te mando el resumen.");
  });

  test("rejects a generated continuation beyond the response limit", async () => {
    const app = createApp({
      authenticate: authenticated,
      generator: generator(["x".repeat(2_100)]),
    });

    const response = await app.request("/v1/suggestions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validRequest),
    });

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "generation_failed" });
  });

  test("removes the old unscoped profile endpoint", async () => {
    const app = createApp({ authenticate: authenticated, generator: generator([]) });
    expect((await app.request("/v1/context/manual", {method: "PUT", body: "{}"})).status).toBe(404);
  });
  test.each([false, true])("incidental recent writing cannot authorize an empty field, explicit=%s", async (explicit) => {
    let calls = 0;
    const app = createApp({authenticate: authenticated, generator: {async complete() { calls++; return "Invented opinion"; }}});
    const request = structuredClone(validRequest);
    request.payload.textBefore = "";
    request.payload.explicit = explicit;
    (request.payload.artifacts as unknown[]) = [{id: "recent", kind: "recent_writing", text: "A previous unrelated opinion", sourceSurface: "text_editor", capturedAtMs: 1}];
    const response = await app.request("/v1/suggestions", {method: "POST", body: JSON.stringify(request)});
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("");
    expect(calls).toBe(0);
  });
  test.each([false, true])("passes current read-only evidence for model judgment on automatic and explicit requests: %s", async (explicit) => {
    let received: unknown;
    const sources = [{id: "source_1", containerId: "container_1", relation: "shared_container", text: "Third-party proposal"}];
    const app = createApp({authenticate: authenticated, generator: {async complete(input) { received = input.request.payload.fieldContext.sources; return undefined; }}});
    const response = await app.request("/v1/suggestions", {method: "POST", body: JSON.stringify({...validRequest, payload: {...validRequest.payload, explicit, textBefore: "", fieldContext: {...validRequest.payload.fieldContext, sources}}})});
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("");
    expect(received).toEqual(sources);
  });
  test("rejects unscoped knowledge and never treats scoped knowledge as empty-field intent", async () => {
    let calls = 0;
    const app = createApp({authenticate: authenticated, generator: {async complete() { calls++; return "Opinion"; }}});
    const knowledge = [{sourceId: "00000000-0000-4000-8000-000000000099", title: "Facts", kind: "knowledge", text: "inspection facts", revision: 1, updatedAt: 1, expiresAt: null, scope: {appIds: [] as string[], anchor: ""}}];
    const body = {...validRequest, payload: {...validRequest.payload, textBefore: "", knowledge}};
    expect((await app.request("/v1/suggestions", {method: "POST", body: JSON.stringify(body)})).status).toBe(400);
    knowledge[0]!.scope = {appIds: ["com.apple.Notes"], anchor: "inspection"};
    const response = await app.request("/v1/suggestions", {method: "POST", body: JSON.stringify(body)});
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("");
    expect(calls).toBe(0);
  });

  test("passes only current-app or global explicit writing preferences", async () => {
    let received: unknown;
    const base = {id:"00000000-0000-4000-8000-000000000001",dimension:"concision",value:"concise",appId:"com.apple.Notes",origin:"learned"};
    const preferences = [base,{...base,id:"00000000-0000-4000-8000-000000000002",appId:"other.app"},{...base,id:"00000000-0000-4000-8000-000000000003",appId:null,origin:"explicit"}];
    const app = createApp({authenticate:authenticated,generator:{complete:async input => {received=input.request.payload.writingPreferences;return undefined;}}});
    const response = await app.request("/v1/suggestions",{method:"POST",body:JSON.stringify({...validRequest,payload:{...validRequest.payload,writingPreferences:preferences}})});
    expect(response.status).toBe(200);
    expect(received).toEqual([preferences[0],preferences[2]]);
  });

  test("drops expired and other-app knowledge without fetching a profile", async () => {
    let received: unknown;
    const candidate = {sourceId: "00000000-0000-4000-8000-000000000099", title: "Inspection", kind: "knowledge", text: "Known fact", revision: 1, updatedAt: 1, expiresAt: null, scope: {appIds: ["com.apple.Notes"], anchor: "inspection"}};
    const app = createApp({authenticate: authenticated, generator: {async complete(input) {received = input.request.payload.knowledge; return undefined; }}});
    const knowledge = [candidate, {...candidate, sourceId: "00000000-0000-4000-8000-000000000098", expiresAt: 1}, {...candidate, sourceId: "00000000-0000-4000-8000-000000000097", scope: {...candidate.scope, appIds: ["other.app"]}}];
    const response = await app.request("/v1/suggestions", {method: "POST", body: JSON.stringify({...validRequest, payload: {...validRequest.payload, knowledge}})});
    expect(response.status).toBe(200);
    expect(received).toEqual([candidate]);
  });

  test.each([
    {artifact: "Account: 123\nRouting: 456", before: "", shape: "single_line", parts: [{artifact: "clip"}], expected: ""},
    {artifact: "ha ha", before: "ha ", shape: "multiline", parts: [{artifact: "clip"}], expected: "ha ha"},
    {artifact: "ha ha\r\nnext", before: "ha ", shape: "multiline", parts: [{artifact: "clip"}, {text: " generated"}], expected: "ha ha\r\nnext generated"},
  ])("preserves exact composition or rejects incompatible destination: $shape $artifact", async ({artifact, before, shape, parts, expected}) => {
    const model = new GeminiSuggestionGenerator(() => ({} as never), {generate: async () => ({output: {offer: true, parts}})});
    const app = createApp({authenticate: authenticated, generator: model});
    const response = await app.request("/v1/suggestions", {method: "POST", body: JSON.stringify({...validRequest, payload: {...validRequest.payload, textBefore: before, artifacts: [{id: "clip", kind: "selection", text: artifact, capturedAtMs: 1}], fieldContext: {...validRequest.payload.fieldContext, shape}}})});
    expect(response.status).toBe(expected ? 200 : 502);
    if (expected) expect(await response.text()).toBe(expected);
    else expect(await response.json()).toEqual({ error: "generation_failed" });
  });

});
