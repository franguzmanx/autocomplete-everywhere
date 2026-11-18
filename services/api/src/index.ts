import { createContextApp } from './context/routes.js';
import { ContextModels } from './context/models.js';
import { createConnectorApp } from './context/connectors.js';
import { createContextLeasePool } from './context/leases.js';
import { TransformGenerator } from "./models/transform.js";
import { createTransformApp } from "./transforms.js";
import { createAuthenticatedPostgresRunner } from "../../../packages/database/src/postgres-client.js";
import { createPostgresSuggestionOutcomeConnection } from "../../../packages/database/src/postgres-suggestion-outcomes.js";
import { SuggestionOutcomeFailure, SuggestionOutcomeRepository } from "../../../packages/database/src/suggestion-outcomes.js";
import { gateway } from "@ai-sdk/gateway";
import { handle } from "hono/vercel";

import { createApp } from "./app.js";
import { createAuthenticateClerkRequest } from "./auth.js";
import { parseApiEnvironment } from "./config.js";
import { GeminiPreferenceExtractor } from "./models/preferences.js";
import { GeminiSuggestionGenerator } from "./models/generate.js";
import { createApiTraceRuntime } from "./telemetry/api-trace.js";

const configuration = parseApiEnvironment(process.env);
const modelProvider = gateway;
const backgroundLeases=configuration.databaseUrl ? createContextLeasePool(createAuthenticatedPostgresRunner(configuration.databaseUrl)) : {async acquire(){throw new Error('context_unavailable');}};
const backgroundMetric=(event:import('./context/telemetry.js').BackgroundMetric)=>console.info('background_usage',event);
const suggestionOutcomes = configuration.databaseUrl
  ? new SuggestionOutcomeRepository(createPostgresSuggestionOutcomeConnection(createAuthenticatedPostgresRunner(configuration.databaseUrl)))
  : undefined;
const apiTrace = createApiTraceRuntime({
  diagnostics: configuration.aiDiagnostics,
  environment: process.env,
});

function reportOutcomeFailure(error: unknown): void {
  console.error("suggestion_outcome_store_failed", {
    code: error instanceof SuggestionOutcomeFailure ? error.code : "UNKNOWN",
    reason: error instanceof SuggestionOutcomeFailure ? error.reason : "rejected",
  });
}

export const app = createApp({
  authenticate: createAuthenticateClerkRequest({
    secretKey: configuration.clerkSecretKey,
    publishableKey: configuration.clerkPublishableKey,
  }),
  preferenceExtractor: new GeminiPreferenceExtractor(modelProvider,{metric:backgroundMetric}),
  backgroundLeases,
  generator: new GeminiSuggestionGenerator(modelProvider, {
    diagnostics: configuration.aiDiagnostics,
  }),
  ...(apiTrace ? { trace: apiTrace } : {}),
  outcomes: {
    record: async ({ userId, events }) => {
      try {
        // The model identity is server knowledge attached at record time so
        // later configuration changes can be compared without a client
        // concept of models.
        if (!suggestionOutcomes) throw new Error("outcomes_unavailable");
        await suggestionOutcomes.record(
          userId,
          events.map((event) => ({
            requestId: event.requestId,
            appId: event.appId,
            surface: event.surface,
            outcome: event.outcome,
            ...(event.requestToVisibleMs !== undefined
              ? { requestToVisibleMs: event.requestToVisibleMs }
              : {}),
            ...(event.requestToFinalMs !== undefined
              ? { requestToFinalMs: event.requestToFinalMs }
              : {}),
            ...(event.suggestionCharacterCount !== undefined
              ? { suggestionCharacterCount: event.suggestionCharacterCount }
              : {}),
            ...(event.acceptedCharacterCount !== undefined
              ? { acceptedCharacterCount: event.acceptedCharacterCount }
              : {}),
            ...(event.errorClass !== undefined
              ? { errorClass: event.errorClass }
              : {}),
            modelId: "google/gemini-3.5-flash-lite",
          })),
        );
      } catch (error) {
        reportOutcomeFailure(error);
        throw error;
      }
    },
  },
});

const transformGenerator = new TransformGenerator(modelProvider, "google/gemini-3.5-flash-lite");
app.route('/', createTransformApp({
  authenticate: createAuthenticateClerkRequest({
    secretKey: configuration.clerkSecretKey,
    publishableKey: configuration.clerkPublishableKey,
  }),
  generate: input => transformGenerator.transform(input),
}));
const contextModels = new ContextModels(modelProvider, backgroundMetric);
const contextAuthenticate = createAuthenticateClerkRequest({secretKey:configuration.clerkSecretKey,publishableKey:configuration.clerkPublishableKey});
app.route('/', createContextApp({
 authenticate:contextAuthenticate,
 leases:backgroundLeases,
 visual:(input,signal)=>contextModels.visual(input,signal),
 embed:(text,signal)=>contextModels.embedding(text,signal),
}));
app.route('/', createConnectorApp({authenticate:contextAuthenticate,environment:process.env}));
const handler = handle(app);

export const GET = handler;
export const POST = handler;
export const OPTIONS = handler;

export default handler;
