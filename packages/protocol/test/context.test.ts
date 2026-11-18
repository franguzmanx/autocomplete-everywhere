import { expect, it } from "vitest";
import { EvidenceSchema, PreparedContextSchema } from "../src/context.js";
const availability = {
  text: "ready" as const,
  semantic: "not_prepared" as const,
};
const evidence = {
  provenance: "observed",
  id: "e",
  sourceId: "s",
  revision: "1",
  appId: "app",
  capturedAtMs: 1,
  expiresAtMs: 2,
  text: "source",
  dependencies: [],
};
it("rejects derived material without dependencies and invalid expiry", () => {
  expect(
    EvidenceSchema.safeParse({ ...evidence, provenance: "derived" }).success,
  ).toBe(false);
  expect(
    EvidenceSchema.safeParse({ ...evidence, expiresAtMs: 0 }).success,
  ).toBe(false);
});
it("bounds prepared context bytes and rejects duplicated evidence", () => {
  expect(
    PreparedContextSchema.safeParse({
      availability,
      revision: "1",
      dependencies: [],
      evidence: [evidence, evidence],
    }).success,
  ).toBe(false);
  expect(
    PreparedContextSchema.safeParse({
      availability,
      revision: "1",
      dependencies: [],
      evidence: [{ ...evidence, text: "🙂".repeat(8100) }],
    }).success,
  ).toBe(false);
});
it("invalidates derived evidence transitively when its retained source expires", async () => {
  const { freshPreparedContext } = await import("../src/context.js");
  const root = { ...evidence, provenance: "observed" as const };
  const derived = {
    ...root,
    id: "derived",
    sourceId: "d",
    provenance: "derived" as const,
    expiresAtMs: 100,
    dependencies: [{ sourceId: "s", revision: "1" }],
  };
  const context = {
    availability,
    revision: "1",
    dependencies: [],
    evidence: [root, derived],
  };
  expect(freshPreparedContext(context, 3)?.evidence).toEqual([]);
});
it("requires the prepared revision list to cover every source and derived dependency", () => {
  expect(
    PreparedContextSchema.safeParse({
      availability,
      revision: "r",
      dependencies: [],
      evidence: [evidence],
    }).success,
  ).toBe(false);
  const derived = {
    ...evidence,
    sourceId: "derived",
    id: "derived",
    provenance: "derived",
    dependencies: [{ sourceId: "s", revision: "1" }],
  };
  expect(
    PreparedContextSchema.safeParse({
      availability,
      revision: "r",
      dependencies: [{ sourceId: "derived", revision: "1" }],
      evidence: [derived],
    }).success,
  ).toBe(false);
  expect(
    PreparedContextSchema.safeParse({
      availability,
      revision: "r",
      dependencies: [
        { sourceId: "derived", revision: "1" },
        { sourceId: "s", revision: "1" },
      ],
      evidence: [derived],
    }).success,
  ).toBe(true);
});
