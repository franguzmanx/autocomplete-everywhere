import type { AuthenticatedPostgresRunner } from "./postgres-client.js";
import type { SuggestionOutcomeConnection } from "./suggestion-outcomes.js";

export function createPostgresSuggestionOutcomeConnection(
  runner: AuthenticatedPostgresRunner,
): SuggestionOutcomeConnection {
  return {
    record: (subject, events) =>
      runner.run(subject, async (transaction) => {
        for (const event of events) {
          await transaction`
            select public.record_suggestion_outcome(
              ${event.requestId}::uuid,
              ${event.appId},
              ${event.surface},
              ${event.outcome}::public.suggestion_outcome,
              ${event.requestToVisibleMs ?? null},
              ${event.requestToFinalMs ?? null},
              ${event.suggestionCharacterCount ?? null},
              ${event.acceptedCharacterCount ?? null},
              ${event.errorClass ?? null},
              ${event.modelId ?? null}
            )
          `;
        }
      }),
  };
}
