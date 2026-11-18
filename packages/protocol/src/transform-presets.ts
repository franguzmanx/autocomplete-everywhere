import type { TransformSettings } from "./transforms.js";

export const TRANSFORM_RULES = {
  concise: 'Cut repetition and empty wording without losing useful details or personality',
  clarity: 'Fix errors and unclear passages; leave clear sentences alone',
  reorder: 'Reorder only when the current progression is confusing',
  structure: 'Untangle difficult sentences while preserving the existing formatting',
  tone: 'Preserve my vocabulary, rhythm, humor, bluntness and uncertainty',
} as const;

export function defaultTransformSettings(): TransformSettings {
  return { enabled: false, transforms: [
    { id: 'c611fc31-91e3-4172-a74d-2c90e359c001', name: 'Polish', shortcut: 1,
      rules: ['concise', 'clarity', 'reorder', 'structure', 'tone'], prompt: '', examples: [] },
    { id: 'c611fc31-91e3-4172-a74d-2c90e359c002', name: 'Improve prompt', shortcut: 2,
      rules: [], prompt: 'Rewrite as a clear, effective prompt. Clarify the objective, constraints and requested output. Preserve intent; never invent requirements or answer the prompt.', examples: [] },
    { id: 'c611fc31-91e3-4172-a74d-2c90e359c003', name: 'Improve text', shortcut: 3,
      rules: ['clarity', 'tone'], prompt: 'Correct spelling and grammar while preserving meaning and language.', examples: [] },
  ] };
}
