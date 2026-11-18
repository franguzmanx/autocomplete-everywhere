import {
  classifyDatabaseCode,
  classifyDatabaseReason,
  requireSubject,
} from "./database-failure.js";

export type SuggestionOutcomeKind =
  | "requested"
  | "generated"
  | "suppressed"
  | "failed"
  | "cancelled"
  | "shown"
  | "accepted_full"
  | "accepted_partial"
  | "typed_through"
  | "dismissed"
  | "stale";

/// One content-free outcome row. Identifiers, surface class, outcome, and
/// timing only; the API validates the shape before it reaches this layer.
export type SuggestionOutcomeRecord = {
  requestId: string;
  appId: string;
  surface: "text_editor" | "web_textarea";
  outcome: SuggestionOutcomeKind;
  requestToVisibleMs?: number;
  requestToFinalMs?: number;
  suggestionCharacterCount?: number;
  acceptedCharacterCount?: number;
  errorClass?: string;
  modelId?: string;
};

export type SuggestionOutcomeConnection = {
  record(subject: string, events: readonly SuggestionOutcomeRecord[]): Promise<void>;
};

export class SuggestionOutcomeFailure extends Error {
  constructor(
    readonly code: string,
    readonly reason: string,
  ) {
    super("Suggestion outcome record failed");
    this.name = "SuggestionOutcomeFailure";
  }
}

export class SuggestionOutcomeRepository {
  constructor(private readonly connection: SuggestionOutcomeConnection) {}

  async record(
    subject: string,
    events: readonly SuggestionOutcomeRecord[],
  ): Promise<void> {
    const verifiedSubject = requireSubject(subject);
    if (verifiedSubject === null) {
      throw new SuggestionOutcomeFailure("INVALID_SUBJECT", "rejected");
    }
    if (events.length === 0) return;
    try {
      await this.connection.record(verifiedSubject, events);
    } catch (error) {
      if (error instanceof SuggestionOutcomeFailure) throw error;
      const candidate = error as { code?: unknown; message?: unknown };
      throw new SuggestionOutcomeFailure(
        classifyDatabaseCode(candidate?.code),
        classifyDatabaseReason(candidate?.message),
      );
    }
  }
}
