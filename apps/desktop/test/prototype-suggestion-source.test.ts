import { describe, expect, test } from "vitest";

import type { SuggestionRequest } from "@autocompletion/protocol";

import { createPrototypeSuggestionSource } from "../src/main/prototype-suggestion-source";

const DEFAULT_FIXTURE =
  "En una interfaz confiable, la sugerencia permanece junto al cursor mientras escribís, se oculta ante una geometría dudosa y reaparece únicamente cuando la posición vuelve a ser estable.";
const UNICODE_FIXTURE =
  "También debe respetar emoji 🚀, acentos, 日本語 y العربية sin duplicar texto.";
const LIST_FIXTURE =
  "\n- primer punto con una explicación extensa\n- segundo punto que verifica el ajuste del párrafo";

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
    textBefore: "private fixture",
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

async function collect(
  textBefore: string,
  signal: AbortSignal = new AbortController().signal,
): Promise<string> {
  const source = createPrototypeSuggestionSource({
    AUTOCOMPLETION_VISUAL_FIXTURE: "1",
  });
  if (!source) throw new Error("fixture_source_unavailable");
  return source.complete(
    {
      ...request,
      payload: { ...request.payload, textBefore },
    },
    signal,
  );
}

async function collectDecision(
  textBefore: string,
  signal: AbortSignal = new AbortController().signal,
): Promise<{ completion: string; decisions: unknown[] }> {
  const decisions: unknown[] = [];
  const source = createPrototypeSuggestionSource(
    { AUTOCOMPLETION_VISUAL_FIXTURE: "1" },
    { onDecision: (decision) => decisions.push(decision) },
  );
  if (!source) throw new Error("fixture_source_unavailable");
  const completion = await source.complete(
    {
      ...request,
      payload: { ...request.payload, textBefore },
    },
    signal,
  );
  return { completion, decisions };
}

describe("PrototypeSuggestionSource", () => {
  test("is absent from the product path unless visual fixture mode is explicit", () => {
    expect(createPrototypeSuggestionSource({})).toBeNull();
    expect(
      createPrototypeSuggestionSource({ AUTOCOMPLETION_VISUAL_FIXTURE: "0" }),
    ).toBeNull();
    expect(
      createPrototypeSuggestionSource({ AUTOCOMPLETION_VISUAL_FIXTURE: "1" }),
    ).not.toBeNull();
  });

  test("selects the exact deterministic fixture strings by explicit marker", async () => {
    expect(await collect("draft")).toBe(DEFAULT_FIXTURE);
    expect(await collect("unicode:")).toBe(UNICODE_FIXTURE);
    expect(await collect("lista:")).toBe(LIST_FIXTURE);
  });

  test("returns only the untyped suffix while completing partial words", async () => {
    expect(await collect("draft En una interfaz confia")).toBe(
      "ble, la sugerencia permanece junto al cursor mientras escribís, se oculta ante una geometría dudosa y reaparece únicamente cuando la posición vuelve a ser estable.",
    );
    expect(await collect("unicode:También debe resp")).toBe(
      "etar emoji 🚀, acentos, 日本語 y العربية sin duplicar texto.",
    );
    expect(await collect("lista:\n- primer pun")).toBe(
      "to con una explicación extensa\n- segundo punto que verifica el ajuste del párrafo",
    );
  });

  test("stays silent when the newest character breaks a default fixture prefix", async () => {
    const prefix = DEFAULT_FIXTURE.slice(0, 72);

    expect(await collect(`${prefix}x`)).toBe("");
    expect((await collectDecision(`${prefix}x`)).decisions).toEqual([
      { outcome: "silence", reason: "no_match" },
    ]);
    expect(await collect("unrelated draft")).toBe(DEFAULT_FIXTURE);
  });

  test("stays silent after any selected fixture is complete", async () => {
    expect(await collect(`draft ${DEFAULT_FIXTURE}`)).toBe("");
    expect(await collect(`unicode:${UNICODE_FIXTURE}`)).toBe("");
    expect(await collect(`lista:${LIST_FIXTURE}`)).toBe("");
  });

  test("keeps the fixture available after pasted or typed trailing spaces", async () => {
    expect(await collect("draft  ")).toBe(DEFAULT_FIXTURE);
    expect(await collect("ordinary pasted text  ")).toBe(DEFAULT_FIXTURE);
  });

  test("returns nothing after cancellation", async () => {
    const controller = new AbortController();
    controller.abort();

    expect(await collect("draft", controller.signal)).toBe("");
  });

  test("matches Unicode prefixes exactly without case or diacritic folding", async () => {
    expect(await collect("unicode:También debe respetar emoji 🚀, ac")).toBe(
      "entos, 日本語 y العربية sin duplicar texto.",
    );
    expect(await collect("unicode:también debe")).toBe("");
    expect(await collect("unicode:Tambien debe")).toBe("");
  });

  test("continues the multiline marker after its intentional newline", async () => {
    expect(await collect("lista:\n")).toBe(
      "- primer punto con una explicación extensa\n- segundo punto que verifica el ajuste del párrafo",
    );
    expect(await collect("ordinary paragraph\n")).toBe("");
  });

  test("never repeats content after a yielded fixture is accepted", async () => {
    const cases = [
      { before: "draft", acceptedPrefix: "draft" },
      { before: "unicode:", acceptedPrefix: "unicode:" },
      { before: "lista:", acceptedPrefix: "lista:" },
    ];

    for (const fixture of cases) {
      const first = await collect(fixture.before);
      expect(first).not.toBe("");
      expect(await collect(fixture.acceptedPrefix + first)).toBe("");
    }
  });

  test("does not expose captured request text through its deterministic output", async () => {
    const chunks = await collect("private fixture");

    expect(JSON.stringify(chunks)).not.toContain("private fixture");
  });

  test("classifies fixture text and silence without exposing request content", async () => {
    const aborted = new AbortController();
    aborted.abort();

    expect((await collectDecision("E")).decisions).toEqual([
      { outcome: "text", reason: "default" },
    ]);
    expect((await collectDecision("unicode:También")).decisions).toEqual([
      { outcome: "text", reason: "unicode" },
    ]);
    expect((await collectDecision("lista:\n")).decisions).toEqual([
      { outcome: "text", reason: "list" },
    ]);
    expect((await collectDecision("draft  ")).decisions).toEqual([
      { outcome: "text", reason: "default" },
    ]);
    expect((await collectDecision("ordinary paragraph\n")).decisions).toEqual([
      { outcome: "silence", reason: "newline" },
    ]);
    expect((await collectDecision(`draft ${DEFAULT_FIXTURE}`)).decisions).toEqual([
      { outcome: "silence", reason: "complete" },
    ]);
    expect((await collectDecision("unicode:not the fixture")).decisions).toEqual([
      { outcome: "silence", reason: "no_match" },
    ]);
    expect((await collectDecision("E", aborted.signal)).decisions).toEqual([
      { outcome: "silence", reason: "cancelled" },
    ]);
    expect(
      JSON.stringify((await collectDecision("never include this private phrase")).decisions),
    ).not.toContain("never include this private phrase");
  });
});
