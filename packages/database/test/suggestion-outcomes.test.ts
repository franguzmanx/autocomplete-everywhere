import { describe, expect, test } from "vitest";

import {
  SuggestionOutcomeFailure,
  SuggestionOutcomeRepository,
  type SuggestionOutcomeRecord,
} from "../src/index";

const shown: SuggestionOutcomeRecord = {
  requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
  appId: "com.apple.Notes",
  surface: "text_editor",
  outcome: "shown",
  requestToVisibleMs: 480,
  suggestionCharacterCount: 21,
};

describe("SuggestionOutcomeRepository", () => {
  test("records events only under the verified subject", async () => {
    const calls: [string, readonly SuggestionOutcomeRecord[]][] = [];
    const repository = new SuggestionOutcomeRepository({
      record: async (subject, events) => {
        calls.push([subject, events]);
      },
    });

    await repository.record("user_verified", [shown]);

    expect(calls).toEqual([["user_verified", [shown]]]);
  });

  test("rejects an empty subject before reaching Postgres", async () => {
    let calls = 0;
    const repository = new SuggestionOutcomeRepository({
      record: async () => {
        calls += 1;
      },
    });

    await expect(repository.record(" ", [shown])).rejects.toMatchObject({
      code: "INVALID_SUBJECT",
      reason: "rejected",
    });
    expect(calls).toBe(0);
  });

  test("skips the database for an empty batch", async () => {
    let calls = 0;
    const repository = new SuggestionOutcomeRepository({
      record: async () => {
        calls += 1;
      },
    });

    await repository.record("user_verified", []);

    expect(calls).toBe(0);
  });

  test("classifies database failures without retaining event details", async () => {
    const repository = new SuggestionOutcomeRepository({
      record: async () => {
        throw Object.assign(new Error("permission denied for function"), {
          code: "42501",
        });
      },
    });

    const failure = await repository
      .record("user_verified", [shown])
      .catch((error: unknown) => error);

    expect(failure).toBeInstanceOf(SuggestionOutcomeFailure);
    expect(failure).toMatchObject({ code: "42501", reason: "rejected" });
    expect(String((failure as Error).message)).not.toContain("com.apple.Notes");
  });
});
