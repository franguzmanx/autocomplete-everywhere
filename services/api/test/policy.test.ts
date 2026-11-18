import { describe, expect, test } from "vitest";

import {
  buildContinuationInstructions,
  buildContinuationPrompt,
  CONTINUATION_INSTRUCTIONS,
  INLINE_OUTPUT_CONTRACT,
  normalizeContinuation,
} from "../src/prompts/continuation";
import {
  SuggestionOutcomeBatchSchema,
  SuggestionOutcomeEventSchema,
} from "../src/telemetry/events";

describe("continuation normalization", () => {
  test("prefers grounded continuation when source context is ambiguous", () => {
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "If the source relationship is ambiguous, ignore that source and continue from the current draft",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain("uncertainty about exact wording is not a reason for silence");
    expect(CONTINUATION_INSTRUCTIONS).toContain("Do not agree, disagree, endorse, promise");
    expect(CONTINUATION_INSTRUCTIONS).not.toContain("Always propose");
    expect(CONTINUATION_INSTRUCTIONS).not.toContain("empty continuation");
  });

  test("removes an exact repeated cursor prefix", () => {
    expect(normalizeContinuation("Hola Axel,", "Hola Axel, te mando el resumen"))
      .toBe(" te mando el resumen");
  });

  test("rejects empty output", () => {
    expect(normalizeContinuation("Hola", "   ")).toBe(null);
  });

  test("makes the cursor boundary whitespace contract explicit to the model", () => {
    const prompt = buildContinuationPrompt(
      {
        protocolVersion: 5,
        type: "suggestion_request",
        identity: {
          requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
          focusSequence: 1,
          contentSignature: "a".repeat(64),
          timestampMs: 1,
        },
        payload: {
          appId: "com.apple.Notes",
          surface: "text_editor",
          textBefore: "El equipo necesita",
          selectedText: "",
          textAfter: "",
          explicit: false,
          artifacts: [],
          fieldContext: { sources: [],
            shape: "multiline",
            relatedFields: [],
          },
        },
      },
    );

    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "include whitespace only when the completed text requires it",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "Follow the author's language, tone, register, voice and formatting",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "Follow a deliberate switch in the author's writing",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "Interface labels, third-party sources and style preferences do not override the draft's language",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "not from its last word alone",
    );
    expect(prompt).not.toContain("LANGUAGE_HINT");
    expect(prompt).not.toContain("ACTIVE_LANGUAGE");
  });

  test("keeps language selection general and grounded in authored writing", () => {
    expect(CONTINUATION_INSTRUCTIONS).toContain("Borrowed terms, names, code, quotations and spelling mistakes do not by themselves signal a language switch");
    expect(CONTINUATION_INSTRUCTIONS).toContain("Infer the language of the unfinished thought from the surrounding user-authored draft");
    expect(CONTINUATION_INSTRUCTIONS).toContain("Interface labels, third-party sources and style preferences do not override the draft's language");
  });

  test("keeps language, facts, and human voice grounded in the writing state", () => {
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "Follow a deliberate switch in the author's writing",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "planned, pending, or completed",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "direct, concrete, and natural",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "generic openings, canned hooks or calls to action",
    );
    expect(CONTINUATION_INSTRUCTIONS).not.toMatch(/LANGUAGE_HINT|ACTIVE_LANGUAGE/);
  });

  test("builds one shared prompt with an explicit output contract", () => {
    const artifactContract =
      "Return the complete target artifact and preserve every required line break.";
    const instructions = buildContinuationInstructions(artifactContract);

    expect(instructions).toContain(artifactContract);
    expect(instructions).not.toContain(INLINE_OUTPUT_CONTRACT);
    expect(instructions.match(new RegExp(artifactContract, "g"))).toHaveLength(1);
  });

  test("gives one model the active and related context needed to infer intent", () => {
    const prompt = buildContinuationPrompt(
      {
        protocolVersion: 5,
        type: "suggestion_request",
        identity: {
          requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
          focusSequence: 1,
          contentSignature: "a".repeat(64),
          timestampMs: 1,
        },
        payload: {
          appId: "com.google.Chrome",
          surface: "web_textarea",
          textBefore: "",
          selectedText: "",
          textAfter: "",
          explicit: false,
          artifacts: [],
          fieldContext: { sources: [],
            shape: "single_line",
            placeholder: "Subject",
            relatedFields: [
              {
                shape: "multiline",
                label: "Message Body",
                text: "Hola Dana, te comparto la propuesta actualizada.",
              },
            ],
          },
        },
      },
    );

    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "Infer the writing task from user-authored text and the destination",
    );
    expect(CONTINUATION_INSTRUCTIONS).toContain(
      "When the active field is empty, use related fields",
    );
    const statePrefix = "WRITING_STATE_JSON\n";
    const stateStart = prompt.indexOf(statePrefix) + statePrefix.length;
    expect(JSON.parse(prompt.slice(
      stateStart,
      prompt.indexOf("\nEND_WRITING_STATE_JSON", stateStart),
    )))
      .toMatchObject({
        field: { placeholder: "Subject" },
        relatedFields: [{
          shape: "multiline",
          label: "Message Body",
          text: "Hola Dana, te comparto la propuesta actualizada.",
        }],
      });
  });

  test("places the active cursor data after its priority rule and conflicting background", () => {
    const prompt = buildContinuationPrompt(
      {
        protocolVersion: 5,
        type: "suggestion_request",
        identity: {
          requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
          focusSequence: 1,
          contentSignature: "a".repeat(64),
          timestampMs: 1,
        },
        payload: {
          appId: "com.openai.chat",
          surface: "web_textarea",
          textBefore: "Quick update: the integration is complete and the next step is ",
          selectedText: "",
          textAfter: "",
          explicit: false,
          artifacts: [],
          fieldContext: { sources: [], shape: "multiline", relatedFields: [] },
        },
      },
    );

    expect(prompt.indexOf('"capturedAtMs"')).toBeGreaterThan(prompt.indexOf('"textBeforeCursor"'));
    expect(prompt).not.toContain("userAuthoredBackground");
    expect(prompt).toContain("CURSOR_PRIORITY");
    expect(prompt).toContain(
      "Continue the current authored thought, preserving its language and exact cursor boundary",
    );
    expect(prompt.indexOf("CURSOR_PRIORITY")).toBeLessThan(
      prompt.indexOf("knowledge"),
    );
    expect(prompt.indexOf('"textBeforeCursor"')).toBeGreaterThan(
      prompt.indexOf("knowledge"),
    );
    expect(prompt.trimEnd().endsWith("END_WRITING_STATE_JSON")).toBe(true);
    expect(prompt).not.toMatch(/LANGUAGE_HINT|ACTIVE_LANGUAGE/);
  });
});

describe("content-free outcome events", () => {
  test("accepts allowlisted lifecycle fields", () => {
    expect(
      SuggestionOutcomeEventSchema.parse({
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "shown",
        requestToVisibleMs: 480,
        requestToFinalMs: 420,
        suggestionCharacterCount: 28,
      }),
    ).toBeTruthy();
  });

  test.each([
    "fieldText",
    "suggestionText",
    "textBefore",
    "retrievedContext",
    "clipboard",
    "modelId",
    "providerId",
    "experimentKey",
  ])("rejects a %s field", (forbiddenField) => {
    expect(() =>
      SuggestionOutcomeEventSchema.parse({
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "shown",
        [forbiddenField]: "private content",
      }),
    ).toThrow();
  });

  test("rejects free-form application identity and error classes", () => {
    expect(() =>
      SuggestionOutcomeEventSchema.parse({
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        appId: "Notes — Private draft title",
        surface: "text_editor",
        outcome: "shown",
      }),
    ).toThrow();
    expect(() =>
      SuggestionOutcomeEventSchema.parse({
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        appId: "com.apple.Notes",
        surface: "text_editor",
        outcome: "failed",
        errorClass: "failed while sending Hola Axel",
      }),
    ).toThrow();
  });

  test("bounds a batch to a small number of events", () => {
    const event = {
      requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
      appId: "com.apple.Notes",
      surface: "text_editor",
      outcome: "requested",
    };
    expect(SuggestionOutcomeBatchSchema.safeParse({ events: [] }).success).toBe(false);
    expect(
      SuggestionOutcomeBatchSchema.safeParse({ events: Array(51).fill(event) })
        .success,
    ).toBe(false);
    expect(
      SuggestionOutcomeBatchSchema.safeParse({ events: [event] }).success,
    ).toBe(true);
  });
});
