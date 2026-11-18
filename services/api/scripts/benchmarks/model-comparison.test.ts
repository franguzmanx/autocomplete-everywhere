import { describe, expect, test } from "vitest";

import { percentile, scoreContinuation } from "./model-comparison";

describe("model benchmark helpers", () => {
  test("computes nearest-rank latency percentiles", () => {
    expect(percentile([100, 200, 300, 400], 0.5)).toBe(200);
    expect(percentile([100, 200, 300, 400], 0.95)).toBe(400);
  });

  test("accepts a useful grounded continuation without retaining its text", () => {
    expect(
      scoreContinuation({
        caseId: "empty_related",
        textBefore: "",
        continuation: "Propuesta actualizada para revisión",
      }),
    ).toEqual({
      useful: true,
      metaLeak: false,
      repeatedPrefix: false,
      outputLength: 35,
      reasons: [],
    });
  });

  test("rejects agent reasoning and repeated input", () => {
    expect(
      scoreContinuation({
        caseId: "spanish",
        textBefore: "Hola equipo, mañana podemos ",
        continuation:
          "The user is writing in Spanish: Hola equipo, mañana podemos reunirnos",
      }),
    ).toMatchObject({
      useful: false,
      metaLeak: true,
      repeatedPrefix: false,
      reasons: expect.arrayContaining(["meta_leak"]),
    });

    expect(
      scoreContinuation({
        caseId: "english",
        textBefore: "The release candidate is ready, so we should ",
        continuation: "The release candidate is ready, so we should ship it",
      }),
    ).toMatchObject({
      useful: false,
      repeatedPrefix: true,
      reasons: expect.arrayContaining(["repeated_prefix"]),
    });
  });

  test("requires the expected script for CJK and RTL cases", () => {
    expect(
      scoreContinuation({
        caseId: "cjk",
        textBefore: "明日の会議では",
        continuation: "進捗を確認します",
      }).useful,
    ).toBe(true);
    expect(
      scoreContinuation({
        caseId: "rtl",
        textBefore: "سنتابع غدًا ",
        continuation: "مراجعة النتائج مع الفريق",
      }).useful,
    ).toBe(true);
    expect(
      scoreContinuation({
        caseId: "rtl",
        textBefore: "سنتابع غدًا ",
        continuation: "review the results",
      }).reasons,
    ).toContain("wrong_script");
  });

  test("does not mistake valid free-form English or code-switching for the wrong language", () => {
    expect(
      scoreContinuation({
        caseId: "english",
        textBefore: "The release candidate is ready, so we should ",
        continuation: "proceed with deployment",
      }).useful,
    ).toBe(true);
    expect(
      scoreContinuation({
        caseId: "code_switch",
        textBefore: "El deploy está green, pero todavía necesitamos ",
        continuation: "review los últimos detalles",
      }).useful,
    ).toBe(true);
    expect(
      scoreContinuation({
        caseId: "anti_meta",
        textBefore: "¿Qué es esto? No sé, pero creo que ",
        continuation: "es una buena idea",
      }).useful,
    ).toBe(true);
  });
});
