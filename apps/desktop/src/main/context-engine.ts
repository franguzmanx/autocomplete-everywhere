import { observedResources, type ContextProvider } from "./context-connectors";
import { createHash, randomUUID } from "node:crypto";
import {
  EvidenceSchema,
  PreparedContextSchema,
  type Evidence,
  type PreparedContext,
  type ProtocolMessage,
} from "@autocompletion/protocol";
export type ContextRow = {
  id: string;
  title: string;
  detail: string;
  excerpt: string;
};
export type ContextSnapshot = {
  enabled: boolean;
  semanticStatus: "not_prepared" | "ready" | "unavailable";
  historyPage: number;
  history: ContextRow[];
  connections: ContextRow[];
  references: ContextRow[];
  used: ContextRow[];
};
type Store = {
  call<T = unknown>(
    op: string,
    payload?: Record<string, unknown>,
    signal?: AbortSignal,
  ): Promise<T>;
};
type Observation = Extract<
  ProtocolMessage,
  { type: "context_observation" }
>["payload"];
const MONTH = 30 * 24 * 60 * 60 * 1000;
const hash = (text: string) => createHash("sha256").update(text).digest("hex");
const row = (e: Evidence): ContextRow => ({
  id: e.id,
  title: e.text.slice(0, 100),
  detail: `${e.provenance} · ${e.appId} · ${new Date(e.capturedAtMs).toLocaleDateString()}${e.resourceId ? " · " + e.resourceId : ""}`,
  excerpt: e.text.slice(0, 2000),
});
/** Account-scoped orchestration. The only retained image is the latest pending job. */
export class ContextEngine {
  private semanticStatus: "not_prepared" | "ready" | "unavailable" =
    "not_prepared";
  private embeddingRetryAt = 0;
  private subject: string | null = null;
  private enabled = false;
  private allowed = false;
  private exclusions = new Set<string>();
  private epoch = 0;
  private cancellation = new AbortController();
  private ready: Promise<void> = Promise.resolve();
  private envKey = "";
  private history: ContextRow[] = [];
  private references: ContextRow[] = [];
  private used: ContextRow[] = [];
  private dependencies = new Map<string, PreparedContext>();
  private latest = new Map<string, string>();
  private queue = new Map<string, () => Promise<void>>();
  private running = 0;
  private queryCache: {
    key: string;
    query: string;
    appId: string;
    embedding: number[];
  } | null = null;
  private screenCache: { appId: string; text: string; sourceId: string; revision: string; preparedAt: number; embedding: number[] } | null = null;
  private refreshing = false;
  private refreshAgain = false;
  private historyOffset = 0;
  private historyQuery = "";
  private generation = 0;
  private visualEpoch = 0;
  private pendingVisual: (() => Promise<void>) | null = null;
  private visualRunning = false;
  private visualCancellation: AbortController | null = null;
  private resourceReads = new Map<string, number>();
  private queryKey = "";
  private queryCancellation: AbortController | null = null;
  private maintenance: ReturnType<typeof setInterval>;
  private maintaining = false;
  constructor(
    private options: {
      readResource?(
        provider: ContextProvider,
        resourceId: string,
        signal: AbortSignal,
      ): Promise<
        | {
            resourceId: string;
            text: string;
            revision: string;
            capturedAtMs: number;
          }
        | undefined
      >;
      store: Store;
      remote: {
        call<T>(
          path: string,
          payload: unknown,
          signal: AbortSignal,
        ): Promise<T>;
      };
      changed(): void;
      invalidate(ids: string[]): void;
      readEnabled(subject: string): Promise<boolean>;
      writeEnabled(subject: string, value: boolean): Promise<void>;
    },
  ) {
    this.maintenance = setInterval(() => {
      void this.maintain().catch(() => {});
    }, 60000);
    this.maintenance.unref?.();
  }
  async maintain(): Promise<void> {
    if (
      this.maintaining ||
      !this.captureEnabled ||
      Date.now() < this.embeddingRetryAt
    )
      return;
    this.maintaining = true;
    const epoch = this.epoch;
    const signal = this.cancellation.signal;
    try {
      await this.ready;
      if (epoch !== this.epoch || !this.captureEnabled) return;
      await this.options.store.call("expire", {}, signal);
      const pending = await this.options.store.call<{ evidence: Evidence[] }>(
        "pendingEmbeddings",
        { limit: 16 },
        signal,
      );
      if (epoch !== this.epoch) return;
      for (const evidence of pending.evidence)
        if (!this.exclusions.has(evidence.appId))
          this.embed(EvidenceSchema.parse(evidence), epoch);
    } finally {
      this.maintaining = false;
    }
  }
  snapshot(): ContextSnapshot {
    return {
      enabled: this.enabled,
      semanticStatus: this.semanticStatus,
      historyPage: Math.floor(this.historyOffset / 100),
      history: this.history,
      connections: [],
      references: this.references,
      used: this.used,
    };
  }
  get captureEnabled(): boolean {
    return this.enabled && this.allowed && this.subject !== null;
  }
  setEnvironment(
    subject: string | null,
    allowed: boolean,
    excluded: string[],
  ): void {
    const key = JSON.stringify([subject, allowed, [...excluded].sort()]);
    if (key === this.envKey) return;
    this.envKey = key;
    const previousSubject = this.subject;
    const oldExclusions = this.exclusions;
    this.subject = subject;
    this.allowed = allowed;
    this.exclusions = new Set(excluded);
    this.epoch++;
    this.cancellation.abort();
    this.cancellation = new AbortController();
    this.queue.clear();
    this.pendingVisual = null;
    this.visualCancellation?.abort();
    this.resourceReads.clear();
    this.queryCache = null;
    this.screenCache = null;
    this.queryKey = "";
    this.queryCancellation?.abort();
    this.latest.clear();
    this.queryCache = null;
    this.screenCache = null;
    this.queryKey = "";
    this.queryCancellation?.abort();
    this.invalidateAll();
    if (subject !== previousSubject) {
      this.semanticStatus = "not_prepared";
      this.embeddingRetryAt = 0;
      this.enabled = false;
      this.history = [];
      this.references = [];
      this.used = [];
      this.historyOffset = 0;
      this.historyQuery = "";
    }
    const epoch = this.epoch;
    this.ready = this.ready
      .catch(() => {})
      .then(async () => {
        if (epoch !== this.epoch) return;
        if (!subject) {
          await this.options.store.call("close");
          return;
        }
        await this.options.store.call("open", { accountId: subject });
        if (epoch !== this.epoch) return;
        const enabled = await this.options.readEnabled(subject);
        if (epoch !== this.epoch) return;
        this.enabled = enabled;
        for (const appId of this.exclusions)
          if (!oldExclusions.has(appId) || subject !== previousSubject)
            await this.options.store.call("purgeApp", { appId });
        if (epoch === this.epoch) this.options.changed();
      })
      .catch(() => {
        if (epoch === this.epoch) {
          this.enabled = false;
          this.options.changed();
        }
      });
  }
  stopVisual(): void {
    this.visualEpoch++;
    this.pendingVisual = null;
    this.visualCancellation?.abort();
    this.queue.delete("visual");
  }
  async setEnabled(value: boolean): Promise<void> {
    const subject = this.subject;
    if (!subject) throw new Error("Sign in first");
    if (!value) {
      this.enabled = false;
      this.epoch++;
      this.cancellation.abort();
      this.cancellation = new AbortController();
      this.queue.clear();
      this.stopVisual();
      this.invalidateAll();
      this.options.changed();
    }
    const epoch = this.epoch;
    await this.options.writeEnabled(subject, value);
    if (subject !== this.subject || epoch !== this.epoch) return;
    this.enabled = value;
    this.epoch++;
    this.cancellation.abort();
    this.cancellation = new AbortController();
    this.queue.clear();
    this.stopVisual();
    this.resourceReads.clear();
    this.queryCache = null;
    this.screenCache = null;
    this.queryKey = "";
    this.queryCancellation?.abort();
    this.latest.clear();
    this.invalidateAll();
    this.options.changed();
  }
  private invalidateAll(): void {
    this.used = [];
    const ids = [...this.dependencies.keys()];
    this.dependencies.clear();
    if (ids.length) this.options.invalidate(ids);
  }
  private changedSource(sourceId: string, revision?: string): void {
    if (this.screenCache?.sourceId === sourceId && this.screenCache.revision !== revision) this.screenCache = null;
    const ids: string[] = [];
    for (const [id, context] of this.dependencies)
      if (
        context.dependencies.some(
          (d) => d.sourceId === sourceId && d.revision !== revision,
        )
      ) {
        ids.push(id);
        this.dependencies.delete(id);
      }
    if (ids.length) this.options.invalidate(ids);
  }
  private schedule(key: string, job: () => Promise<void>): void {
    if (!this.captureEnabled) return;
    if (this.queue.size >= 32 && !this.queue.has(key))
      this.queue.delete(this.queue.keys().next().value!);
    this.queue.set(key, job);
    this.drain();
  }
  private drain(): void {
    while (this.running < 2 && this.queue.size) {
      const key = this.queue.keys().next().value!;
      const job = this.queue.get(key)!;
      this.queue.delete(key);
      this.running++;
      void job()
        .catch(() => {})
        .finally(() => {
          this.running--;
          this.drain();
        });
    }
  }
  async observe(observation: Observation): Promise<void> {
    if (
      !this.captureEnabled ||
      this.exclusions.has(observation.appId) ||
      !Number.isSafeInteger(observation.capturedAtMs) ||
      observation.capturedAtMs > Date.now() + 1000 ||
      Date.now() - observation.capturedAtMs > 300000
    )
      return;
    const epoch = this.epoch,
      visualEpoch = this.visualEpoch,
      signal = this.cancellation.signal;
    await this.ready;
    if (epoch !== this.epoch || !this.captureEnabled) return;
    const sourceId = hash(`${observation.appId}\0${observation.documentId}`);
    const text = observation.sources
      .map((s) => s.text)
      .join("\n")
      .slice(0, 16000);
    const image = observation.image;
    this.readResources(text, epoch);
    const revision = hash(text + (image ? hash(image.data) : ""));
    if (this.latest.get(sourceId) === revision) return;
    this.latest.set(sourceId, revision);
    this.changedSource(sourceId, revision);
    if (this.latest.size > 256)
      this.latest.delete(this.latest.keys().next().value!);
    if (!text && !image) return;
    // A visual-only source needs an observed anchor, never a fabricated authored fact.
    const evidence: Evidence = EvidenceSchema.parse({
      id: sourceId,
      sourceId,
      revision,
      provenance: "observed",
      appId: observation.appId,
      documentId: observation.documentId,
      capturedAtMs: observation.capturedAtMs,
      expiresAtMs: observation.capturedAtMs + MONTH,
      text: text || "[Visual observation]",
      dependencies: [],
    });
    try {
      await this.options.store.call("put", { evidence }, signal);
    } catch (error) {
      if (this.latest.get(sourceId) === revision) this.latest.delete(sourceId);
      throw error;
    }
    if (epoch !== this.epoch) return;
    this.generation++;
    this.embed(evidence, epoch);
    if (image && visualEpoch === this.visualEpoch) {
      this.visualCancellation?.abort();
      const visualController = new AbortController();
      this.visualCancellation = visualController;
      const visualSignal = AbortSignal.any([signal, visualController.signal]);
      this.pendingVisual = async () => {
        if (
          epoch !== this.epoch ||
          Date.now() - observation.capturedAtMs > 300000
        )
          return;
        const recognized = await this.options.store.call<{ text: string }>(
          "ocr",
          { imageBase64: image.data },
          visualSignal,
        );
        if (
          visualSignal.aborted ||
          visualEpoch !== this.visualEpoch ||
          epoch !== this.epoch ||
          this.latest.get(sourceId) !== revision
        )
          return;
        if (recognized.text?.trim()) {
          const ocr = EvidenceSchema.parse({
            ...evidence,
            id: sourceId + "-ocr",
            sourceId: sourceId + "-ocr",
            text: recognized.text.slice(0, 12000),
            dependencies: [{ sourceId, revision }],
          });
          await this.options.store.call("put", { evidence: ocr }, visualSignal);
          this.embed(ocr, epoch);
        }
        const result = await this.options.remote.call<{ text: string }>(
          "visual",
          { imageBase64: image.data, mimeType: image.mediaType },
          visualSignal,
        );
        if (
          visualSignal.aborted ||
          visualEpoch !== this.visualEpoch ||
          epoch !== this.epoch ||
          this.latest.get(sourceId) !== revision ||
          !result.text?.trim()
        )
          return;
        const derived = EvidenceSchema.parse({
          ...evidence,
          id: sourceId + "-visual",
          sourceId: sourceId + "-visual",
          provenance: "derived",
          text: result.text.slice(0, 16000),
          dependencies: [{ sourceId, revision }],
        });
        await this.options.store.call(
          "put",
          { evidence: derived },
          visualSignal,
        );
        this.generation++;
        this.embed(derived, epoch);
      };
      this.drainVisual();
    }
  }
  private drainVisual(): void {
    if (this.visualRunning || !this.pendingVisual) return;
    this.schedule("visual", async () => {
      if (this.visualRunning) return;
      const job = this.pendingVisual;
      this.pendingVisual = null;
      if (!job) return;
      this.visualRunning = true;
      try {
        await job();
      } finally {
        this.visualRunning = false;
        this.drainVisual();
      }
    });
  }
  private readResources(text: string, epoch: number): void {
    if (!this.options.readResource) return;
    const signal = this.cancellation.signal;
    for (const resource of observedResources(text)) {
      const key = resource.provider + ":" + resource.resourceId;
      const now = Date.now();
      if (now - (this.resourceReads.get(key) ?? 0) < 300000) continue;
      this.resourceReads.set(key, now);
      while (this.resourceReads.size > 128)
        this.resourceReads.delete(this.resourceReads.keys().next().value!);
      this.schedule("resource:" + key, async () => {
        if (epoch !== this.epoch) return;
        const result = await this.options.readResource!(
          resource.provider,
          resource.resourceId,
          signal,
        );
        if (
          !result ||
          epoch !== this.epoch ||
          signal.aborted ||
          result.resourceId !== resource.resourceId ||
          result.capturedAtMs > Date.now() + 1000 ||
          Date.now() - result.capturedAtMs > 300000
        )
          return;
        const sourceId = hash("connector:" + key);
        const evidence = EvidenceSchema.parse({
          id: sourceId,
          sourceId,
          revision: result.revision,
          provenance: "observed",
          appId: "connector." + resource.provider,
          resourceId: resource.resourceId,
          capturedAtMs: result.capturedAtMs,
          expiresAtMs: result.capturedAtMs + MONTH,
          text: result.text,
          dependencies: [],
        });
        this.changedSource(sourceId, evidence.revision);
        await this.options.store.call("put", { evidence }, signal);
        if (epoch === this.epoch) this.embed(evidence, epoch);
      });
    }
  }
  async purgeApp(appId: string): Promise<void> {
    const epoch = this.epoch;
    await this.ready;
    if (epoch !== this.epoch || !this.subject) return;
    this.epoch++;
    this.cancellation.abort();
    this.cancellation = new AbortController();
    this.queue.clear();
    this.pendingVisual = null;
    this.visualCancellation?.abort();
    this.resourceReads.clear();
    const ids = [...this.dependencies]
      .filter(([, context]) => context.evidence.some((e) => e.appId === appId))
      .map(([id]) => id);
    for (const id of ids) this.dependencies.delete(id);
    if (ids.length) this.options.invalidate(ids);
    await this.options.store.call("purgeApp", { appId });
    await this.refresh();
  }
  private async embedding(
    text: string,
    signal: AbortSignal,
  ): Promise<number[] | undefined> {
    if (Date.now() < this.embeddingRetryAt) return;
    const epoch = this.epoch;
    try {
      const result = await this.options.remote.call<{ embedding: number[] }>(
        "embeddings",
        { text },
        signal,
      );
      if (epoch !== this.epoch || signal.aborted) return;
      this.semanticStatus = "ready";
      this.options.changed();
      return result.embedding;
    } catch (error) {
      if (epoch === this.epoch && !signal.aborted) {
        this.semanticStatus = "unavailable";
        this.embeddingRetryAt = Date.now() + 60000;
        this.options.changed();
      }
      throw error;
    }
  }
  private embed(evidence: Evidence, epoch: number): void {
    const signal = this.cancellation.signal;
    this.schedule("embed:" + evidence.id, async () => {
      if (epoch !== this.epoch) return;
      const embedding = await this.embedding(evidence.text, signal);
      if (epoch !== this.epoch || !embedding) return;
      await this.options.store.call(
        "embed",
        { evidenceId: evidence.id, revision: evidence.revision, embedding },
        signal,
      );
      // Reuse indexing work for proactive retrieval only when the request carries
      // the exact same currently observed screen text. No guessed destination.
      if (epoch === this.epoch && !signal.aborted &&
          this.latest.get(evidence.sourceId) === evidence.revision) {
        this.screenCache = { appId: evidence.appId, text: evidence.text,
          sourceId: evidence.sourceId, revision: evidence.revision,
          preparedAt: Date.now(), embedding };
      }
    });
  }
  async prepare(
    requestId: string,
    query: string,
    appId: string,
    signal: AbortSignal,
    screenText = "",
  ): Promise<PreparedContext | undefined> {
    if (!this.captureEnabled || this.exclusions.has(appId)) return undefined;
    const epoch = this.epoch;
    await this.ready;
    signal.throwIfAborted();
    if (epoch !== this.epoch || !this.captureEnabled) return undefined;
    const bounded = query.slice(-8000),
      key = hash(appId + "\0" + bounded),
      cancellation = this.cancellation.signal;
    if (
      bounded.trim() &&
      this.queryCache?.key !== key &&
      this.queryKey !== key
    ) {
      this.queryCancellation?.abort();
      this.queryCancellation = new AbortController();
      this.queryKey = key;
      const querySignal = AbortSignal.any([
        cancellation,
        this.queryCancellation.signal,
      ]);
      this.schedule("query", async () => {
        try {
          const embedding = await this.embedding(bounded, querySignal);
          if (
            embedding &&
            epoch === this.epoch &&
            this.queryKey === key &&
            !querySignal.aborted
          )
            this.queryCache = { key, query: bounded, appId, embedding };
        } finally {
          if (this.queryKey === key) this.queryKey = "";
        }
      });
    }
    // A completed query vector remains useful while the same draft only grows.
    // Replacement/deletion or a destination-app change cannot reuse it.
    const cached = this.queryCache;
    const reusable =
      cached &&
      cached.appId === appId &&
      (cached.key === key ||
        (bounded.startsWith(cached.query) &&
          bounded.length - cached.query.length <= 256));
    const screen = this.screenCache;
    const screenVector = screen && screen.appId === appId && screen.text === screenText &&
      Date.now() - screen.preparedAt < 300000 &&
      this.latest.get(screen.sourceId) === screen.revision ? screen.embedding : undefined;
    const vector = reusable ? cached.embedding : screenVector;
    const result = PreparedContextSchema.parse(
      await this.options.store.call(
        "retrieve",
        {
          query: bounded,
          ...(vector ? { embedding: vector } : {}),
          limit: 12,
        },
        signal,
      ),
    );
    if (epoch !== this.epoch || signal.aborted) return undefined;
    if (!vector && this.semanticStatus === "unavailable")
      result.availability.semantic = "unavailable";
    this.dependencies.set(requestId, result);
    while (this.dependencies.size > 64)
      this.dependencies.delete(this.dependencies.keys().next().value!);
    for (const evidence of result.evidence) {
      if (evidence.resourceId && evidence.appId === "connector.github")
        this.readResources(
          "https://github.com/" +
            evidence.resourceId
              .replace("/pulls/", "/pull/")
              .replace(/\/contents\/(.+)\?ref=([^&]+)$/, "/blob/$2/$1"),
          epoch,
        );
      if (evidence.resourceId && evidence.appId === "connector.figma")
        this.readResources(
          "https://www.figma.com/file/" +
            evidence.resourceId.split("/nodes/")[0] +
            (evidence.resourceId.includes("/nodes/")
              ? "?node-id=" +
                encodeURIComponent(evidence.resourceId.split("/nodes/")[1]!)
              : ""),
          epoch,
        );
    }
    this.used = result.evidence.map(row);
    this.options.changed();
    return result;
  }
  async valid(requestId: string, signal: AbortSignal): Promise<boolean> {
    const epoch = this.epoch;
    const context = this.dependencies.get(requestId);
    if (!context || !this.captureEnabled) return false;
    try {
      const valid = await this.options.store.call<boolean>(
        "validate",
        { dependencies: context.dependencies },
        signal,
      );
      return (
        valid === true &&
        epoch === this.epoch &&
        !signal.aborted &&
        this.dependencies.get(requestId) === context
      );
    } catch {
      return false;
    }
  }
  release(requestId: string): void {
    this.dependencies.delete(requestId);
  }
  async previousHistory(): Promise<void> {
    this.historyOffset = Math.max(0, this.historyOffset - 100);
    await this.refresh();
  }
  async moreHistory(): Promise<void> {
    await this.browse(this.historyQuery, true);
  }
  async browse(query: string, more = false): Promise<void> {
    this.historyQuery = query.slice(0, 2000);
    this.historyOffset = more ? this.historyOffset + 100 : 0;
    await this.refresh();
  }
  async refresh(): Promise<void> {
    if (!this.subject) return;
    if (this.refreshing) {
      this.refreshAgain = true;
      return;
    }
    this.refreshing = true;
    const epoch = this.epoch,
      query = this.historyQuery,
      offset = this.historyOffset;
    try {
      await this.ready;
      if (epoch !== this.epoch) return;
      const result = await this.options.store.call<{
        evidence: Evidence[];
        savedIds: string[];
      }>(
        query ? "search" : "history",
        query ? { query } : { limit: 100, offset, savedOnly: false },
      );
      const pins = await this.options.store.call<{
        evidence: Evidence[];
        savedIds: string[];
      }>("history", { limit: 200, savedOnly: true });
      if (
        epoch !== this.epoch ||
        query !== this.historyQuery ||
        offset !== this.historyOffset
      )
        return;
      this.history = result.evidence
        .filter((e) => !result.savedIds.includes(e.id))
        .map(row);
      this.references = pins.evidence.map(row);
      this.options.changed();
    } finally {
      this.refreshing = false;
      if (this.refreshAgain) {
        this.refreshAgain = false;
        void this.refresh().catch(() => {});
      }
    }
  }
  async action(
    op: "delete" | "save" | "unpin" | "clear",
    id?: string,
  ): Promise<void> {
    const epoch = this.epoch;
    if (!this.subject) throw new Error("Sign in first");
    await this.ready;
    if (epoch !== this.epoch) throw new Error("Account changed");
    this.epoch++;
    this.cancellation.abort();
    this.cancellation = new AbortController();
    this.queue.clear();
    this.pendingVisual = null;
    this.visualCancellation?.abort();
    this.resourceReads.clear();
    this.queryCache = null;
    this.screenCache = null;
    this.queryKey = "";
    this.queryCancellation?.abort();
    this.latest.clear();
    if (op === "clear") this.invalidateAll();
    else if (id) {
      const source =
        [...this.dependencies.values()]
          .flatMap((c) => c.evidence)
          .find((e) => e.id === id)?.sourceId ?? id;
      this.changedSource(source);
    }
    await this.options.store.call(
      op === "unpin" ? "save" : op,
      id ? { evidenceId: id, saved: op !== "unpin" } : {},
    );
    await this.refresh();
  }
  async addReference(text: string): Promise<void> {
    const epoch = this.epoch;
    if (!this.subject) throw new Error("Sign in first");
    await this.ready;
    if (epoch !== this.epoch) throw new Error("Account changed");
    const id = randomUUID(),
      now = Date.now();
    const evidence = EvidenceSchema.parse({
      id,
      sourceId: id,
      revision: hash(text),
      provenance: "authored",
      appId: "com.autocompletion.reference",
      text,
      capturedAtMs: now,
      expiresAtMs: now + MONTH,
      dependencies: [],
    });
    await this.options.store.call(
      "put",
      { evidence },
      this.cancellation.signal,
    );
    if (epoch !== this.epoch) throw new Error("Account changed");
    await this.options.store.call(
      "save",
      { evidenceId: id, saved: true },
      this.cancellation.signal,
    );
    if (epoch !== this.epoch) return;
    this.embed(evidence, this.epoch);
    await this.refresh();
  }
  dispose(): void {
    clearInterval(this.maintenance);
    this.epoch++;
    this.allowed = false;
    this.cancellation.abort();
    this.queue.clear();
    this.pendingVisual = null;
    this.visualCancellation?.abort();
    this.invalidateAll();
  }
}
