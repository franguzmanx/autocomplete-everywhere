import { z } from "zod";

// Closed HTTP diagnostic vocabulary. Never serialize arbitrary exception messages,
// names, causes, provider response bodies, or writing content into these fields.
export const generationFailureKindSchema = z.enum(["invalid_output", "timeout", "provider_error"]);
export const generationFailureReasonSchema = z.enum([
  "ai_nooutputgeneratederror", "ai_noobjectgeneratederror", "ai_apicallerror",
  "timeout", "aborterror", "error", "unknown",
  "invalid_candidate", "candidate_rejected", "required_object_missing_or_invalid",
  "plain_text_missing_or_invalid", "plain_text_unsafe_controls",
  "offer_true_without_parts", "unknown_artifact_reference", "empty_composition",
  "generated_text_outside_budget", "artifact_outside_budget",
]);
export type GenerationFailureKind = z.infer<typeof generationFailureKindSchema>;
export type GenerationFailureReason = z.infer<typeof generationFailureReasonSchema>;
