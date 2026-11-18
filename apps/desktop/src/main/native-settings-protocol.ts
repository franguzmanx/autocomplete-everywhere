import { TransformSettingsSchema, TransformInputSchema, personalizationEditSchema } from "@autocompletion/protocol";
import { shortcutSchema, interactionShortcutSchema } from "./suggestion-shortcut";
import { z } from "zod";
import { appIdSchema, writingPreferencesSchema } from "./product-preferences";
import { libraryInputSchema, libraryImportSchema } from "./local-library";

const payloads = {
  context_set_enabled:z.object({enabled:z.boolean()}).strict(),
  context_set_visual_enabled:z.object({enabled:z.boolean()}).strict(),
  context_unpin:z.object({id:z.string().min(1).max(512)}).strict(),
  context_search:z.object({query:z.string().max(2000)}).strict(),
  context_history_more:z.null(),context_history_previous:z.null(),
  context_delete:z.object({id:z.string().min(1).max(512)}).strict(),
  context_pin:z.object({id:z.string().min(1).max(512)}).strict(),
  context_add_reference:z.object({text:z.string().trim().min(1).max(16000)}).strict(),
  context_connect:z.object({provider:z.enum(["github","figma"])}).strict(),
  context_disconnect:z.object({provider:z.enum(["github","figma"])}).strict(),
  context_request_screen_permission:z.null(),
  context_clear:z.null(),context_refresh:z.null(),
  saveTransforms:TransformSettingsSchema, previewTransform:TransformInputSchema, getDefaultTransforms:z.null(),
  ready:z.null(), resume:z.null(), beginSignIn:z.null(), signOut:z.null(), openManageAccount:z.null(), restartHelper:z.null(),
  setShortcut:shortcutSchema.nullable(), setShortcutRecording:z.boolean(),
  setInteractionShortcut:z.object({action:z.enum(["accept", "dismiss"]),shortcut:interactionShortcutSchema}).strict(),
  pause:z.enum(["15m","30m","1h","tomorrow"]), setUiLanguage:z.enum(["en","es"]),
  saveWriting:writingPreferencesSchema.extend({personalization:personalizationEditSchema}).strict(),
  setAppEnabled:z.object({appId:appIdSchema,enabled:z.boolean()}).strict(),
  openMacPermissionSettings:z.enum(["accessibility","input_monitoring"]),
  librarySave:libraryInputSchema, libraryDelete:z.object({id:z.string().uuid(),revision:z.number().int().positive()}).strict(),
  libraryImport:libraryImportSchema, setExerciseActive:z.boolean(), requestExerciseSuggestion:z.null(),
} as const;
export type NativeAction = keyof typeof payloads;
export type NativeRequest = { [K in NativeAction]: {id:string;action:K;payload:z.infer<typeof payloads[K]>} }[NativeAction];
export function parseNativeRequest(line: string): NativeRequest {
  if (Buffer.byteLength(line)>100_000) throw new Error("Request too large");
  const header=z.object({id:z.string().min(1).max(80),action:z.string(),payload:z.unknown()}).strict().parse(JSON.parse(line));
  if (!Object.hasOwn(payloads,header.action)) throw new Error("Unknown action");
  return {...header,payload:payloads[header.action as NativeAction].parse(header.payload)} as NativeRequest;
}
