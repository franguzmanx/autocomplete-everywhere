import { DEFAULT_SHORTCUT, DEFAULT_ACCEPT_SHORTCUT, DEFAULT_DISMISS_SHORTCUT, shortcutSchema, interactionShortcutSchema, sameShortcut, isReservedShortcut, shortcutShapeSchema } from "./suggestion-shortcut";
import type { SuggestionKeyBinding } from "../shared/contracts";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { z } from "zod";
import type { PauseChoice, UiLanguage } from "../shared/contracts";
import { ProductState } from "./state";

export const appIdSchema = z.string().min(1).max(255).regex(/^[A-Za-z0-9._-]+$/);
export const writingPreferencesSchema = z.object({
  automaticSuggestions: z.boolean(),
  timing: z.enum(["instant", "quick", "balanced", "deliberate"]),
  visibility: z.enum(["subtle", "clear"]),
}).strict();
export type WritingPreferences = z.infer<typeof writingPreferencesSchema>;
const preferencesSchema = z.object({
  shortcut: shortcutSchema.nullable().default(DEFAULT_SHORTCUT),
  acceptShortcut: interactionShortcutSchema.default(DEFAULT_ACCEPT_SHORTCUT),
  dismissShortcut: interactionShortcutSchema.default(DEFAULT_DISMISS_SHORTCUT),
  pausedUntil: z.number().int().positive().nullable(),
  automaticSuggestions: z.boolean(),
  apps: z.record(appIdSchema, z.boolean()),
  uiLanguage: z.enum(["en", "es"]).default("en"),
  timing: z.enum(["instant", "quick", "balanced", "deliberate"]).default("balanced"),
  visibility: z.enum(["subtle", "clear"]).default("subtle"),
}).refine(value => !sameShortcut(value.acceptShortcut, value.dismissShortcut)
  && !sameShortcut(value.shortcut, value.acceptShortcut)
  && !sameShortcut(value.shortcut, value.dismissShortcut), "Shortcut already used by another action");
type Preferences = z.infer<typeof preferencesSchema>;

export class ReservedShortcutPreferencesError extends Error {
  constructor() { super("Saved shortcuts overlap reserved Autocomplete Everywhere actions"); }
}

/** Repair is offered only when every other saved preference is valid. */
function reservedShortcutRepair(input: unknown): Preferences | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  const raw = input as Record<string, unknown>;
  let reserved = false;
  const bindings: Array<SuggestionKeyBinding | null> = [];
  for (const field of ["shortcut", "acceptShortcut", "dismissShortcut"] as const) {
    const value = raw[field];
    const normal = preferencesSchema.shape[field].safeParse(value);
    if (normal.success) { bindings.push(normal.data); continue; }
    const shape = shortcutShapeSchema.safeParse(value);
    if (!shape.success || !isReservedShortcut(shape.data)) return null;
    reserved = true;
    bindings.push(shape.data);
  }
  if (!reserved || bindings.some((binding, index) => bindings.slice(index + 1).some(other => sameShortcut(binding, other)))) return null;
  const repaired = preferencesSchema.safeParse({...raw, shortcut:DEFAULT_SHORTCUT, acceptShortcut:DEFAULT_ACCEPT_SHORTCUT, dismissShortcut:DEFAULT_DISMISS_SHORTCUT});
  return repaired.success ? repaired.data : null;
}


/** Local controls are independent of credentials and never contain captured text. */
export class ProductPreferences {
  private value: Preferences = { pausedUntil: null, automaticSuggestions: true, apps: {}, uiLanguage:"en", timing:"balanced", visibility:"subtle", shortcut:DEFAULT_SHORTCUT, acceptShortcut:DEFAULT_ACCEPT_SHORTCUT, dismissShortcut:DEFAULT_DISMISS_SHORTCUT };
  private pending: Promise<void> = Promise.resolve();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private disposed = false;

  constructor(private readonly path: string, private readonly state: ProductState) {}

  async load(): Promise<void> {
    try {
      const raw: unknown = JSON.parse(await readFile(this.path, "utf8"));
      const parsed = preferencesSchema.safeParse(raw);
      if (!parsed.success) {
        if (reservedShortcutRepair(raw)) throw new ReservedShortcutPreferencesError();
        throw parsed.error;
      }
      this.value = parsed.data;
    }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
    if (this.value.pausedUntil !== null && this.value.pausedUntil <= Date.now()) {
      this.value.pausedUntil = null;
    }
    this.publish();
  }

  /** Called only after the startup dialog's explicit Reset shortcuts choice. */
  resetReservedShortcuts(): Promise<void> {
    return this.update(async () => {
      const repair = reservedShortcutRepair(JSON.parse(await readFile(this.path, "utf8")));
      if (!repair) throw new Error("Saved preferences cannot be repaired by resetting shortcuts");
      return repair;
    });
  }

  resume(): Promise<void> { return this.update(current => ({ ...current, pausedUntil: null })); }

  pause(choice: PauseChoice): Promise<void> {
    z.enum(["15m", "30m", "1h", "tomorrow"]).parse(choice);
    const now = new Date();
    const deadline = choice === "tomorrow"
      ? new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 9).getTime()
      : now.getTime() + ({ "15m":15, "30m":30, "1h":60 }[choice]) * 60_000;
    return this.update(current => ({ ...current, pausedUntil: deadline }));
  }
  setUiLanguage(value: UiLanguage): Promise<void> { z.enum(["en", "es"]).parse(value); return this.update(c => ({ ...c, uiLanguage:value })); }

  setShortcut(shortcut: SuggestionKeyBinding | null): Promise<void> { return this.update(c => ({...c, shortcut})); }

  setInteractionShortcut(action: "accept" | "dismiss", shortcut: SuggestionKeyBinding): Promise<void> {
    return this.update(c => ({...c, [action === "accept" ? "acceptShortcut" : "dismissShortcut"]:shortcut}));
  }

  saveWriting(input: WritingPreferences): Promise<void> {
    const writing = writingPreferencesSchema.parse(input);
    return this.update(current => ({ ...current, ...writing }));
  }

  setAppEnabled(appId: string, enabled: boolean): Promise<void> {
    appIdSchema.parse(appId);
    return this.update(current => ({ ...current, apps: { ...current.apps, [appId]: enabled } }));
  }

  expirePause(): Promise<void> {
    return this.update(current => current.pausedUntil !== null && current.pausedUntil <= Date.now()
      ? { ...current, pausedUntil: null } : current);
  }

  dispose(): void { this.disposed = true; clearTimeout(this.timer); }

  private update(change: (current: Preferences) => Preferences | Promise<Preferences>): Promise<void> {
    const next = this.pending.then(async () => {
      const value = preferencesSchema.parse(await change(this.value));
      await mkdir(dirname(this.path), { recursive: true });
      await writeFile(this.path + ".tmp", JSON.stringify(value), { mode: 0o600 });
      await rename(this.path + ".tmp", this.path);
      this.value = value;
      this.publish();
    });
    this.pending = next.catch(() => {});
    return next;
  }

  private publish(): void {
    clearTimeout(this.timer);
    this.state.setPreferences({ ...this.value, enabled: this.value.pausedUntil === null });
    if (!this.disposed && this.value.pausedUntil !== null) {
      this.timer = setTimeout(() => { void this.expirePause().catch(() => {
        // A failed save leaves the product paused; never silently resume it.
      }); }, Math.max(0, this.value.pausedUntil - Date.now()));
    }
  }
}
