import { isReservedShortcut } from "@autocompletion/protocol";
export { isReservedShortcut } from "@autocompletion/protocol";
import { z } from "zod";
import type { SuggestionKeyBinding } from "../shared/contracts";

export const DEFAULT_SHORTCUT: SuggestionKeyBinding = {
  accelerator: "Command+Shift+Space", keyCode: 49, modifiers: 768,
};
export const DEFAULT_ACCEPT_SHORTCUT: SuggestionKeyBinding = { accelerator:"Tab", keyCode:48, modifiers:0 };
export const DEFAULT_DISMISS_SHORTCUT: SuggestionKeyBinding = { accelerator:"Escape", keyCode:53, modifiers:0 };
export function sameShortcut(a: SuggestionKeyBinding | null, b: SuggestionKeyBinding | null): boolean {
  return !!a && !!b && a.keyCode === b.keyCode && a.modifiers === b.modifiers;
}
export const shortcutShapeSchema = z.object({
  accelerator: z.string().max(80).regex(/^(?:(?:Command|Control|Alt|Shift)\+)+(?:[A-Z0-9]|Space|Enter|Tab|Escape|Backspace|Delete|Up|Down|Left|Right|Home|End|PageUp|PageDown|F(?:[1-9]|1[0-9]|20))$/)
    .refine(value => /(?:^|\+)(Command|Control|Alt)\+/.test(value)),
  keyCode: z.number().int().min(0).max(127),
  modifiers: z.number().int().min(1).max(6912).refine(value => (value & ~6912) === 0),
}).strict();
export const shortcutSchema = shortcutShapeSchema.refine(binding => !isReservedShortcut(binding), "Option+Tab, Option+Up/Down and Option+1–9 are reserved for Autocomplete Everywhere actions");

export const interactionShortcutSchema = z.union([
  shortcutSchema,
  z.object({accelerator:z.literal("Tab"),keyCode:z.literal(48),modifiers:z.literal(0)}).strict(),
  z.object({accelerator:z.literal("Escape"),keyCode:z.literal(53),modifiers:z.literal(0)}).strict(),
  z.object({accelerator:z.literal("Enter"),keyCode:z.literal(36),modifiers:z.literal(0)}).strict(),
  z.object({accelerator:z.literal("Right"),keyCode:z.literal(124),modifiers:z.literal(0)}).strict(),
]);

type Registrar = { register(value: string, action: () => void): boolean; unregister(value: string): void };
/** Register the candidate first: conflicts or disk failures preserve the working shortcut. */
export class SuggestionShortcut {
  private active: string | null = null;
  private recording = false;
  private pending: Promise<void> = Promise.resolve();
  constructor(private readonly registrar: Registrar, private readonly action: () => void) {}
  start(binding: SuggestionKeyBinding | null): boolean {
    if (!binding) return true;
    shortcutSchema.parse(binding);
    if (!this.registrar.register(binding.accelerator, this.action)) return false;
    this.active = binding.accelerator;
    return true;
  }
  setRecording(recording: boolean): Promise<void> {
    const next = this.pending.then(() => {
      if (recording === this.recording) return;
      if (this.active) {
        if (recording) this.registrar.unregister(this.active);
        else if (!this.registrar.register(this.active, this.action)) throw new Error("Shortcut unavailable");
      }
      this.recording = recording;
    });
    this.pending = next.catch(() => {});
    return next;
  }
  change(binding: SuggestionKeyBinding | null, save: () => Promise<void>): Promise<void> {
    const next = this.pending.then(async () => {
      if (!binding) {
        await save();
        if (this.active) this.registrar.unregister(this.active);
        this.active = null;
        return;
      }
      shortcutSchema.parse(binding);
      if (binding.accelerator === this.active) { await save(); return; }
      if (!this.registrar.register(binding.accelerator, this.action)) throw new Error("Shortcut unavailable");
      try { await save(); }
      catch (error) { this.registrar.unregister(binding.accelerator); throw error; }
      if (this.active) this.registrar.unregister(this.active);
      this.active = binding.accelerator;
      if (this.recording) this.registrar.unregister(this.active);
    });
    this.pending = next.catch(() => {});
    return next;
  }
}
