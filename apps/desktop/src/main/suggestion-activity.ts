import type { ProtocolMessage, WorkIdentity } from "@autocompletion/protocol";

import type {
  LatencySummary,
  SuggestionActivitySummary,
  SuggestionOutcome,
} from "../shared/contracts";

/// One content-free outcome for one suggestion request. It carries request
/// identity, surface class, outcome, and timing: never field text,
/// suggestion text, or anything derived from them beyond a character count.
export type SuggestionOutcomeEvent = {
  requestId: string;
  appId: string;
  surface: "text_editor" | "web_textarea";
  outcome: SuggestionOutcome;
  requestToVisibleMs?: number;
  requestToFinalMs?: number;
  suggestionCharacterCount?: number;
  acceptedCharacterCount?: number;
  errorClass?: string;
};

type SuggestionActivityDependencies = {
  now?: () => number;
  onEvent?: (event: SuggestionOutcomeEvent) => void;
  onChange?: (summary: SuggestionActivitySummary) => void;
};

type RememberedRequest = {
  appId: string;
  surface: "text_editor" | "web_textarea";
  requestedAtMs: number;
  requestToFinalMs?: number;
  suggestionCharacterCount?: number;
};

const MAX_REMEMBERED_REQUESTS = 64;
const MAX_LATENCY_SAMPLES = 200;
const MAX_PLAUSIBLE_LATENCY_MS = 120_000;

/// Correlates helper requests, desktop responses, and helper interaction
/// reports into content-free outcomes. The helper remains the authority for
/// what was shown or inserted; this class only records what it reports.
export class SuggestionActivity {
  private readonly remembered = new Map<string, RememberedRequest>();
  private readonly visibleLatencies: number[] = [];
  private readonly finalLatencies: number[] = [];
  private readonly counts: Record<SuggestionOutcome, number> = {
    requested: 0,
    generated: 0,
    suppressed: 0,
    failed: 0,
    cancelled: 0,
    shown: 0,
    accepted_full: 0,
    accepted_partial: 0,
    typed_through: 0,
    dismissed: 0,
    stale: 0,
  };
  private acceptedCharacters = 0;
  private lastOutcome: SuggestionOutcome | null = null;
  private readonly since: string;

  constructor(private readonly dependencies: SuggestionActivityDependencies = {}) {
    this.since = new Date(this.now()).toISOString();
  }

  get rememberedRequestCount(): number {
    return this.remembered.size;
  }

  clearRequests(): void {
    this.remembered.clear();
  }

  observe(message: ProtocolMessage): void {
    switch (message.type) {
      case "suggestion_request":
        this.remember(message.identity, {
          appId: message.payload.appId,
          surface: message.payload.surface,
          requestedAtMs: message.identity.timestampMs,
        });
        this.emit(message.identity, "requested", {});
        return;
      case "suggestion_final": {
        const entry = this.remembered.get(message.identity.requestId);
        if (!entry) return;
        const requestToFinalMs = this.elapsedSince(entry.requestedAtMs);
        if (requestToFinalMs !== undefined) {
          entry.requestToFinalMs = requestToFinalMs;
          this.sample(this.finalLatencies, requestToFinalMs);
        }
        if ("text" in message.payload) {
          entry.suggestionCharacterCount = message.payload.text.length;
          this.emit(message.identity, "generated", {
            ...(requestToFinalMs !== undefined ? { requestToFinalMs } : {}),
            suggestionCharacterCount: entry.suggestionCharacterCount,
          });
        } else {
          this.emit(message.identity, "suppressed", {
            ...(requestToFinalMs !== undefined ? { requestToFinalMs } : {}),
          });
        }
        return;
      }
      case "request_failed":
        if (!this.remembered.has(message.identity.requestId)) return;
        this.emit(message.identity, "failed", {
          errorClass: message.payload.code,
        });
        return;
      case "cancel_request":
        if (!this.remembered.has(message.identity.requestId)) return;
        this.emit(message.identity, "cancelled", {
          errorClass: message.payload.reason,
        });
        return;
      case "interaction": {
        if(message.payload.outcome === "edited_after_acceptance" || message.payload.outcome === "removed_after_acceptance" || message.payload.outcome === "observation_unavailable")return;
        const entry = this.remembered.get(message.identity.requestId);
        if (!entry) return;
        const details: Partial<SuggestionOutcomeEvent> = {};
        if (entry.requestToFinalMs !== undefined && message.payload.outcome === "shown") {
          details.requestToFinalMs = entry.requestToFinalMs;
        }
        if (message.payload.outcome === "shown") {
          const requestToVisibleMs = this.elapsedSince(entry.requestedAtMs);
          if (requestToVisibleMs !== undefined) {
            details.requestToVisibleMs = requestToVisibleMs;
            this.sample(this.visibleLatencies, requestToVisibleMs);
          }
        }
        if (entry.suggestionCharacterCount !== undefined) {
          details.suggestionCharacterCount = entry.suggestionCharacterCount;
        }
        if (message.payload.acceptedCharacters > 0) {
          details.acceptedCharacterCount = message.payload.acceptedCharacters;
          this.acceptedCharacters += message.payload.acceptedCharacters;
        }
        this.emit(message.identity, message.payload.outcome, details);
        return;
      }
      default:
        return;
    }
  }

  summary(): SuggestionActivitySummary {
    return {
      since: this.since,
      requested: this.counts.requested,
      generated: this.counts.generated,
      suppressed: this.counts.suppressed,
      failed: this.counts.failed,
      cancelled: this.counts.cancelled,
      shown: this.counts.shown,
      accepted: this.counts.accepted_full + this.counts.accepted_partial,
      typedThrough: this.counts.typed_through,
      dismissed: this.counts.dismissed,
      stale: this.counts.stale,
      acceptedCharacters: this.acceptedCharacters,
      requestToVisibleMs: summarize(this.visibleLatencies),
      requestToFinalMs: summarize(this.finalLatencies),
      lastOutcome: this.lastOutcome,
    };
  }

  private now(): number {
    return (this.dependencies.now ?? Date.now)();
  }

  private elapsedSince(startMs: number): number | undefined {
    const elapsed = this.now() - startMs;
    return elapsed >= 0 && elapsed <= MAX_PLAUSIBLE_LATENCY_MS ? elapsed : undefined;
  }

  private remember(identity: WorkIdentity, entry: RememberedRequest): void {
    this.remembered.delete(identity.requestId);
    this.remembered.set(identity.requestId, entry);
    while (this.remembered.size > MAX_REMEMBERED_REQUESTS) {
      const oldest = this.remembered.keys().next().value;
      if (oldest === undefined) break;
      this.remembered.delete(oldest);
    }
  }

  private sample(samples: number[], value: number): void {
    samples.push(value);
    if (samples.length > MAX_LATENCY_SAMPLES) samples.shift();
  }

  private emit(
    identity: WorkIdentity,
    outcome: SuggestionOutcome,
    details: Partial<SuggestionOutcomeEvent>,
  ): void {
    const entry = this.remembered.get(identity.requestId);
    if (!entry) return;
    this.counts[outcome] += 1;
    this.lastOutcome = outcome;
    const event: SuggestionOutcomeEvent = {
      requestId: identity.requestId,
      appId: entry.appId,
      surface: entry.surface,
      outcome,
      ...details,
    };
    try {
      this.dependencies.onEvent?.(event);
    } catch {
      // Measurement is best-effort and never affects the suggestion loop.
    }
    try {
      this.dependencies.onChange?.(this.summary());
    } catch {
      // Same: a consumer failure cannot affect the suggestion loop.
    }
  }
}

function summarize(samples: readonly number[]): LatencySummary {
  if (samples.length === 0) return { p50: null, p95: null, samples: 0 };
  const sorted = [...samples].sort((left, right) => left - right);
  return {
    p50: nearestRank(sorted, 0.5),
    p95: nearestRank(sorted, 0.95),
    samples: sorted.length,
  };
}

function nearestRank(sorted: readonly number[], percentile: number): number {
  const rank = Math.max(1, Math.ceil(percentile * sorted.length));
  return sorted[rank - 1] ?? sorted[sorted.length - 1] ?? 0;
}
