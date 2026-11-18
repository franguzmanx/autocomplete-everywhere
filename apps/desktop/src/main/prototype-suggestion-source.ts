import type { SuggestionRequest } from "@autocompletion/protocol";

import type { SuggestionSource } from "./suggestion-coordinator";

export type PrototypeSuggestionDecision =
  | { outcome: "text"; reason: "default" | "unicode" | "list" }
  | {
      outcome: "silence";
      reason: "newline" | "complete" | "no_match" | "cancelled";
    };

type PrototypeSuggestionSourceOptions = {
  onDecision?: (decision: PrototypeSuggestionDecision) => void;
};

const DEFAULT_FIXTURE =
  "En una interfaz confiable, la sugerencia permanece junto al cursor mientras escribís, se oculta ante una geometría dudosa y reaparece únicamente cuando la posición vuelve a ser estable.";
const UNICODE_FIXTURE =
  "También debe respetar emoji 🚀, acentos, 日本語 y العربية sin duplicar texto.";
const LIST_FIXTURE =
  "\n- primer punto con una explicación extensa\n- segundo punto que verifica el ajuste del párrafo";

const MARKED_FIXTURES = [
  { marker: "unicode:", target: UNICODE_FIXTURE },
  { marker: "lista:", target: LIST_FIXTURE },
] as const;

export function createPrototypeSuggestionSource(
  environment: Readonly<Record<string, string | undefined>>,
  options: PrototypeSuggestionSourceOptions = {},
): SuggestionSource | null {
  return environment.AUTOCOMPLETION_VISUAL_FIXTURE === "1"
    ? new PrototypeSuggestionSource(options)
    : null;
}

class PrototypeSuggestionSource implements SuggestionSource {
  constructor(private readonly options: PrototypeSuggestionSourceOptions) {}

  async complete(
    request: SuggestionRequest,
    signal: AbortSignal,
  ): Promise<string> {
    if (signal.aborted) {
      this.report({ outcome: "silence", reason: "cancelled" });
      return "";
    }
    const decision = continuationDecision(request.payload.textBefore);
    this.report(decision.publicDecision);
    return decision.continuation ?? "";
  }

  private report(decision: PrototypeSuggestionDecision): void {
    try {
      this.options.onDecision?.(decision);
    } catch {
      // Fixture diagnostics are best-effort and cannot affect suggestions.
    }
  }
}

type ContinuationDecision = {
  continuation: string | null;
  publicDecision: PrototypeSuggestionDecision;
};

function continuationDecision(textBefore: string): ContinuationDecision {
  for (const fixture of MARKED_FIXTURES) {
    if (!textBefore.startsWith(fixture.marker)) continue;
    const typed = textBefore.slice(fixture.marker.length);
    if (!fixture.target.startsWith(typed)) {
      return {
        continuation: null,
        publicDecision: { outcome: "silence", reason: "no_match" },
      };
    }
    const continuation = fixture.target.slice(typed.length);
    if (!continuation) {
      return {
        continuation: null,
        publicDecision: { outcome: "silence", reason: "complete" },
      };
    }
    return {
      continuation,
      publicDecision: {
        outcome: "text",
        reason: fixture.marker === "unicode:" ? "unicode" : "list",
      },
    };
  }

  if (textBefore.endsWith("\n") || textBefore.endsWith("\r")) {
    return {
      continuation: null,
      publicDecision: { outcome: "silence", reason: "newline" },
    };
  }

  const overlap = suffixPrefixOverlap(textBefore, DEFAULT_FIXTURE);
  if (overlap === 0) {
    const characters = Array.from(textBefore);
    characters.pop();
    if (suffixPrefixOverlap(characters.join(""), DEFAULT_FIXTURE) > 0) {
      return {
        continuation: null,
        publicDecision: { outcome: "silence", reason: "no_match" },
      };
    }
  }
  const continuation = overlap > 0
    ? DEFAULT_FIXTURE.slice(overlap)
    : DEFAULT_FIXTURE;
  return continuation
    ? {
        continuation,
        publicDecision: { outcome: "text", reason: "default" },
      }
    : {
        continuation: null,
        publicDecision: { outcome: "silence", reason: "complete" },
      };
}

function suffixPrefixOverlap(source: string, target: string): number {
  const maximumOverlap = Math.min(source.length, target.length);

  for (let overlap = maximumOverlap; overlap > 0; overlap -= 1) {
    if (source.endsWith(target.slice(0, overlap))) return overlap;
  }
  return 0;
}
