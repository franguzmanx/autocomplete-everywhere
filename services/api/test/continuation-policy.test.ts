import { describe, expect, test } from "vitest";

import { finalizeContinuation } from "../src/prompts/continuation-policy";

describe("finalizeContinuation", () => {
  test("strips a repeated prompt prefix from one final candidate", () => {
    expect(
      finalizeContinuation(
        "Hola Axel,",
        "Hola Axel, te mando el resumen.",
      ),
    ).toBe(" te mando el resumen.");
  });

  test("silences Markdown fences", () => {
    expect(finalizeContinuation("const value =", "```ts\nprivateContent()"))
      .toBe("");
  });

  test("normalizes CRLF and lone carriage returns in multiline content", () => {
    expect(finalizeContinuation("Lista:", "\r\n- café\r- 東京")).toBe(
      "\n- café\n- 東京",
    );
  });

  test("stops at unsafe controls", () => {
    expect(finalizeContinuation("Hola", " mundo\u0000private")).toBe(" mundo");
  });

  test("silences malformed UTF-16", () => {
    expect(finalizeContinuation("Hola", "\uDE00private")).toBe("");
    expect(finalizeContinuation("Hola", " \uD83D")).toBe("");
  });

  test("returns no suggestion for blank output", () => {
    expect(finalizeContinuation("Hola", " \n ")).toBe("");
    expect(finalizeContinuation("Hola", undefined)).toBe("");
  });

  test("limits output without splitting an emoji grapheme", () => {
    expect(
      finalizeContinuation("Hola", "ab😀cd", { maxOutputLength: 3 }),
    ).toBe("ab");
    expect(
      finalizeContinuation("Hola", "😀", { maxOutputLength: 1 }),
    ).toBe("");
  });

  test("a single-line field returns only the first line", () => {
    expect(
      finalizeContinuation(
        "",
        "  Propuesta actualizada\nEste texto pertenece al cuerpo",
        { maxOutputLength: 80, singleLine: true },
      ),
    ).toBe("Propuesta actualizada");
  });

  test("preserves the cursor-boundary space in a non-empty single-line field", () => {
    expect(
      finalizeContinuation("Follow", " up tomorrow", {
        maxOutputLength: 80,
        singleLine: true,
      }),
    ).toBe(" up tomorrow");
  });

  test("preserves authored CRLF bytes when requested", () => {
    expect(
      finalizeContinuation("", "Hola\r\n\r\nTabla:\t€ 1.250", {
        preserveLineEndings: true,
      }),
    ).toBe("Hola\r\n\r\nTabla:\t€ 1.250");
  });
});
