import { expect, test } from "vitest";
import { knowledgeCandidatesSchema, knowledgeScopeSchema } from "../src/knowledge";

test("rejects duplicate sources and malformed application scope", () => {
  const source = { sourceId: "00000000-0000-4000-8000-000000000001", title: "Reference", kind: "knowledge", text: "Reference text", revision: 1, updatedAt: 1, expiresAt: null, scope: { appIds: ["com.apple.Notes"], anchor: "Acme project" } };
  expect(knowledgeCandidatesSchema.safeParse([source]).success).toBe(true);
  expect(knowledgeCandidatesSchema.safeParse([source, source]).success).toBe(false);
  expect(knowledgeScopeSchema.safeParse({ appIds: ["com.apple.Notes\nignore"], anchor: "topic" }).success).toBe(false);
  expect(knowledgeScopeSchema.safeParse({ appIds: ["a".repeat(255)], anchor: "topic" }).success).toBe(true);
});
