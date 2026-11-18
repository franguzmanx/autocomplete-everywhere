import type { ProtocolMessage } from "@autocompletion/protocol";

import type { PipelineTraceRecorder } from "./pipeline-trace";
import {
  createPrototypeSuggestionSource,
  type PrototypeSuggestionDecision,
} from "./prototype-suggestion-source";
import {
  SuggestionCoordinator,
  type SuggestionCoordinatorFinalResult,
  type SuggestionSource,
} from "./suggestion-coordinator";

type SuggestionBootstrapOptions = {
  environment: Readonly<Record<string, string | undefined>>;
  send(message: ProtocolMessage): void;
  remoteSource?: SuggestionSource;
  onSourceDecision?: (decision: PrototypeSuggestionDecision) => void;
  onFinalResult?: (result: SuggestionCoordinatorFinalResult) => void;
  trace?: PipelineTraceRecorder;
};

// The explicit visual fixture is the only development source. Normal
// execution uses the authenticated remote engine or stays silent; there is no
// clipboard, local, or cached fallback.
export function createSuggestionBootstrap(
  options: SuggestionBootstrapOptions,
): SuggestionCoordinator | null {
  const fixtureSource = createPrototypeSuggestionSource(
    options.environment,
    options.onSourceDecision
      ? { onDecision: options.onSourceDecision }
      : {},
  );
  const productSource = options.remoteSource ?? null;
  const source = fixtureSource ?? productSource;
  return source
    ? new SuggestionCoordinator({
        transport: source,
        send: options.send,
        ...(options.onFinalResult
          ? { onFinalResult: options.onFinalResult }
          : {}),
        ...(options.trace ? { trace: options.trace } : {}),
      })
    : null;
}
