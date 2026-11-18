import type { ContextLeasePool } from './context/leases.js';
import {
  generationFailureKindSchema,
  generationFailureReasonSchema,
  parseProtocolMessage,
  maximumInsertionCharacters,
  type SuggestionRequest,
} from "../../../packages/protocol/src/index.js";
import { Hono } from "hono";
import { SuggestionOutcomeBatchSchema, type SuggestionOutcomeEvent } from "./telemetry/events.js";
import { registerPreferenceExtractionRoute, type PreferenceExtractor } from "./preferences.js";

import { finalizeContinuation } from "./prompts/continuation-policy.js";
import type {
  ApiTraceEntry,
  ApiTraceRuntime,
  ApiTraceTimestamp,
} from "./telemetry/api-trace.js";

export type DependencySource = "origin" | "cache" | "inflight";

export type AuthenticatedUser = {
  userId: string;
  source?: DependencySource;
};
export type AuthenticateRequest = (
  request: Request,
) => Promise<AuthenticatedUser | null>;

export type SuggestionGenerationInput = {
  request: SuggestionRequest;
  userId: string;
  outputBudget: SuggestionOutputBudget;
  signal: AbortSignal;
};

export type SuggestionOutputBudget = {
  scope: "line" | "block";
  maxCharacters: number;
  allowsNewlines: boolean;
};

// Generated prose may be normalized; exact compositions must remain byte-for-byte.
export type SuggestionCandidate = string | { text: string; preservesExactArtifacts: true };
export type SuggestionGenerationFailureKind = "invalid_output" | "timeout" | "cancelled" | "provider_error";

export class SuggestionGenerationError extends Error {
  override name = "SuggestionGenerationError";

  constructor(
    readonly kind: SuggestionGenerationFailureKind,
    readonly reason: string,
  ) {
    super(`suggestion_generation_failed:${reason}`);
  }
}

function publicFailureDiagnostics(error: unknown): { kind: string; reason: string } {
  if (!(error instanceof SuggestionGenerationError)) {
    return { kind: "provider_error", reason: "unknown" };
  }
  return {
    kind: generationFailureKindSchema.safeParse(error.kind).data ?? "provider_error",
    reason: generationFailureReasonSchema.safeParse(error.reason).data ?? "unknown",
  };
}

export interface SuggestionGenerator {
  complete(input: SuggestionGenerationInput): Promise<SuggestionCandidate | undefined>;
}

export function deriveSuggestionOutputBudget(
  request: SuggestionRequest,
): SuggestionOutputBudget {
  if (request.payload.fieldContext.shape === "single_line") {
    return { scope: "line", maxCharacters: maximumInsertionCharacters(request), allowsNewlines: false };
  }

  // Shape is a physical constraint. The model chooses how much writing is
  // useful, including after the user has already started a multiline field.
  return {
    scope: "block",
    maxCharacters: maximumInsertionCharacters(request),
    allowsNewlines: true,
  };
}

export type SuggestionOutcomeStoreInput = AuthenticatedUser & {
  events: SuggestionOutcomeEvent[];
};
export interface SuggestionOutcomeStore {
  record(input: SuggestionOutcomeStoreInput): Promise<void>;
}

export type AppDependencies = {
  authenticate: AuthenticateRequest;
  generator: SuggestionGenerator;
  outcomes?: SuggestionOutcomeStore;
  preferenceExtractor?: PreferenceExtractor;
  backgroundLeases?:ContextLeasePool;
  trace?: ApiTraceRuntime;
};

const requestIdHeader = "x-autocompletion-request-id";

function elapsedMs(start: ApiTraceTimestamp, end: ApiTraceTimestamp): number {
  return Math.max(0, Math.round(end.monoMs - start.monoMs));
}

function writeTrace(
  runtime: ApiTraceRuntime | undefined,
  entry: ApiTraceEntry,
): void {
  try {
    runtime?.write(entry);
  } catch {
    // Diagnostics must never affect suggestion delivery.
  }
}

export function createApp(dependencies: AppDependencies): Hono {
  const app = new Hono();
  registerPreferenceExtractionRoute(app, dependencies);

  app.get("/health", (context) => context.json({ status: "ok" }));

  app.post("/v1/suggestions/outcomes", async (context) => {
    let authenticated: AuthenticatedUser | null;
    try {
      authenticated = await dependencies.authenticate(context.req.raw);
    } catch {
      return context.json({ error: "auth_unavailable" }, 503);
    }
    if (!authenticated) return context.json({ error: "unauthorized" }, 401);

    let input: unknown;
    try {
      input = await context.req.json();
    } catch {
      return context.json({ error: "invalid_request" }, 400);
    }
    const parsed = SuggestionOutcomeBatchSchema.safeParse(input);
    if (!parsed.success) return context.json({ error: "invalid_request" }, 400);

    if (!dependencies.outcomes) return context.json({ error: "outcomes_unavailable" }, 503);
    try {
      await dependencies.outcomes.record({
        ...authenticated,
        events: parsed.data.events,
      });
    } catch {
      return context.json({ error: "outcomes_unavailable" }, 503);
    }
    return context.body(null, 204);
  });

  app.post("/v1/suggestions", async (context) => {
    const receivedAt = dependencies.trace?.now();
    const cold = dependencies.trace?.claimCold();
    let authenticated: AuthenticatedUser | null;
    let authDoneAt: ApiTraceTimestamp | undefined;
    try {
      authenticated = await dependencies.authenticate(context.req.raw);
      authDoneAt = dependencies.trace?.now();
    } catch {
      return context.json({ error: "auth_unavailable" }, 503);
    }

    if (!authenticated) {
      return context.json({ error: "unauthorized" }, 401);
    }

    let input: unknown;
    try {
      input = await context.req.json();
    } catch {
      return context.json({ error: "invalid_request" }, 400);
    }

    const parsed = parseProtocolMessage(input);
    if ("ok" in parsed || parsed.type !== "suggestion_request") {
      return context.json({ error: "invalid_request" }, 400);
    }

    const requestId = parsed.identity.requestId;
    context.header(requestIdHeader, requestId);
    if (dependencies.trace && receivedAt && authDoneAt) {
      writeTrace(dependencies.trace, {
        v: 1,
        requestId,
        proc: "api",
        event: "received",
        wallMs: receivedAt.wallMs,
        monoMs: receivedAt.monoMs,
        attrs: {
          region: dependencies.trace.region,
          cold: cold ?? false,
          instanceAgeMs: Math.max(
            0,
            Math.round(
              receivedAt.wallMs - dependencies.trace.instanceStartedWallMs,
            ),
          ),
        },
      });
      writeTrace(dependencies.trace, {
        v: 1,
        requestId,
        proc: "api",
        event: "auth_done",
        wallMs: authDoneAt.wallMs,
        monoMs: authDoneAt.monoMs,
        attrs: {
          ms: elapsedMs(receivedAt, authDoneAt),
          source: authenticated.source ?? "origin",
        },
      });
    }

    const responseEnded = (
      result: "text" | "silence" | "error" | "cancelled",
      clientAborted?: true,
      failure?: SuggestionGenerationError,
    ) => {
      if (!dependencies.trace || !receivedAt) return;
      const endedAt = dependencies.trace.now();
      writeTrace(dependencies.trace, {
        v: 1,
        requestId,
        proc: "api",
        event: "response_end",
        wallMs: endedAt.wallMs,
        monoMs: endedAt.monoMs,
        attrs: {
          ms: elapsedMs(receivedAt, endedAt),
          result,
          ...(clientAborted ? { clientAborted } : {}),
          ...(failure ? { kind: failure.kind, reason: failure.reason } : {}),
        },
      });
    };

    const hasActiveText = Boolean(
      parsed.payload.textBefore.trim() ||
        parsed.payload.selectedText.trim() ||
        parsed.payload.textAfter.trim(),
    );
    const hasRelatedText = parsed.payload.fieldContext.relatedFields.some(
      (field) => field.text.trim(),
    );
    const hasArtifacts = parsed.payload.artifacts.some(
      (artifact) => artifact.kind === "selection" || artifact.kind === "clipboard",
    );
    const hasCurrentSource = parsed.payload.fieldContext.sources.some((source) => source.text.trim());
    if (!hasActiveText && !hasRelatedText && !hasArtifacts && !hasCurrentSource) {
      responseEnded("silence");
      return new Response("", {
        headers: {
          "cache-control": "no-store",
          "content-type": "text/plain; charset=utf-8",
          [requestIdHeader]: requestId,
          "x-content-type-options": "nosniff",
        },
      });
    }

    // The library selects candidates locally. Recheck objective scope boundaries
    // at the API boundary without any database or profile lookup.
    if (parsed.payload.knowledge) {
      const now = Date.now();
      parsed.payload.knowledge = parsed.payload.knowledge.filter((candidate) =>
        (candidate.expiresAt === null || candidate.expiresAt > now) &&
        (candidate.scope.appIds.includes(parsed.payload.appId) ||
          (candidate.kind === "style" && candidate.scope.appIds.length === 0)),
      );
    }

    if (parsed.payload.writingPreferences) {
      const matching = parsed.payload.writingPreferences.filter(preference =>
        preference.appId === parsed.payload.appId || (preference.origin === "explicit" && preference.appId === null),
      );
      if (matching.length) parsed.payload.writingPreferences = matching;
      else delete parsed.payload.writingPreferences;
    }

    const outputBudget = deriveSuggestionOutputBudget(parsed);

    const modelStartedAt = dependencies.trace?.now();
    let candidate: SuggestionCandidate | undefined;
    let final: string;
    try {
      context.req.raw.signal.throwIfAborted();
      candidate = await dependencies.generator.complete({
        request: parsed,
        userId: authenticated.userId,
        outputBudget,
        signal: context.req.raw.signal,
      });
      context.req.raw.signal.throwIfAborted();
      const exact = typeof candidate === "object" && candidate !== null;
      if (candidate !== undefined && typeof candidate !== "string" &&
        !(exact && candidate.preservesExactArtifacts === true && typeof candidate.text === "string")) {
        throw new SuggestionGenerationError("invalid_output", "invalid_candidate");
      }
      const text: string | undefined = typeof candidate === "string"
        ? candidate
        : candidate === undefined ? undefined : candidate.text;
      // Reuse the indivisible-composition validator to reject unsafe bytes and
      // budget violations before prose normalization can silently discard them.
      if (text !== undefined && (text !== "" || exact) && !finalizeContinuation("", text, {
        preserveExactComposition: true,
        maxOutputLength: outputBudget.maxCharacters,
        singleLine: exact && !outputBudget.allowsNewlines,
      })) {
        throw new SuggestionGenerationError("invalid_output", "invalid_candidate");
      }
      final = finalizeContinuation(parsed.payload.textBefore, text, {
        preserveExactComposition: exact,
        maxOutputLength: outputBudget.maxCharacters,
        singleLine: !outputBudget.allowsNewlines,
        preserveLineEndings: parsed.payload.artifacts.length > 0,
      });
      if (text && !final) {
        throw new SuggestionGenerationError("invalid_output", "candidate_rejected");
      }
    } catch (error) {
      if (context.req.raw.signal.aborted ||
        (error instanceof SuggestionGenerationError && error.kind === "cancelled")) {
        responseEnded("cancelled", context.req.raw.signal.aborted ? true : undefined);
        return Response.json({ error: "generation_cancelled" }, {
          status: 499,
          headers: { [requestIdHeader]: requestId },
        });
      }
      responseEnded("error", undefined, error instanceof SuggestionGenerationError ? error : undefined);
      const failure = publicFailureDiagnostics(error);
      context.header("x-autocompletion-failure-kind", failure.kind);
      context.header("x-autocompletion-failure-reason", failure.reason);
      return context.json({ error: "generation_failed" }, 502);
    }
    const modelDoneAt = dependencies.trace?.now();
    if (dependencies.trace && modelStartedAt && modelDoneAt) {
      if (candidate !== undefined) {
        writeTrace(dependencies.trace, {
          v: 1,
          requestId,
          proc: "api",
          event: "model_valid_object",
          wallMs: modelDoneAt.wallMs,
          monoMs: modelDoneAt.monoMs,
          attrs: { validObjectMs: elapsedMs(modelStartedAt, modelDoneAt) },
        });
      }
      writeTrace(dependencies.trace, {
        v: 1,
        requestId,
        proc: "api",
        event: "model_done",
        wallMs: modelDoneAt.wallMs,
        monoMs: modelDoneAt.monoMs,
        attrs: { totalMs: elapsedMs(modelStartedAt, modelDoneAt) },
      });
    }
    responseEnded(final ? "text" : "silence");
    return new Response(final, {
      headers: {
        "cache-control": "no-store",
        "content-type": "text/plain; charset=utf-8",
        [requestIdHeader]: requestId,
        "x-content-type-options": "nosniff",
      },
    });
  });

  return app;
}
