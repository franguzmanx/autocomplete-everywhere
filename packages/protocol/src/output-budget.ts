import type { SuggestionRequest } from "./messages.js";

/** Generated writing plus exact source transport, bounded across every hop. */
export function maximumInsertionCharacters(request: SuggestionRequest): number {
  return request.payload.fieldContext.shape === "single_line" ? 120 : Math.min(
    12_000, 2_000 + request.payload.artifacts.reduce((total, artifact) => total + artifact.text.length, 0),
  );
}
