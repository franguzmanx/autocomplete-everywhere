import { PreparedContextSchema } from "./context.js";
import { z } from 'zod';

export const TransformSchema = z.object({
  id: z.string().uuid(),
  name: z.string().trim().min(1).max(60),
  shortcut: z.number().int().min(1).max(9),
  rules: z.array(z.enum(['concise', 'clarity', 'reorder', 'structure', 'tone'])).max(5),
  prompt: z.string().trim().max(4000),
  examples: z.array(z.string().trim().min(1).max(4000)).max(3),
}).strict().refine(value => value.rules.length > 0 || value.prompt.length > 0);
export type Transform = z.infer<typeof TransformSchema>;
export const TransformSettingsSchema = z.object({
  enabled: z.boolean(),
  transforms: z.array(TransformSchema).max(9),
}).strict().refine(({ transforms }) =>
  new Set(transforms.map(t => t.id)).size === transforms.length &&
  new Set(transforms.map(t => t.shortcut)).size === transforms.length,
  'Each transform needs a unique shortcut and identity',
);
export type TransformSettings = z.infer<typeof TransformSettingsSchema>;
export const TransformInputSchema = z.object({
  text: z.string().min(1).max(2000).refine(text => text.trim().length > 0),
  transform: TransformSchema,
  singleLine: z.boolean(),
  preparedContext: PreparedContextSchema.optional(),
}).strict();
export type TransformInput = z.infer<typeof TransformInputSchema>;
export const TransformOutputSchema = z.object({
  text: z.string().min(1).max(8000).refine(text => text.trim().length > 0 && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(text)),
}).strict();

export { TRANSFORM_RULES, defaultTransformSettings } from "./transform-presets.js";
