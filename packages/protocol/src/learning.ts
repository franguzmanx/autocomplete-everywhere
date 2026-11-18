import { z } from "zod";

const concision = z.object({ dimension: z.literal("concision"), value: z.enum(["concise", "balanced", "detailed"]) }).strict();
const formality = z.object({ dimension: z.literal("formality"), value: z.enum(["casual", "neutral", "formal"]) }).strict();
const structure = z.object({ dimension: z.literal("structure"), value: z.enum(["paragraphs", "lists"]) }).strict();
export const preferenceValueSchema = z.discriminatedUnion("dimension", [concision, formality, structure]);
const appIdSchema = z.string().min(1).max(255).regex(/^[A-Za-z0-9._-]+$/);
const preferenceIdentity = { id: z.string().uuid(), appId: appIdSchema.nullable(), origin: z.enum(["learned", "explicit"]) };
export const stylePreferenceSchema = z.discriminatedUnion("dimension", [
  concision.extend(preferenceIdentity), formality.extend(preferenceIdentity), structure.extend(preferenceIdentity),
]).refine(value => value.origin === "explicit" || value.appId !== null, "Learned preferences require an application");
export const writingPreferencesSchema = z.array(stylePreferenceSchema).max(24).refine(
  values => new Set(values.map(value => value.id)).size === values.length,
  "Preference IDs must be unique",
);
export const personalizationSnapshotSchema = z.object({
  enabled: z.boolean(), revision: z.number().int().nonnegative(), preferences: writingPreferencesSchema,
}).strict();
export const personalizationEditSchema = z.object({
  accountSubject: z.string().max(255), enabled: z.boolean(), edits: writingPreferencesSchema,
  forgetIds: z.array(z.string().uuid()).max(24).refine(ids => new Set(ids).size === ids.length), reset: z.boolean(),
}).strict().refine(value => value.accountSubject.length > 0 ||
  (!value.enabled && value.edits.length === 0 && value.forgetIds.length === 0 && !value.reset),
  "Personalization changes require an account",
);
const observedTextSchema = z.string().min(1).max(2_000).refine(value => value.trim().length > 0);
export const preferenceExtractionRequestSchema = z.object({
  observations: z.array(z.object({
    id: z.string().uuid(), sessionId: z.string().uuid(), appId: appIdSchema,
    before: observedTextSchema, after: observedTextSchema,
  }).strict().refine(value => value.before !== value.after, "Correction must change the text")).min(1).max(6)
    .refine(values => new Set(values.map(value => value.id)).size === values.length, "Observation IDs must be unique"),
}).strict();
const evidenceIdentity = { observationId: z.string().uuid() };
export const preferenceExtractionResponseSchema = z.object({
  evidence: z.array(z.discriminatedUnion("dimension", [
    concision.extend(evidenceIdentity), formality.extend(evidenceIdentity), structure.extend(evidenceIdentity),
  ])).max(18).refine(values => new Set(values.map(value => `${value.observationId}:${value.dimension}`)).size === values.length,
    "Each observation may have only one value per dimension"),
}).strict();
export type StylePreference = z.infer<typeof stylePreferenceSchema>;
export type PersonalizationSnapshot = z.infer<typeof personalizationSnapshotSchema>;
export type PersonalizationEdit = z.infer<typeof personalizationEditSchema>;
export type PreferenceExtractionRequest = z.infer<typeof preferenceExtractionRequestSchema>;
export type PreferenceExtractionResponse = z.infer<typeof preferenceExtractionResponseSchema>;
