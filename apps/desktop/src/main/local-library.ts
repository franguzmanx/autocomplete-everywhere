import { randomUUID } from "node:crypto";
import { z } from "zod";
import { knowledgeKindSchema, knowledgeScopeSchema, type KnowledgeCandidate } from "@autocompletion/protocol";
import type { LibraryEntry, LibraryInput } from "../shared/contracts";

const libraryInputFields = z.object({
  id: z.string().uuid().optional(),
  expectedRevision: z.number().int().positive().optional(),
  title: z.string().trim().min(1).max(120),
  kind: knowledgeKindSchema,
  text: z.string().min(1).max(12_000).refine(text => text.trim().length > 0),
  scope: knowledgeScopeSchema,
  expiresAt: z.number().int().nonnegative().nullable(),
}).strict();
export const libraryImportSchema = libraryInputFields.omit({ text: true });
export const libraryInputSchema = libraryInputFields.refine(value => value.kind === "style" || (value.scope.appIds.length > 0 && /[\p{L}\p{N}]{3}/u.test(value.scope.anchor)), "Choose an application and a specific topic or recipient anchor").refine(value => Boolean(value.id) === Boolean(value.expectedRevision), "An edit must specify its revision");
const entrySchema = z.object({
  id: z.string().uuid(), title: z.string().trim().min(1).max(120), kind: knowledgeKindSchema,
  text: z.string().min(1).max(12_000), scope: knowledgeScopeSchema,
  revision: z.number().int().positive(), createdAt: z.number().int().nonnegative(), updatedAt: z.number().int().nonnegative(),
  expiresAt: z.number().int().nonnegative().nullable(),
  provenance: z.discriminatedUnion("kind", [z.object({ kind: z.literal("user") }).strict(), z.object({ kind: z.literal("file"), name: z.string().min(1).max(255) }).strict()]),
}).strict().refine(value => value.kind === "style" || (value.scope.appIds.length > 0 && /[\p{L}\p{N}]{3}/u.test(value.scope.anchor)));
const storedSchema = z.object({ entries: z.array(entrySchema).max(100) }).strict().refine(value => new Set(value.entries.map(entry => entry.id)).size === value.entries.length && value.entries.reduce((sum, entry) => sum + entry.text.length, 0) <= 500_000);
const normalized = (value: string): string => value.normalize("NFKC").toLocaleLowerCase().replace(/\s+/gu, " ").trim();
const tokens = (value: string): Set<string> => new Set(normalized(value).match(/[\p{L}\p{N}]+/gu) ?? []);
function containsAnchor(text: string, anchor: string): boolean {
  const needle = normalized(anchor);
  if (!needle) return true;
  let offset = text.indexOf(needle);
  while (offset >= 0) {
    const before = text.slice(0, offset).at(-1) ?? "";
    const after = text.slice(offset + needle.length)[0] ?? "";
    if (!/[\p{L}\p{N}]/u.test(before) && !/[\p{L}\p{N}]/u.test(after)) return true;
    offset = text.indexOf(needle, offset + 1);
  }
  return false;
}
export interface LibraryStorage { read<T>(): Promise<T | null>; write(value: unknown): Promise<void> }

/** Explicit user sources only. No disk, model, network, or renderer access during selection. */
export class LocalLibrary {
  private entries: LibraryEntry[] = [];
  private index: { entry: LibraryEntry; terms: Set<string> }[] = [];
  private pending: Promise<unknown> = Promise.resolve();
  private ready = false;
  private expirationTimer: ReturnType<typeof setTimeout> | undefined;
  private expiredIds = new Set<string>();
  constructor(private readonly storage: LibraryStorage, private readonly onChanged: () => void) {}
  async load(): Promise<void> {
    const stored = await this.storage.read<unknown>();
    this.publish(stored === null ? [] : storedSchema.parse(stored).entries);
    this.ready = true;
  }
  private publish(entries: LibraryEntry[]): void {
    this.entries = entries;
    this.index = entries.map(entry => ({ entry, terms: tokens(`${entry.title} ${entry.text}`) }));
    this.expiredIds = new Set(entries.filter(entry => entry.expiresAt !== null && entry.expiresAt <= Date.now()).map(entry => entry.id));
    this.scheduleExpiration();
  }
  private scheduleExpiration(): void {
    if (this.expirationTimer) clearTimeout(this.expirationTimer);
    const next = Math.min(...this.entries.filter(entry => entry.expiresAt !== null && !this.expiredIds.has(entry.id)).map(entry => entry.expiresAt!));
    if (!Number.isFinite(next)) return;
    this.expirationTimer = setTimeout(() => this.expire(), Math.max(1, Math.min(next - Date.now(), 2_147_483_647)));
    this.expirationTimer.unref();
  }
  expire(): void {
    const newlyExpired = this.entries.filter(entry => entry.expiresAt !== null && entry.expiresAt <= Date.now() && !this.expiredIds.has(entry.id));
    for (const entry of newlyExpired) this.expiredIds.add(entry.id);
    if (newlyExpired.length) this.onChanged();
    this.scheduleExpiration();
  }
  unload(): void { this.ready=false; this.entries=[]; this.index=[]; this.dispose(); }
  dispose(): void { if (this.expirationTimer) clearTimeout(this.expirationTimer); }
  list(): LibraryEntry[] {
    if (!this.ready) throw new Error("Library is unavailable. Restart Autocomplete Everywhere to try again.");
    return structuredClone(this.entries);
  }
  private mutate<T>(action: () => Promise<T>): Promise<T> {
    const operation = this.pending.then(() => {
      if (!this.ready) throw new Error("Library is unavailable");
      return action();
    });
    this.pending = operation.catch(() => {});
    return operation;
  }
  upsert(raw: LibraryInput, provenance: LibraryEntry["provenance"] = { kind: "user" }): Promise<LibraryEntry> {
    return this.mutate(async () => {
      const input = libraryInputSchema.parse(raw);
      const previous = input.id ? this.entries.find(entry => entry.id === input.id) : undefined;
      if (input.id && (!previous || previous.revision !== input.expectedRevision)) throw new Error("This source changed. Reload the library before editing.");
      const now = Date.now();
      const entry: LibraryEntry = entrySchema.parse({ id: previous?.id ?? randomUUID(), title: input.title, kind: input.kind, text: input.text, scope: input.scope, expiresAt: input.expiresAt, revision: (previous?.revision ?? 0) + 1, createdAt: previous?.createdAt ?? now, updatedAt: now, provenance });
      const entries = [...this.entries.filter(item => item.id !== entry.id), entry];
      storedSchema.parse({ entries });
      await this.storage.write({ entries });
      if(this.ready){ this.publish(entries); this.onChanged(); }
      return structuredClone(entry);
    });
  }
  delete(id: string, expectedRevision: number): Promise<void> {
    return this.mutate(async () => {
      z.string().uuid().parse(id); z.number().int().positive().parse(expectedRevision);
      const entry = this.entries.find(item => item.id === id);
      if (!entry || entry.revision !== expectedRevision) throw new Error("This source changed. Reload the library before deleting.");
      const entries = this.entries.filter(item => item.id !== id);
      await this.storage.write({ entries }); if(this.ready){ this.publish(entries); this.onChanged(); }
    });
  }
  select(input: { appId: string; text: string }): KnowledgeCandidate[] {
    if (!this.ready) return [];
    const text = normalized(input.text.slice(0, 32_000));
    const query = tokens(text); const now = Date.now();
    const admissible = this.index.filter(({ entry }) =>
      (entry.expiresAt === null || entry.expiresAt > now) &&
      (entry.scope.appIds.includes(input.appId) || (entry.kind === "style" && entry.scope.appIds.length === 0)) &&
      containsAnchor(text, entry.scope.anchor));
    const ranked = admissible.map(item => ({ ...item, score: [...query].reduce((score, term) => score + Number(item.terms.has(term)), 0) })).sort((a, b) => b.score - a.score || b.entry.updatedAt - a.entry.updatedAt);
    const selected: KnowledgeCandidate[] = []; let remaining = 12_000;
    for (const { entry } of ranked) {
      if (selected.length === 6) break;
      if (entry.text.length > remaining) continue;
      const { id, title, kind, text, revision, updatedAt, expiresAt, scope } = entry;
      selected.push({ sourceId: id, title, kind, text, revision, updatedAt, expiresAt, scope: structuredClone(scope) });
      remaining -= text.length;
    }
    return selected;
  }
}
