import type { SuggestionOutcomeEvent } from "./suggestion-activity";

type CancelScheduled = () => void;

type SuggestionOutcomeUploaderDependencies = {
  send(events: SuggestionOutcomeEvent[], signal: AbortSignal): Promise<void>;
  schedule?: (callback: () => void, delayMs: number) => CancelScheduled;
  onDiagnostic?: (code: "outcome_upload_failed") => void;
  batchSize?: number;
  flushIntervalMs?: number;
  maxQueue?: number;
};

/// Ships content-free outcome events to the product API in small batches.
/// Delivery is best-effort: a rejected batch is dropped, never retried into
/// the suggestion hot path, and never logged with its contents.
export class SuggestionOutcomeUploader {
  private queue: SuggestionOutcomeEvent[] = [];
  private cancelScheduled: CancelScheduled | null = null;
  private inFlight: Promise<void> | null = null;
  private active: AbortController | null = null;
  private disposed = false;
  private readonly batchSize: number;
  private readonly flushIntervalMs: number;
  private readonly maxQueue: number;
  private readonly schedule: NonNullable<
    SuggestionOutcomeUploaderDependencies["schedule"]
  >;

  constructor(private readonly dependencies: SuggestionOutcomeUploaderDependencies) {
    this.batchSize = dependencies.batchSize ?? 20;
    this.flushIntervalMs = dependencies.flushIntervalMs ?? 15_000;
    this.maxQueue = dependencies.maxQueue ?? 200;
    this.schedule =
      dependencies.schedule ??
      ((callback, delayMs) => {
        const timer = setTimeout(callback, delayMs);
        timer.unref();
        return () => clearTimeout(timer);
      });
  }

  enqueue(event: SuggestionOutcomeEvent): void {
    if (this.disposed) return;
    this.queue.push(event);
    if (this.queue.length > this.maxQueue) {
      this.queue.splice(0, this.queue.length - this.maxQueue);
    }
    if (this.queue.length >= this.batchSize) {
      void this.flush();
      return;
    }
    this.cancelScheduled ??= this.schedule(() => {
      this.cancelScheduled = null;
      void this.flush();
    }, this.flushIntervalMs);
  }

  flush(): Promise<void> {
    this.clearTimer();
    if (this.disposed || this.queue.length === 0) return this.inFlight ?? Promise.resolve();
    // A single drain owns the pending queue. Flush never captures another batch
    // behind an outstanding send.
    this.inFlight ??= this.drain().finally(() => {
      this.inFlight = null;
      if (!this.disposed && this.queue.length > 0) void this.flush();
    });
    return this.inFlight;
  }

  private async drain(): Promise<void> {
    while (!this.disposed && this.queue.length > 0) {
      const batch = this.queue.splice(0, this.batchSize);
      const controller = new AbortController();
      this.active = controller;
      try {
        await this.dependencies.send(batch, controller.signal);
      } catch {
        if (!controller.signal.aborted) {
          try { this.dependencies.onDiagnostic?.("outcome_upload_failed"); }
          catch { /* Diagnostics are best-effort. */ }
        }
      } finally {
        if (this.active === controller) this.active = null;
      }
    }
    this.clearTimer();
  }

  // Called synchronously before a session can use replacement credentials.
  reset(): void {
    this.clearTimer();
    this.queue = [];
    this.active?.abort();
  }

  dispose(): void {
    this.disposed = true;
    this.reset();
  }

  private clearTimer(): void {
    this.cancelScheduled?.();
    this.cancelScheduled = null;
  }
}
