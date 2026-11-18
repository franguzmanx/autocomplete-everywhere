import { createHash, randomUUID } from "node:crypto";
import { join } from "node:path";
import { z } from "zod";
import {
  personalizationEditSchema, personalizationSnapshotSchema, preferenceValueSchema,
  preferenceExtractionRequestSchema, preferenceExtractionResponseSchema,
  type PersonalizationEdit, type PersonalizationSnapshot, type StylePreference,
  type PreferenceExtractionRequest, type PreferenceExtractionResponse,
} from "@autocompletion/protocol";

const MINUTE = 60_000;
const TTL = 5 * MINUTE;
const INTERVAL = 15 * MINUTE;
const EMPTY: PersonalizationSnapshot = { enabled: false, revision: 0, preferences: [] };
type Observation = PreferenceExtractionRequest["observations"][number] & { receivedAt: number };
const candidateSchema = z.object({
  trait: preferenceValueSchema, appId: z.string().min(1).max(255),
  observations: z.array(z.string().uuid()).max(3), sessions: z.array(z.string().uuid()).max(3),
}).strict();
const persistedSchema = z.object({
  snapshot: personalizationSnapshotSchema, candidates: z.array(candidateSchema).max(72),
  seen: z.array(z.string().uuid()).max(256), attempts: z.array(z.number().int().nonnegative()).max(24),
}).strict();
type Persisted = z.infer<typeof persistedSchema>;
export interface LearningStore { read(): Promise<unknown>; write(value: unknown, signal?: AbortSignal): Promise<void> }
type Options = {
  storeForAccount(subject: string): LearningStore;
  extract(input: PreferenceExtractionRequest, signal: AbortSignal): Promise<PreferenceExtractionResponse>;
  changed(snapshot: PersonalizationSnapshot): void;
  now?: () => number;
  schedule?: (callback: () => void, delay: number) => ReturnType<typeof setTimeout>;
  cancelTimer?: (timer: ReturnType<typeof setTimeout>) => void;
};
export function learningFileForAccount(root: string, subject: string): string {
  return join(root, `learning-${createHash("sha256").update(subject).digest("hex")}.bin`);
}
function empty(): Persisted { return { snapshot: structuredClone(EMPTY), candidates: [], seen: [], attempts: [] }; }

/** Raw corrections only live in this bounded RAM queue and one cancellable call. */
export class LearningService {
  private subject: string | null = null;
  private allowed = false;
  private excluded = new Set<string>();
  private store: LearningStore | null = null;
  private data = empty();
  private loaded = false;
  private epoch = 0;
  private accountRevision = 0;
  private activityRevision = 0;
  private lastActivity: number;
  private pending: Promise<unknown> = Promise.resolve();
  private observations: Observation[] = [];
  private activeBatch: Observation[] = [];
  private requests = new Map<string, {appId: string; registeredAt: number; acceptedAt: number | null}>();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private inFlight: AbortController | null = null;
  private disposed = false;
  private suspended = false;
  constructor(private readonly options: Options) { this.lastActivity = this.now(); }
  private now(): number { return (this.options.now ?? Date.now)(); }
  get observationEnabled(): boolean { return this.eligible(); }
  snapshot(): PersonalizationSnapshot { return structuredClone(this.data.snapshot); }
  private publish(): void { this.options.changed(this.snapshot()); }
  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.pending.then(operation); this.pending = next.catch(() => {}); return next;
  }
  private clearTimer(): void {
    if (this.timer !== undefined) (this.options.cancelTimer ?? clearTimeout)(this.timer);
    this.timer = undefined;
  }
  private invalidate(): void {
    this.epoch++; this.clearTimer(); this.inFlight?.abort(); this.inFlight = null; this.observations = []; this.requests.clear();
  }
  async setEnvironment(subject: string | null, allowed: boolean, excluded: string[]): Promise<void> {
    if (this.disposed) return;
    const accountChanged = subject !== this.subject;
    const boundaryChanged = allowed !== this.allowed || [...new Set(excluded)].sort().join("\n") !== [...this.excluded].sort().join("\n");
    this.allowed = allowed; this.excluded = new Set(excluded);
    if (!accountChanged) {
      if (boundaryChanged) this.invalidate();
      this.arm(); return;
    }
    this.accountRevision++; this.invalidate(); this.subject = subject; this.loaded = false; this.data = empty();
    this.suspended = false; this.store = subject ? this.options.storeForAccount(subject) : null;
    this.publish();
    const store = this.store;
    if (!store) return;
    await this.enqueue(async () => {
      const raw = await store.read();
      if (this.store !== store) return;
      this.data = raw === null ? empty() : persistedSchema.parse(raw);
      this.loaded = true; this.publish(); this.arm();
    });
  }
  userActivity(): void {
    this.lastActivity = this.now(); this.activityRevision++;
    this.inFlight?.abort(); this.inFlight = null;
    this.clearTimer(); this.arm();
  }
  registerRequest(id: string, appId: string): void {
    this.userActivity();
    if (!this.eligible() || this.excluded.has(appId)) return;
    this.requests.set(id, {appId, registeredAt: this.now(), acceptedAt: null});
    while (this.requests.size > 128) this.requests.delete(this.requests.keys().next().value!);
  }
  interaction(id: string, outcome: string): void {
    const request = this.requests.get(id);
    if (!request) return;
    if (outcome === "accepted_full" || outcome === "accepted_partial") {
      if (this.eligible() && this.now() - request.registeredAt <= MINUTE && request.acceptedAt === null) request.acceptedAt = this.now();
    } else if (["removed_after_acceptance", "observation_unavailable", "failed", "stale", "dismissed"].includes(outcome)) this.requests.delete(id);
  }
  observe(id: string, payload: { appId: string; sessionId: string; before: string; after: string; observedAtMs: number }): void {
    if (!this.eligible() || this.excluded.has(payload.appId)) return;
    const now = this.now();
    const accepted = this.requests.get(id);
    if (!accepted || accepted.acceptedAt === null || accepted.appId !== payload.appId || now - accepted.acceptedAt > 35_000 || payload.observedAtMs < accepted.acceptedAt) return;
    this.requests.delete(id);
    if (!Number.isSafeInteger(payload.observedAtMs) || payload.observedAtMs > now + 1_000 || now - payload.observedAtMs >= TTL) return;
    const result = preferenceExtractionRequestSchema.safeParse({ observations: [{ id, sessionId: payload.sessionId, appId: payload.appId, before: payload.before, after: payload.after }] });
    if (!result.success) return;
    this.prune();
    if (this.data.seen.includes(id) || this.observations.some(o => o.id === id)) return;
    this.observations.push({ ...result.data.observations[0]!, receivedAt: payload.observedAtMs });
    const capacity = 12 - this.activeBatch.length;
    this.observations = capacity > 0 ? this.observations.slice(-capacity) : []; this.arm();
  }
  preferencesForApp(appId: string): StylePreference[] {
    if (!this.eligible() || this.excluded.has(appId)) return [];
    const matching = this.data.snapshot.preferences.filter(p => p.appId === appId || (p.origin === "explicit" && p.appId === null));
    // Explicit user choices resolve a dimension before learned app preferences.
    return ["concision", "formality", "structure"].flatMap(dimension => {
      const items = matching.filter(p => p.dimension === dimension);
      const item = items.find(p => p.origin === "explicit" && p.appId === appId)
        ?? items.find(p => p.origin === "explicit") ?? items[0];
      return item ? [structuredClone(item)] : [];
    });
  }
  async save(input: PersonalizationEdit, saveControls: () => Promise<void> = async () => {}): Promise<PersonalizationSnapshot> {
    const patch = personalizationEditSchema.parse(input);
    if (patch.accountSubject !== (this.subject ?? "")) throw new Error("Account changed. Reopen Writing settings.");
    // Disable/reset immediately stops capture and extraction, even while saving.
    if (!patch.enabled || patch.reset) { this.suspended = true; this.invalidate(); this.publish(); }
    const subject = this.subject, accountRevision = this.accountRevision;
    return this.enqueue(async () => {
      if (accountRevision !== this.accountRevision || subject !== this.subject || patch.accountSubject !== (this.subject ?? "")) throw new Error("Account changed. Reopen Writing settings.");
      if (!subject) { await saveControls(); if (accountRevision !== this.accountRevision || this.subject !== null) throw new Error("Account changed. Reopen Writing settings."); return structuredClone(EMPTY); }
      if (!this.loaded || !this.store) throw new Error("Personalization is not available. Reopen Writing settings.");
      const store = this.store;
      const next = structuredClone(this.data);
      const known = new Map(next.snapshot.preferences.map(p => [p.id, p]));
      if (patch.edits.some(p => !known.has(p.id) || known.get(p.id)!.dimension !== p.dimension)) throw new Error("Preference changed. Reopen Writing settings.");
      if (patch.reset && patch.edits.length) throw new Error("Reset cannot include preference edits.");
      if (patch.reset) { next.candidates = []; next.snapshot.preferences = []; next.seen = []; }
      else {
        const removed = next.snapshot.preferences.filter(p => patch.forgetIds.includes(p.id));
        next.snapshot.preferences = next.snapshot.preferences.filter(p => !patch.forgetIds.includes(p.id));
        next.candidates = next.candidates.filter(c => !removed.some(p => (p.appId === null || p.appId === c.appId) && p.dimension === c.trait.dimension));
        for (const change of patch.edits) {
          if (patch.forgetIds.includes(change.id)) throw new Error("A forgotten preference cannot also be edited.");
          next.snapshot.preferences = next.snapshot.preferences.map(p => p.id === change.id ? { ...change, origin: "explicit" as const } : p);
        }
      }
      next.snapshot.enabled = patch.enabled; next.snapshot.revision++;
      persistedSchema.parse(next);
      await saveControls();
      if (accountRevision !== this.accountRevision || subject !== this.subject || store !== this.store) throw new Error("Writing controls saved. Account changed before personalization was saved.");
      try { await store.write(next); }
      catch { throw new Error("Writing controls saved. Personalization could not be saved. Try again."); }
      if (accountRevision !== this.accountRevision || subject !== this.subject || store !== this.store) throw new Error("Account changed. Reopen Writing settings.");
      this.data = next; this.suspended = false; this.publish(); this.arm(); return this.snapshot();
    });
  }
  dispose(): void { this.disposed = true; this.invalidate(); this.data = empty(); this.subject = null; this.store = null; }
  private eligible(): boolean { return !this.disposed && !this.suspended && this.loaded && this.allowed && this.subject !== null && this.data.snapshot.enabled; }
  private prune(): void { const now = this.now(); this.observations = this.observations.filter(o => now - o.receivedAt < TTL && !this.excluded.has(o.appId)); }
  private arm(): void {
    this.clearTimer(); this.prune();
    if (!this.eligible() || this.inFlight || !this.observations.length) return;
    const now = this.now();
    const lastAttempt = this.data.attempts.at(-1) ?? -Infinity;
    const today = Math.floor(now / 86_400_000);
    const todayCount = this.data.attempts.filter(t => Math.floor(t / 86_400_000) === today).length;
    const earliest = Math.max(this.lastActivity + 30_000, lastAttempt + INTERVAL, todayCount >= 12 ? (today + 1) * 86_400_000 : now);
    const expiry = Math.min(...this.observations.map(o => o.receivedAt + TTL));
    this.timer = (this.options.schedule ?? setTimeout)(() => { this.timer = undefined; if (this.now() >= earliest) void this.extract(); else this.arm(); }, Math.max(1, Math.min(earliest, expiry) - now));
  }
  private async extract(): Promise<void> {
    this.prune(); if (!this.eligible() || this.inFlight || !this.observations.length) return;
    const epoch = this.epoch, activity = this.activityRevision, store = this.store!;
    const controller = new AbortController(); this.inFlight = controller;
    const batch = this.observations.splice(0, 6); this.activeBatch = batch;
    const input = { observations: batch.map(({ receivedAt: _, ...o }) => o) };
    const wipe = () => { for (const o of [...batch, ...input.observations]) { o.before = ""; o.after = ""; } if (this.activeBatch === batch) this.activeBatch = []; };
    controller.signal.addEventListener("abort", wipe, {once: true});
    const expiryTimer = (this.options.schedule ?? setTimeout)(() => controller.abort(), Math.max(1, Math.min(...batch.map(o => o.receivedAt + TTL)) - this.now()));
    const valid = () => this.epoch === epoch && this.activityRevision === activity && this.store === store && this.eligible() && !controller.signal.aborted;
    try {
      const permitted = await this.enqueue(async () => {
        if (!valid() || this.now() - this.lastActivity < 30_000) return false;
        const now = this.now(), day = Math.floor(now / 86_400_000);
        if (now - (this.data.attempts.at(-1) ?? -Infinity) < INTERVAL || this.data.attempts.filter(t => Math.floor(t / 86_400_000) === day).length >= 12) return false;
        const next = structuredClone(this.data);
        next.attempts = [...next.attempts.filter(t => now - t < 2 * 86_400_000), now].slice(-24);
        next.seen = [...new Set([...next.seen, ...batch.map(o => o.id)])].slice(-256);
        await store.write(next);
        // Budget remains persisted even if input resumes during this write.
        if (this.store === store) this.data = next;
        return valid();
      });
      if (!permitted || !valid() || batch.some(o => this.now() - o.receivedAt >= TTL)) return;
      const result = preferenceExtractionResponseSchema.parse(await this.options.extract(input, controller.signal));
      if (!valid() || batch.some(o => this.now() - o.receivedAt >= TTL)) return;
      const byId = new Map(batch.map(o => [o.id, o]));
      if (result.evidence.some(e => !byId.has(e.observationId))) return;
      await this.enqueue(async () => {
        if (!valid()) return;
        const next = structuredClone(this.data);
        for (const evidence of result.evidence) {
          const o = byId.get(evidence.observationId)!;
          if (next.snapshot.preferences.some(p => p.origin === "explicit" && p.dimension === evidence.dimension && (p.appId === null || p.appId === o.appId))) continue;
          let candidate = next.candidates.find(c => c.appId === o.appId && c.trait.dimension === evidence.dimension && c.trait.value === evidence.value);
          if (!candidate) { candidate = { appId: o.appId, trait: { dimension: evidence.dimension, value: evidence.value } as z.infer<typeof preferenceValueSchema>, observations: [], sessions: [] }; next.candidates.push(candidate); }
          candidate.observations = [...new Set([...candidate.observations, o.id])].slice(-3);
          candidate.sessions = [...new Set([...candidate.sessions, o.sessionId])].slice(-3);
          if (candidate.observations.length >= 3 && candidate.sessions.length >= 2) {
            const existing = next.snapshot.preferences.find(p => p.appId === o.appId && p.dimension === evidence.dimension);
            if (existing) Object.assign(existing, candidate.trait);
            else if (next.snapshot.preferences.length < 24) next.snapshot.preferences.push({ id: randomUUID(), appId: o.appId, origin: "learned", ...candidate.trait });
          }
        }
        next.candidates = next.candidates.slice(-72);
        next.snapshot.revision++;
        const previous = this.data;
        await store.write(persistedSchema.parse(next), controller.signal);
        if (!valid()) { await store.write(previous); return; }
        this.data = next; this.publish();
      });
    } catch { /* A failed/cancelled attempt is spent; snippets are discarded, never logged or retried. */ }
    finally { (this.options.cancelTimer ?? clearTimeout)(expiryTimer); wipe(); if (this.inFlight === controller) this.inFlight = null; this.arm(); }
  }
}
