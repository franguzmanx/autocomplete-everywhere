import { z } from "zod";
const identity = z.string().min(1).max(512);
export const ContextDependencySchema = z
  .object({ sourceId: identity, revision: identity })
  .strict();
const fields = {
  id: identity,
  sourceId: identity,
  revision: identity,
  appId: identity,
  accountId: identity.optional(),
  workspaceId: identity.optional(),
  resourceId: identity.optional(),
  documentId: identity.optional(),
  conversationId: identity.optional(),
  url: z.string().url().max(2048).optional(),
  capturedAtMs: z.number().int().nonnegative(),
  expiresAtMs: z.number().int().nonnegative(),
  text: z.string().min(1).max(16000),
  dependencies: z.array(ContextDependencySchema).max(24),
};
export const EvidenceSchema = z
  .discriminatedUnion("provenance", [
    z.object({ ...fields, provenance: z.literal("authored") }).strict(),
    z.object({ ...fields, provenance: z.literal("observed") }).strict(),
    z
      .object({
        ...fields,
        provenance: z.literal("derived"),
        dependencies: z.array(ContextDependencySchema).min(1).max(24),
      })
      .strict(),
  ])
  .superRefine((value, ctx) => {
    if (value.expiresAtMs <= value.capturedAtMs)
      ctx.addIssue({ code: "custom", message: "Expiry must follow capture" });
    if (
      new Set(value.dependencies.map((d) => d.sourceId)).size !==
      value.dependencies.length
    )
      ctx.addIssue({ code: "custom", message: "Duplicate dependency" });
  });
export const PreparedContextSchema = z
  .object({
    availability: z
      .object({
        text: z.literal("ready"),
        semantic: z.enum(["included", "not_prepared", "unavailable"]),
      })
      .strict(),
    evidence: z.array(EvidenceSchema).max(12),
    dependencies: z.array(ContextDependencySchema).max(64),
    revision: identity,
  })
  .strict()
  .superRefine((value, ctx) => {
    if (
      new TextEncoder().encode(value.evidence.map((e) => e.text).join(""))
        .length > 32000
    )
      ctx.addIssue({ code: "custom", message: "Context exceeds byte budget" });
    if (new Set(value.evidence.map((e) => e.id)).size !== value.evidence.length)
      ctx.addIssue({ code: "custom", message: "Duplicate evidence" });
    if (
      new Set(value.dependencies.map((d) => d.sourceId)).size !==
      value.dependencies.length
    )
      ctx.addIssue({ code: "custom", message: "Duplicate dependency" });
    const covered = new Map(
      value.dependencies.map((d) => [d.sourceId, d.revision]),
    );
    for (const ref of value.evidence.flatMap((e) => [
      { sourceId: e.sourceId, revision: e.revision },
      ...e.dependencies,
    ])) {
      if (covered.get(ref.sourceId) !== ref.revision)
        ctx.addIssue({ code: "custom", message: "Missing source revision" });
    }
    const revisions = new Map<string, string>();
    for (const item of [
      ...value.dependencies,
      ...value.evidence.flatMap((e) => [
        { sourceId: e.sourceId, revision: e.revision },
        ...e.dependencies,
      ]),
    ]) {
      if (
        revisions.has(item.sourceId) &&
        revisions.get(item.sourceId) !== item.revision
      )
        ctx.addIssue({
          code: "custom",
          message: "Conflicting source revisions",
        });
      revisions.set(item.sourceId, item.revision);
    }
  });
export type Evidence = z.infer<typeof EvidenceSchema>;
export type ContextDependency = z.infer<typeof ContextDependencySchema>;
export type PreparedContext = z.infer<typeof PreparedContextSchema>;
/** Drop expired evidence before provider use, including derivatives of expired retained sources. */
export function freshPreparedContext(
  context: PreparedContext | undefined,
  now = Date.now(),
): PreparedContext | undefined {
  if (!context) return undefined;
  const expired = new Set(
    context.evidence
      .filter((e) => e.expiresAtMs <= now || e.capturedAtMs > now)
      .map((e) => e.sourceId),
  );
  let evidence = context.evidence;
  for (;;) {
    const next = evidence.filter(
      (e) =>
        !expired.has(e.sourceId) &&
        !e.dependencies.some((d) => expired.has(d.sourceId)),
    );
    if (next.length === evidence.length) break;
    for (const e of evidence) if (!next.includes(e)) expired.add(e.sourceId);
    evidence = next;
  }
  return {
    ...context,
    evidence,
    dependencies: context.dependencies.filter((d) => !expired.has(d.sourceId)),
  };
}
