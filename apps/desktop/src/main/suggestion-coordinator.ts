import {
  PROTOCOL_VERSION,
  maximumInsertionCharacters,
  type ProtocolMessage,
  type SuggestionRequest,
  type WorkIdentity,
} from "@autocompletion/protocol";

import type { PipelineTraceRecorder } from "./pipeline-trace";

export type SuggestionFailureCode =
  | "unauthorized"
  | "network"
  | "timeout"
  | "server";

export class SuggestionRequestFailure extends Error {
  constructor(
    readonly code: SuggestionFailureCode,
    readonly retryable: boolean,
  ) {
    super(code);
    this.name = "SuggestionRequestFailure";
  }
}

export type SuggestionSource = {
  complete(request: SuggestionRequest, signal: AbortSignal): Promise<string>;
};

export type SuggestionCoordinatorFinalResult = "text" | "silence";

type SuggestionCoordinatorDependencies = {
  transport: SuggestionSource;
  send(message: ProtocolMessage): void;
  onFinalResult?: (result: SuggestionCoordinatorFinalResult) => void;
  trace?: PipelineTraceRecorder;
};

type ActiveSuggestion = {
  identity: WorkIdentity;
  controller: AbortController;
};

export class SuggestionCoordinator {
  private active: ActiveSuggestion | null = null;
  private lastAutomaticEdit: { focusSequence: number; at: number } | null = null;
  private static readonly editQuietMs = 250;

  constructor(private readonly dependencies: SuggestionCoordinatorDependencies) {}

  handle(message: ProtocolMessage): void {
    if (message.type === "suggestion_request") {
      this.trace({
        requestId: message.identity.requestId,
        event: "request_received",
        attrs: {
          focusSequence: message.identity.focusSequence,
          explicit: message.payload.explicit,
          artifactCount: message.payload.artifacts.length,
          recentWritingCount: message.payload.artifacts.filter(
            (artifact) => artifact.kind === "recent_writing" || artifact.kind === "accepted_completion",
          ).length,
        },
      });
      this.start(message);
      return;
    }
    if (
      message.type === "cancel_request" &&
      this.active &&
      sameIdentity(message.identity, this.active.identity)
    ) {
      this.active.controller.abort("cancel");
      this.active = null;
    }
  }

  invalidate(requestIds: string[]): void {
    if(this.active && requestIds.includes(this.active.identity.requestId))this.stop();
  }

  stop(): void {
    this.lastAutomaticEdit = null;
    this.active?.controller.abort();
    this.active = null;
  }

  private start(request: SuggestionRequest): void {
    this.active?.controller.abort("supersede");
    const session: ActiveSuggestion = {
      identity: request.identity,
      controller: new AbortController(),
    };
    this.active = session;
    const now = performance.now();
    const previous = this.lastAutomaticEdit;
    const coalesce = !request.payload.explicit && previous?.focusSequence === request.identity.focusSequence
      && now - previous.at < SuggestionCoordinator.editQuietMs;
    this.lastAutomaticEdit = request.payload.explicit ? null : {focusSequence: request.identity.focusSequence, at: now};
    void this.run(session, request, coalesce);
  }

  private async run(
    session: ActiveSuggestion,
    request: SuggestionRequest,
    coalesce: boolean,
  ): Promise<void> {
    // The first request is immediate. During a typing burst, replace pending
    // work before it reaches the provider: aborting HTTP does not refund quota.
    if (coalesce) {
      await new Promise<void>(resolve => {
        const done = () => {
          clearTimeout(timer);
          session.controller.signal.removeEventListener("abort", done);
          resolve();
        };
        const timer = setTimeout(done, SuggestionCoordinator.editQuietMs);
        session.controller.signal.addEventListener("abort", done, {once: true});
        if (session.controller.signal.aborted) done();
      });
      if (!this.isCurrent(session)) return;
    }
    let completion = "";
    try {
      completion = await this.dependencies.transport.complete(
        request,
        session.controller.signal,
      );
      if (
        completion.length > maximumInsertionCharacters(request) ||
        (completion.length > 0 && !completion.trim())
      ) {
        throw new SuggestionRequestFailure("server", false);
      }
    } catch (error) {
      if (!this.isCurrent(session)) return;
      this.active = null;
      const failure =
        error instanceof SuggestionRequestFailure
          ? error
          : new SuggestionRequestFailure("network", true);
      this.dependencies.send({
        protocolVersion: PROTOCOL_VERSION,
        type: "request_failed",
        identity: session.identity,
        payload: { code: failure.code, retryable: failure.retryable },
      });
      this.trace({
        requestId: session.identity.requestId,
        event: "helper_write",
        attrs: { result: "failed" },
      });
      return;
    }

    if (!this.isCurrent(session)) return;
    this.active = null;
    const finalResult: SuggestionCoordinatorFinalResult = completion
      ? "text"
      : "silence";
    try {
      this.dependencies.onFinalResult?.(finalResult);
    } catch {
      // Diagnostics cannot affect the coordinator result.
    }
    this.dependencies.send({
      protocolVersion: PROTOCOL_VERSION,
      type: "suggestion_final",
      identity: session.identity,
      payload: completion
        ? { text: completion }
        : { silenceReason: "not_useful" },
    });
    this.trace({
      requestId: session.identity.requestId,
      event: "helper_write",
      attrs: { result: finalResult },
    });
  }

  private isCurrent(session: ActiveSuggestion): boolean {
    return this.active === session && !session.controller.signal.aborted;
  }

  private trace(
    record: Parameters<NonNullable<SuggestionCoordinatorDependencies["trace"]>["record"]>[0],
  ): void {
    try {
      this.dependencies.trace?.record(record);
    } catch {
      // Observability cannot affect suggestion delivery.
    }
  }
}

function sameIdentity(left: WorkIdentity, right: WorkIdentity): boolean {
  return (
    left.requestId === right.requestId &&
    left.focusSequence === right.focusSequence &&
    left.contentSignature === right.contentSignature &&
    left.timestampMs === right.timestampMs
  );
}
