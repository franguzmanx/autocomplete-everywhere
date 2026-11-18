import { PreparedContextSchema } from "./context.js";
import { isReservedShortcut } from "./shortcut-reservations.js";
import { z } from "zod";
import { writingPreferencesSchema } from "./learning.js";
import { knowledgeCandidatesSchema } from "./knowledge.js";

export const PROTOCOL_VERSION = 5 as const;

export const WorkIdentitySchema = z
  .object({
    requestId: z.string().uuid(),
    focusSequence: z.number().int().nonnegative(),
    contentSignature: z.string().min(16).max(128),
    timestampMs: z.number().int().nonnegative(),
  })
  .strict();

const ProtocolEnvelopeSchema = z.object({
  protocolVersion: z.literal(PROTOCOL_VERSION),
});

const HelloMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("hello"),
  payload: z
    .object({
      platform: z.enum(["macos", "windows"]),
      helperVersion: z.string().min(1).max(64),
      capabilities: z.array(z.string().min(1).max(64)).max(32),
    })
    .strict(),
}).strict();

const PermissionStateMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("permission_state"),
  payload: z
    .object({
      accessibility: z.enum(["required", "granted"]),
      inputMonitoring: z.enum(["required", "granted"]),
    })
    .strict(),
}).strict();

const InteractionKeyBindingSchema = z.object({
  keyCode:z.number().int().min(0).max(127),
  modifiers:z.number().int().min(0).max(6912).refine(value => (value & ~6912) === 0),
}).strict().refine(value => !isReservedShortcut(value)).refine(value => (value.modifiers & (256 | 2048 | 4096)) !== 0
  || (value.modifiers === 0 && [36, 48, 53, 124].includes(value.keyCode)));

const ConfigureMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("configure"),
  payload: z
    .object({
      enabled: z.boolean(),
      // Explicit user exclusions; field interpretation remains capability based.
      excludedApplications: z.array(z.string().min(1).max(255).regex(/^[A-Za-z0-9._-]+$/)).max(500),
      automaticSuggestions: z.boolean(),
      quietPeriodMs: z.union([z.literal(0), z.literal(150), z.literal(300), z.literal(700)]),
      ghostAlpha: z.union([z.literal(0.30), z.literal(0.45)]),
      acceptShortcut: InteractionKeyBindingSchema,
      dismissShortcut: InteractionKeyBindingSchema,
      clipboardContextEnabled: z.boolean(),
      learningEnabled: z.boolean(),
      contextEnabled: z.boolean(),
      contextImagesEnabled: z.boolean(),
    })
    .strict(),
}).strict();

const FieldContextSchema = z
  .object({
    shape: z.enum(["single_line", "multiline"]),
    label: z.string().trim().min(1).max(160).optional(),
    placeholder: z.string().trim().min(1).max(160).optional(),
    sources: z.array(z.object({
      id: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/),
      containerId: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/),
      relation: z.enum(["labelled_by", "described_by", "shared_container"]),
      text: z.string().trim().min(1).max(2_000),
    }).strict()).max(24)
      .refine(sources => sources.reduce((total, source) => total + source.text.length, 0) <= 12_000, "Source text budget exceeded")
      .refine(sources => new Set(sources.map(source => source.id)).size === sources.length),
    relatedFields: z
      .array(
        z
          .object({
            shape: z.enum(["single_line", "multiline"]),
            label: z.string().trim().min(1).max(160).optional(),
            placeholder: z.string().trim().min(1).max(160).optional(),
            text: z.string().trim().min(1).max(2_000),
          })
          .strict(),
      )
      .max(3),
  })
  .strict();

const AuthoredArtifactSchema = z
  .object({
    id: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/),
    kind: z.enum(["selection", "clipboard", "saved", "recent_writing", "accepted_completion"]),
    sourceSurface: z.enum(["text_editor", "web_textarea"]).optional(),
    text: z.string().min(1).max(4_000),
    capturedAtMs: z.number().int().nonnegative(),
  })
  .strict();

const SuggestionRequestMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("suggestion_request"),
  identity: WorkIdentitySchema,
  payload: z
    .object({
      appId: z.string().min(1).max(256),
      surface: z.enum(["text_editor", "web_textarea"]),
      textBefore: z.string().max(8_000),
      textAfter: z.string().max(2_000),
      selectedText: z.string().max(2_000),
      explicit: z.boolean(),
      // Unaccepted ghosts are request-scoped alternatives, never authored context.
      alternativeTo: z.array(z.string().min(1).max(12_000).refine(text => text.trim().length > 0))
        .min(1).max(5).optional(),
      // Added by the desktop context service after native capture.
      knowledge: knowledgeCandidatesSchema.optional(),
      preparedContext: PreparedContextSchema.optional(),
      writingPreferences: writingPreferencesSchema.optional(),
      artifacts: z
        .array(AuthoredArtifactSchema)
        .max(5)
        .refine((artifacts) => artifacts.reduce((total, artifact) => total + artifact.text.length, 0) <= 12_000)
        .refine(
          (artifacts) =>
            new Set(artifacts.map((artifact) => artifact.id)).size ===
            artifacts.length,
        ),
      fieldContext: FieldContextSchema,
    })
    .strict().refine(payload => !payload.alternativeTo || payload.explicit),
}).strict();

const CancelRequestMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("cancel_request"),
  identity: WorkIdentitySchema,
  payload: z
    .object({
      reason: z.enum([
        "content_changed",
        "focus_changed",
        "dismissed",
        "shutdown",
      ]),
    })
    .strict(),
}).strict();

const SuggestionFinalMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("suggestion_final"),
  identity: WorkIdentitySchema,
  payload: z.union([
    z.object({ text: z.string().min(1).max(12_000) }).strict(),
    z
      .object({
        silenceReason: z.enum([
          "not_useful",
          "not_grounded",
          "unsafe",
          "timeout",
          "cancelled",
        ]),
      })
      .strict(),
  ]),
}).strict();

const RequestFailedMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("request_failed"),
  identity: WorkIdentitySchema,
  payload: z
    .object({
      code: z.enum(["unauthorized", "network", "timeout", "server"]),
      retryable: z.boolean(),
    })
    .strict(),
}).strict();

const InteractionMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("interaction"),
  identity: WorkIdentitySchema,
  payload: z
    .object({
      outcome: z.enum([
        "shown",
        "accepted_full",
        "accepted_partial",
        "dismissed",
        "typed_through",
        "edited_after_acceptance",
        "removed_after_acceptance",
        "observation_unavailable",
        "stale",
        "failed",
      ]),
      acceptedCharacters: z.number().int().nonnegative(),
    })
    .strict(),
}).strict();

const TransformConfigureMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("transform_configure"),
  payload: z.object({
    shortcuts: z.array(z.object({ id: z.string().uuid(), name: z.string().min(1).max(60), key: z.number().int().min(1).max(9) }).strict()).max(9).refine(items =>
      new Set(items.map(item => item.id)).size === items.length &&
      new Set(items.map(item => item.key)).size === items.length),
  }).strict(),
}).strict();
const TransformRequestMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("transform_request"), identity: WorkIdentitySchema,
  payload: z.object({ appId:z.string().min(1).max(256), transformId: z.string().uuid(), text: z.string().min(1).max(2000), singleLine: z.boolean() }).strict(),
}).strict();
const TransformResultMessageSchema = ProtocolEnvelopeSchema.extend({
  type: z.literal("transform_result"), identity: WorkIdentitySchema,
  payload: z.union([
    z.object({ text: z.string().min(1).max(8000) }).strict(),
    z.object({ error: z.enum(["unavailable", "cancelled"]) }).strict(),
  ]),
}).strict();

export const ProtocolMessageSchema = z.discriminatedUnion("type", [
  ProtocolEnvelopeSchema.extend({type:z.literal("context_observation"),payload:z.object({
    appId:z.string().min(1).max(256),documentId:z.string().min(1).max(256),capturedAtMs:z.number().int().nonnegative(),
    sources:z.array(z.object({id:z.string().min(1).max(256),text:z.string().min(1).max(2000)}).strict()).max(24)
      .refine(items=>items.reduce((sum,item)=>sum+item.text.length,0)<=12000),
    image:z.object({mediaType:z.literal("image/jpeg"),data:z.string().max(2800000).regex(/^[A-Za-z0-9+/]*={0,2}$/)}).strict().optional(),
  }).strict()}).strict(),
  ProtocolEnvelopeSchema.extend({type:z.literal("context_invalidate"),payload:z.object({requestIds:z.array(z.string().uuid()).max(64)}).strict()}).strict(),
  ProtocolEnvelopeSchema.extend({type:z.literal("context_request_screen_permission"),payload:z.null()}).strict(),
  ProtocolEnvelopeSchema.extend({type:z.literal("context_screen_permission"),payload:z.object({granted:z.boolean()}).strict()}).strict(),
  TransformConfigureMessageSchema,
  TransformRequestMessageSchema,
  TransformResultMessageSchema,
  HelloMessageSchema,
  PermissionStateMessageSchema,
  ConfigureMessageSchema,
  ProtocolEnvelopeSchema.extend({
    type: z.literal("request_suggestion"),
    payload: z.null(),
  }).strict(),
  ProtocolEnvelopeSchema.extend({
    type: z.literal("application_state"),
    payload: z.object({
      currentApplication: z.string().min(1).max(255).nullable(),
      applications: z.array(z.object({ id: z.string().min(1).max(255), name: z.string().min(1).max(255) }).strict()).max(500),
    }).strict(),
  }).strict(),
  SuggestionRequestMessageSchema,
  CancelRequestMessageSchema,
  SuggestionFinalMessageSchema,
  RequestFailedMessageSchema,
  InteractionMessageSchema,
  ProtocolEnvelopeSchema.extend({type: z.literal("user_activity"), payload: z.null()}).strict(),
  ProtocolEnvelopeSchema.extend({
    type: z.literal("correction_observed"), identity: WorkIdentitySchema,
    payload: z.object({
      appId: z.string().min(1).max(255), sessionId: z.string().uuid(),
      before: z.string().min(1).max(2000), after: z.string().min(1).max(2000),
      observedAtMs: z.number().int().nonnegative(),
    }).strict().refine(value => value.before !== value.after),
  }).strict(),
]);

export type WorkIdentity = z.infer<typeof WorkIdentitySchema>;
export type ProtocolMessage = z.infer<typeof ProtocolMessageSchema>;
export type SuggestionRequest = z.infer<typeof SuggestionRequestMessageSchema>;

export type ProtocolParseError = {
  ok: false;
  code: "protocol_version_mismatch" | "invalid_message";
};

export function parseProtocolMessage(
  input: unknown,
): ProtocolMessage | ProtocolParseError {
  if (
    typeof input === "object" &&
    input !== null &&
    "protocolVersion" in input &&
    input.protocolVersion !== PROTOCOL_VERSION
  ) {
    return { ok: false, code: "protocol_version_mismatch" };
  }

  const result = ProtocolMessageSchema.safeParse(input);
  return result.success
    ? result.data
    : { ok: false, code: "invalid_message" };
}
