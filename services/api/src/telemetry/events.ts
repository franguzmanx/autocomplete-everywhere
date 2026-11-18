import { z } from "zod";

/// Outcome events the desktop may record. The schema is a strict allowlist:
/// any field that could carry draft, suggestion, clipboard, or retrieved
/// content is rejected before authentication of the payload completes.
export const SuggestionOutcomeEventSchema = z
  .object({
    requestId: z.string().uuid(),
    appId: z
      .string()
      .min(1)
      .max(256)
      .regex(/^[A-Za-z0-9._-]+$/),
    surface: z.enum(["text_editor", "web_textarea"]),
    outcome: z.enum([
      "requested",
      "generated",
      "suppressed",
      "failed",
      "cancelled",
      "shown",
      "accepted_full",
      "accepted_partial",
      "typed_through",
      "dismissed",
      "stale",
    ]),
    requestToVisibleMs: z.number().int().nonnegative().max(120_000).optional(),
    requestToFinalMs: z.number().int().nonnegative().max(120_000).optional(),
    suggestionCharacterCount: z.number().int().nonnegative().max(2_000).optional(),
    acceptedCharacterCount: z.number().int().nonnegative().max(2_000).optional(),
    errorClass: z
      .string()
      .min(1)
      .max(100)
      .regex(/^[a-z0-9_]+$/)
      .optional(),
  })
  .strict();

export const SuggestionOutcomeBatchSchema = z
  .object({
    events: z.array(SuggestionOutcomeEventSchema).min(1).max(50),
  })
  .strict();

export type SuggestionOutcomeEvent = z.infer<typeof SuggestionOutcomeEventSchema>;
