import { z } from "zod";

export const knowledgeScopeSchema = z.object({
  appIds: z.array(z.string().min(1).max(255).regex(/^[A-Za-z0-9._-]+$/)).max(20),
  anchor: z.string().trim().max(200),
}).strict();
export const knowledgeKindSchema = z.enum(["memory", "knowledge", "style"]);
export const knowledgeCandidateSchema = z.object({
  sourceId: z.string().uuid(),
  title: z.string().trim().min(1).max(120),
  kind: knowledgeKindSchema,
  text: z.string().min(1).max(12_000),
  revision: z.number().int().positive(),
  updatedAt: z.number().int().nonnegative(),
  expiresAt: z.number().int().nonnegative().nullable(),
  scope: knowledgeScopeSchema,
}).strict().refine(value => value.kind === "style" || (value.scope.appIds.length > 0 && value.scope.anchor.length >= 3), "Memory and knowledge need an application and topic anchor");
export const knowledgeCandidatesSchema = z.array(knowledgeCandidateSchema).max(6).refine(values => values.reduce((sum, value) => sum + value.text.length, 0) <= 12_000, "Knowledge budget exceeded").refine(values => new Set(values.map(value => value.sourceId)).size === values.length, "Knowledge source IDs must be unique");
export type KnowledgeCandidate = z.infer<typeof knowledgeCandidateSchema>;
