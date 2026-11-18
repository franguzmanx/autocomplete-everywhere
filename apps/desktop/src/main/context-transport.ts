import { parseSuggestionApiUrl } from "./suggestion-transport";
export class ContextRequestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly retryAfterMs?: number,
  ) {
    super("Context request unavailable");
  }
}
/** All context operations are authenticated; no request/response content is logged. */
export class ContextTransport {
  private origin: URL;
  constructor(
    private options: {
      apiUrl: string;
      tokenProvider: { getAccessToken(): Promise<string> };
      request?: typeof fetch;
    },
  ) {
    this.origin = parseSuggestionApiUrl(options.apiUrl);
  }
  async call<T>(
    path: string,
    payload: unknown,
    cancellation: AbortSignal,
  ): Promise<T> {
    const signal = AbortSignal.any([cancellation, AbortSignal.timeout(20_000)]);
    signal.throwIfAborted();
    const token = await this.options.tokenProvider.getAccessToken();
    signal.throwIfAborted();
    const response = await (this.options.request ?? fetch)(
      new URL("/v1/context/" + path, this.origin),
      {
        method: "POST",
        redirect: "error",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
        signal,
      },
    );
    if (!response.headers.get("content-type")?.includes("application/json")) {
      await response.body?.cancel();
      throw new ContextRequestError(response.status, "invalid_response");
    }
    const reader = response.body?.getReader();
    if (!reader) throw new Error("Context response unavailable");
    let size = 0;
    const chunks: Uint8Array[] = [];
    try {
      while (true) {
        signal.throwIfAborted();
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 1_000_000) throw new Error("Context response too large");
        chunks.push(value);
      }
      const result = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      if (!response.ok) {
        const allowed = [
          "authorization_revoked",
          "unauthorized",
          "rate_limited",
          "permission_denied",
          "resource_unavailable",
        ];
        const code = allowed.includes(result?.error)
          ? result.error
          : "unavailable";
        const retry = response.headers.get("retry-after");
        const delay =
          retry === null
            ? undefined
            : /^\d+$/.test(retry)
              ? Number(retry) * 1000
              : Date.parse(retry) - Date.now();
        throw new ContextRequestError(
          response.status,
          code,
          delay !== undefined && Number.isFinite(delay)
            ? Math.max(0, delay)
            : undefined,
        );
      }
      return result as T;
    } finally {
      await reader.cancel().catch(() => {});
    }
  }
}
