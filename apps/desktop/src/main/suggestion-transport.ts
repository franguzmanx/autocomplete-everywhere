import { TransformOutputSchema, type TransformInput } from "@autocompletion/protocol";
import type { SuggestionOutcomeEvent } from "./suggestion-activity";
import { generationFailureKindSchema, generationFailureReasonSchema, maximumInsertionCharacters, type SuggestionRequest } from "@autocompletion/protocol";

import {
  SuggestionRequestFailure,
  type SuggestionSource,
} from "./suggestion-coordinator";
import type {
  DesktopTraceRecord,
  PipelineTraceRecorder,
} from "./pipeline-trace";

type AccessTokenProvider = {
  getAccessToken(forceRefresh?: boolean): Promise<string>;
};

type HttpSuggestionTransportOptions = {
  apiUrl: string;
  tokenProvider: AccessTokenProvider;
  request?: typeof fetch;
  trace?: PipelineTraceRecorder;
  monotonicNow?: () => number;
};

const SUGGESTION_REQUEST_DEADLINE_MS = 10_000;

type SuggestionAttempt = "initial" | "refresh";
type AbortStage = "token" | "http" | "body";

type TracedSuggestionResponse = {
  response: Response;
  finish(result: "complete" | "unauthorized" | "error"): void;
};

export function parseSuggestionApiUrl(value: string): URL {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash ||
    url.hostname === "127.0.0.1" ||
    url.hostname === "localhost"
  ) {
    throw new Error("Suggestion API must be a canonical public HTTPS origin");
  }
  return url;
}

export class HttpSuggestionTransport implements SuggestionSource {
  private readonly origin: URL;
  private readonly request: typeof fetch;
  private readonly monotonicNow: () => number;

  constructor(private readonly options: HttpSuggestionTransportOptions) {
    this.origin = parseSuggestionApiUrl(options.apiUrl);
    this.request = options.request ?? fetch;
    this.monotonicNow = options.monotonicNow ?? (() => performance.now());
  }

  async transform(input: TransformInput, signal: AbortSignal): Promise<string> {
    const init = (): RequestInit => ({ method: "POST", headers: { "content-type": "application/json", accept: "application/json" }, body: JSON.stringify(input), signal });
    let response = await this.authorizedRequest("/v1/transforms", init(), false);
    if (response.status === 401 && !signal.aborted) {
      await response.body?.cancel();
      response = await this.authorizedRequest("/v1/transforms", init(), true);
    }
    if (!response.ok || !response.body || !response.headers.get("content-type")?.startsWith("application/json")) {
      await response.body?.cancel();
      throw new Error("Transform unavailable");
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder("utf-8", { fatal: true });
    let body = "";
    let bytes = 0;
    try {
      while (true) {
        const next = await reader.read();
        if (next.done) break;
        bytes += next.value.byteLength;
        if (bytes > 64_000) throw new Error("Transform response too large");
        body += decoder.decode(next.value, { stream: true });
      }
      body += decoder.decode();
      return TransformOutputSchema.parse(JSON.parse(body)).text;
    } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  }

  /// Ships content-free outcome events. The caller batches and drops on
  /// failure. One deadline includes token acquisition, HTTP, and one 401 refresh.
  async recordSuggestionOutcomes(events: SuggestionOutcomeEvent[], signal: AbortSignal): Promise<void> {
    if (events.length === 0) return;
    const deadline = new AbortController();
    const timer = setTimeout(() => deadline.abort(new Error("outcome_upload_timeout")), 10_000);
    const requestSignal = AbortSignal.any([signal, deadline.signal]);
    try {
      await this.authorizedJson(
        "/v1/suggestions/outcomes",
        "POST",
        { events },
        "Suggestion outcomes could not be recorded",
        requestSignal,
      );
    } finally {
      clearTimeout(timer);
    }
  }

  private async authorizedJson(
    path: string,
    method: "PUT" | "POST",
    body: unknown,
    failureMessage: string,
    signal: AbortSignal,
  ): Promise<void> {
    const init = (): RequestInit => ({
      signal,
      method,
      headers: {
        accept: "application/json",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
    let response = await this.authorizedRequest(path, init(), false);
    if (response.status === 401) {
      if (response.body) await abortable(response.body.cancel(), signal);
      response = await this.authorizedRequest(path, init(), true);
    }
    if (!response.ok) {
      if (response.body) await abortable(response.body.cancel(), signal);
      throw new Error(failureMessage);
    }
    if (response.body) await abortable(response.body.cancel(), signal);
  }


  private async authorizedRequest(
    path: string,
    init: RequestInit,
    forceRefresh: boolean,
  ): Promise<Response> {
    let token: string;
    try {
      init.signal?.throwIfAborted();
      const pendingToken = this.options.tokenProvider.getAccessToken(forceRefresh);
      token = init.signal ? await abortable(pendingToken, init.signal) : await pendingToken;
    } catch {
      throw new SuggestionRequestFailure("unauthorized", false);
    }

    try {
      init.signal?.throwIfAborted();
      const headers = new Headers(init.headers);
      headers.set("authorization", `Bearer ${token}`);
      const pendingResponse = this.request(new URL(path, this.origin), {
        ...init,
        headers: {
          ...Object.fromEntries(headers.entries()),
        },
      });
      return init.signal ? await abortable(pendingResponse, init.signal) : await pendingResponse;
    } catch (error) {
      if (init.signal?.aborted) throw error;
      throw new SuggestionRequestFailure("network", true);
    }
  }

  async complete(
    request: SuggestionRequest,
    signal: AbortSignal,
  ): Promise<string> {
    const timeoutController = new AbortController();
    const timeout = setTimeout(
      () => timeoutController.abort(new Error("suggestion_request_timeout")),
      SUGGESTION_REQUEST_DEADLINE_MS,
    );
    const requestSignal = AbortSignal.any([signal, timeoutController.signal]);
    let abortStage: AbortStage = "token";
    try {
      let tracedResponse = await this.post(
        request,
        requestSignal,
        false,
        (stage) => {
          abortStage = stage;
        },
      );
      let response = tracedResponse.response;
      if (response.status === 401) {
        await response.body?.cancel();
        tracedResponse.finish("unauthorized");
        tracedResponse = await this.post(
          request,
          requestSignal,
          true,
          (stage) => {
            abortStage = stage;
          },
        );
        response = tracedResponse.response;
      }
      if (response.status === 401) {
        await response.body?.cancel();
        tracedResponse.finish("unauthorized");
        throw new SuggestionRequestFailure("unauthorized", false);
      }
      if (!response.ok || !response.body) {
        tracedResponse.finish("error");
        throw new SuggestionRequestFailure("server", response.status >= 500);
      }

      const contentType = response.headers.get("content-type") ?? "";
      if (!contentType.toLowerCase().startsWith("text/plain")) {
        await response.body.cancel();
        tracedResponse.finish("error");
        throw new SuggestionRequestFailure("server", false);
      }

      let result: "complete" | "error" = "complete";
      try {
        const bytes = await response.arrayBuffer();
        const completion = new TextDecoder("utf-8", { fatal: true }).decode(
          bytes,
        );
        if (completion.length > maximumInsertionCharacters(request)) {
          throw new SuggestionRequestFailure("server", false);
        }
        return completion;
      } catch (error) {
        result = "error";
        if (requestSignal.aborted) throw error;
        if (error instanceof SuggestionRequestFailure) throw error;
        if (error instanceof TypeError && error.message.includes("encoded data")) {
          throw new SuggestionRequestFailure("server", false);
        }
        throw new SuggestionRequestFailure("network", true);
      } finally {
        tracedResponse.finish(result);
      }
    } catch (error) {
      if (requestSignal.aborted) {
        this.trace({
          requestId: request.identity.requestId,
          event: "aborted",
          attrs: {
            reason: timeoutController.signal.aborted
              ? "timeout"
              : abortReason(signal.reason),
            stage: abortStage,
          },
        });
      }
      if (timeoutController.signal.aborted && !signal.aborted) {
        throw new SuggestionRequestFailure("timeout", true);
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  private async post(
    request: SuggestionRequest,
    signal: AbortSignal,
    forceRefresh: boolean,
    onStage: (stage: AbortStage) => void,
  ): Promise<TracedSuggestionResponse> {
    const requestId = request.identity.requestId;
    const attempt: SuggestionAttempt = forceRefresh ? "refresh" : "initial";
    onStage("token");
    const tokenStartedAt = this.monotonicNow();
    let token: string;
    try {
      token = await this.options.tokenProvider.getAccessToken(forceRefresh);
    } catch (error) {
      const unauthorized = error instanceof Error && (error.message === "unauthorized" || /OAuth token refresh failed with status (400|401|403)/.test(error.message));
      throw new SuggestionRequestFailure(unauthorized ? "unauthorized" : "network", !unauthorized);
    }
    this.trace({
      requestId,
      event: "token_ready",
      attrs: {
        source: forceRefresh ? "refresh" : "store",
        ms: elapsedMs(tokenStartedAt, this.monotonicNow()),
      },
    });
    if (signal.aborted) throw signal.reason;

    onStage("http");
    const httpStartedAt = this.monotonicNow();
    this.trace({ requestId, event: "http_start", attrs: { attempt } });
    let response: Response;
    try {
      response = await this.request(new URL("/v1/suggestions", this.origin), {
        method: "POST",
        headers: {
          accept: "text/plain",
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(request),
        signal,
      });
    } catch (error) {
      this.trace({
        requestId,
        event: "http_end",
        attrs: {
          attempt,
          totalMs: elapsedMs(httpStartedAt, this.monotonicNow()),
          result: "error",
        },
      });
      if (signal.aborted) throw error;
      throw new SuggestionRequestFailure("network", true);
    }

    onStage("body");
    const failureKind = response.status === 502
      ? generationFailureKindSchema.safeParse(response.headers.get("x-autocompletion-failure-kind")).data : undefined;
    const failureReason = response.status === 502
      ? generationFailureReasonSchema.safeParse(response.headers.get("x-autocompletion-failure-reason")).data : undefined;
    this.trace({
      requestId,
      event: "http_headers",
      attrs: {
        attempt,
        status: response.status,
        ttfbMs: elapsedMs(httpStartedAt, this.monotonicNow()),
        ...(failureKind ? { failureKind } : {}),
        ...(failureReason ? { failureReason } : {}),
      },
    });
    let finished = false;
    return {
      response,
      finish: (result) => {
        if (finished) return;
        finished = true;
        this.trace({
          requestId,
          event: "http_end",
          attrs: {
            attempt,
            status: response.status,
            totalMs: elapsedMs(httpStartedAt, this.monotonicNow()),
            result,
          },
        });
      },
    };
  }

  private trace(record: DesktopTraceRecord): void {
    try {
      this.options.trace?.record(record);
    } catch {
      // Observability cannot affect requests.
    }
  }
}

function elapsedMs(start: number, end: number): number {
  return Math.max(0, end - start);
}

function abortReason(reason: unknown): "cancel" | "supersede" | "shutdown" {
  if (reason === "supersede" || reason === "shutdown") return reason;
  return "cancel";
}

// Release the telemetry operation even if secure-store, token refresh, or a
// response-body promise does not itself support cancellation. Late completion
// cannot resume authorization or hold the uploader's pending queue hostage.
function abortable<T>(pending: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const aborted = () => { reject(signal.reason); };
    signal.addEventListener("abort", aborted, { once: true });
    pending.then(resolve, reject).finally(() => signal.removeEventListener("abort", aborted));
    if (signal.aborted) { signal.removeEventListener("abort", aborted); aborted(); }
  });
}
