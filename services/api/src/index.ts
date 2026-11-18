import { gateway } from "@ai-sdk/gateway";
import { handle } from "hono/vercel";

import { createAuthenticatedPostgresRunner } from "../../../packages/database/src/postgres-client.js";
import { createPostgresSuggestionOutcomeConnection } from "../../../packages/database/src/postgres-suggestion-outcomes.js";
import { SuggestionOutcomeFailure, SuggestionOutcomeRepository } from "../../../packages/database/src/suggestion-outcomes.js";
import { createAuthenticateClerkRequest } from "./auth.js";
import { createApi, GENERATION_MODEL_ID } from "./compose.js";
import { parseApiEnvironment } from "./config.js";
import { createContextLeasePool } from "./context/leases.js";

// Hosted entry: Clerk identity, the deployment's own AI Gateway access and
// optional Postgres storage.
const configuration = parseApiEnvironment(process.env);
const suggestionOutcomes = configuration.databaseUrl
  ? new SuggestionOutcomeRepository(createPostgresSuggestionOutcomeConnection(createAuthenticatedPostgresRunner(configuration.databaseUrl)))
  : undefined;

function reportOutcomeFailure(error: unknown): void {
  console.error("suggestion_outcome_store_failed", {
    code: error instanceof SuggestionOutcomeFailure ? error.code : "UNKNOWN",
    reason: error instanceof SuggestionOutcomeFailure ? error.reason : "rejected",
  });
}

export const app = createApi({
  authenticate: createAuthenticateClerkRequest({
    secretKey: configuration.clerkSecretKey,
    publishableKey: configuration.clerkPublishableKey,
  }),
  modelProvider: gateway,
  aiDiagnostics: configuration.aiDiagnostics,
  environment: process.env,
  backgroundLeases: configuration.databaseUrl
    ? createContextLeasePool(createAuthenticatedPostgresRunner(configuration.databaseUrl))
    : { async acquire() { throw new Error("context_unavailable"); } },
  backgroundMetric: event => console.info("background_usage", event),
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
            modelId: GENERATION_MODEL_ID,
          })),
        );
      } catch (error) {
        reportOutcomeFailure(error);
        throw error;
      }
    },
  },
});

const handler = handle(app);

export const GET = handler;
export const POST = handler;
export const OPTIONS = handler;

export default handler;
