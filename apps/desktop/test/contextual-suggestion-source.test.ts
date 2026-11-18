import { describe, expect, test, vi } from "vitest";
import type { KnowledgeCandidate, SuggestionRequest } from "@autocompletion/protocol";
import { ContextualSuggestionSource } from "../src/main/contextual-suggestion-source";

const request: SuggestionRequest = {
  protocolVersion: 5, type: "suggestion_request",
  identity: { requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63", focusSequence: 1, contentSignature: "0123456789abcdef", timestampMs: 1 },
  payload: { appId: "com.apple.Notes", surface: "text_editor", textBefore: "Sí, ", textAfter: "", selectedText: "", explicit: false, artifacts: [],
    fieldContext: { shape: "multiline", relatedFields: [], sources: [{ id: "source-1", containerId: "scene-1", relation: "shared_container", text: "Jacaranda price?" }] } },
};
const candidate: KnowledgeCandidate = { sourceId: "c870f5a0-ef01-443b-845b-7a48c12555cb", title: "Price", kind: "knowledge", text: "Jacaranda costs $30.", revision: 1, updatedAt: 1, expiresAt: null, scope: { appIds: [request.payload.appId], anchor: "Jacaranda" } };

describe("context service to final generation", () => {
  test("preserves current sources and artifacts without acquiring disabled Library data", async () => {
    const source = new ContextualSuggestionSource({
      isAllowed: () => true,
      transport: { complete: async forwarded => {
        expect(forwarded.payload.fieldContext).toEqual(request.payload.fieldContext);
        expect(forwarded.payload.artifacts).toEqual(request.payload.artifacts);
        expect(Object.hasOwn(forwarded.payload, "knowledge")).toBe(false);
        return "lo reviso.";
      } },
    });
    expect(await source.complete({ ...request, payload: { ...request.payload, knowledge: [candidate] } }, new AbortController().signal)).toBe("lo reviso.");
  });
  test("an exclusion stops acquisition and a late result", async () => {
    let calls = 0; let allowed = false;
    const source = new ContextualSuggestionSource({ isAllowed: () => allowed,
      transport: { complete: async () => { calls++; allowed = false; return "late"; } } });
    expect(await source.complete(request, new AbortController().signal)).toBe("");
    expect(calls).toBe(0);
    allowed = true;
    expect(await source.complete(request, new AbortController().signal)).toBe("");
    expect(calls).toBe(1);
  });
});

test("uses only desktop-owned current preferences and never helper-supplied preferences", async () => {
  const preference = { id:"da2f74ce-c1da-4e2e-85c7-b6d3c4069b63", appId:request.payload.appId, dimension:"concision" as const, value:"concise" as const, origin:"learned" as const };
  let active = true;
  const source = new ContextualSuggestionSource({ isAllowed:()=>true, preferencesForApp: appId => { expect(appId).toBe(request.payload.appId); return active ? [preference] : []; }, transport:{complete:async forwarded=>{
    if(active)expect(forwarded.payload.writingPreferences).toEqual([preference]);
    else expect(Object.hasOwn(forwarded.payload,"writingPreferences")).toBe(false);
    return "reply";
  }}});
  await source.complete(request,new AbortController().signal); active=false;
  await source.complete({...request,payload:{...request.payload,writingPreferences:[preference]}},new AbortController().signal);
});


test("forwards ephemeral alternatives unchanged without adding them to context or traces", async () => {
  const alternativeTo = [" SYNTHETIC_GHOST_ONLY"];
  const traces: unknown[] = [];
  let forwarded: SuggestionRequest | undefined;
  const source = new ContextualSuggestionSource({
    isAllowed: () => true,
    trace: { record: value => traces.push(value) },
    transport: { complete: async value => { forwarded = value; return " otra versión"; } },
  });
  await source.complete({...request, payload: {...request.payload, explicit: true, alternativeTo}}, new AbortController().signal);
  expect(forwarded?.payload.alternativeTo).toEqual(alternativeTo);
  expect(forwarded?.payload.artifacts).toEqual(request.payload.artifacts);
  expect(forwarded?.payload.fieldContext).toEqual(request.payload.fieldContext);
  expect(forwarded?.payload.writingPreferences).toBeUndefined();
  expect(JSON.stringify(traces)).not.toContain(alternativeTo[0]);
});

test("stalled dependency validation cannot hang delivery or publish unverified text", async () => {
  vi.useFakeTimers();
  try {
    const context = {
      prepare: async () => ({ evidence: [], dependencies: [], revision: "1", availability: { text: "ready", semantic: "included" } }) as any,
      valid: () => new Promise<boolean>(() => {}),
    };
    const source = new ContextualSuggestionSource({ isAllowed: () => true, context,
      transport: { complete: async () => "unverified text" } });
    const result = source.complete(request, new AbortController().signal);
    await vi.advanceTimersByTimeAsync(100);
    expect(await Promise.race([result, Promise.resolve("still waiting")])).toBe("");
  } finally { vi.useRealTimers(); }
});
