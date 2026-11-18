import type { GatewayProvider } from "@ai-sdk/gateway";
import type { Hono } from "hono";

import { createApp, type AuthenticateRequest, type SuggestionOutcomeStore } from "./app.js";
import { createConnectorApp } from "./context/connectors.js";
import type { ContextLeasePool } from "./context/leases.js";
import { ContextModels } from "./context/models.js";
import { createContextApp } from "./context/routes.js";
import type { BackgroundMetric } from "./context/telemetry.js";
import { GeminiSuggestionGenerator } from "./models/generate.js";
import { GeminiPreferenceExtractor } from "./models/preferences.js";
import { TransformGenerator } from "./models/transform.js";
import { createApiTraceRuntime } from "./telemetry/api-trace.js";
import { createTransformApp } from "./transforms.js";

export const GENERATION_MODEL_ID = "google/gemini-3.5-flash-lite";

export type ApiComposition = {
  authenticate: AuthenticateRequest;
  modelProvider: GatewayProvider;
  aiDiagnostics: "off" | "full";
  environment: Readonly<Record<string, string | undefined>>;
  backgroundLeases: ContextLeasePool;
  outcomes: SuggestionOutcomeStore;
  backgroundMetric?: (event: BackgroundMetric) => void;
};

/**
 * Assembles every route around injected identity, model access and storage.
 * The hosted entry supplies Clerk and Postgres; the desktop app supplies a
 * local identity and the user's own AI Gateway key.
 */
export function createApi(composition: ApiComposition): Hono {
  const { authenticate, modelProvider, backgroundLeases } = composition;
  const backgroundMetric = composition.backgroundMetric ?? (() => {});
  const trace = createApiTraceRuntime({
    diagnostics: composition.aiDiagnostics,
    environment: composition.environment,
  });

  const app = createApp({
    authenticate,
    preferenceExtractor: new GeminiPreferenceExtractor(modelProvider, { metric: backgroundMetric }),
    backgroundLeases,
    generator: new GeminiSuggestionGenerator(modelProvider, {
      diagnostics: composition.aiDiagnostics,
    }),
    ...(trace ? { trace } : {}),
    outcomes: composition.outcomes,
  });

  const transformGenerator = new TransformGenerator(modelProvider, GENERATION_MODEL_ID);
  app.route("/", createTransformApp({
    authenticate,
    generate: input => transformGenerator.transform(input),
  }));

  const contextModels = new ContextModels(modelProvider, backgroundMetric);
  app.route("/", createContextApp({
    authenticate,
    leases: backgroundLeases,
    visual: (input, signal) => contextModels.visual(input, signal),
    embed: (text, signal) => contextModels.embedding(text, signal),
  }));
  app.route("/", createConnectorApp({ authenticate, environment: composition.environment }));
  return app;
}

/** Bounds concurrent background work per user without a database. */
export function createMemoryLeasePool(limit = 2): ContextLeasePool {
  const active = new Map<string, number>();
  return {
    async acquire(userId) {
      const current = active.get(userId) ?? 0;
      if (current >= limit) return null;
      active.set(userId, current + 1);
      let released = false;
      return async () => {
        if (released) return;
        released = true;
        const remaining = (active.get(userId) ?? 1) - 1;
        if (remaining > 0) active.set(userId, remaining);
        else active.delete(userId);
      };
    },
  };
}
