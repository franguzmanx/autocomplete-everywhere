import { preferenceExtractionRequestSchema, preferenceExtractionResponseSchema, type PreferenceExtractionRequest, type PreferenceExtractionResponse } from "@autocompletion/protocol";
import { parseSuggestionApiUrl } from "./suggestion-transport";

type Options = { apiUrl: string; tokenProvider: { getAccessToken(): Promise<string> }; request?: typeof fetch };
/** Authenticated, bounded background call. No retry, diagnostic body, or saved snippets. */
export class LearningTransport {
  private readonly origin: URL;
  constructor(private readonly options: Options) { this.origin = parseSuggestionApiUrl(options.apiUrl); }
  async extract(input: PreferenceExtractionRequest, cancellation: AbortSignal): Promise<PreferenceExtractionResponse> {
    const signal = AbortSignal.any([cancellation, AbortSignal.timeout(10_000)]);
    signal.throwIfAborted();
    // The shared token refresh may continue for a foreground request, but this
    // background operation must release its correction input immediately.
    const token = await new Promise<string>((resolve, reject) => {
      const abort = () => { signal.removeEventListener("abort", abort); reject(signal.reason); };
      signal.addEventListener("abort", abort, {once: true});
      this.options.tokenProvider.getAccessToken().then(value => {
        signal.removeEventListener("abort", abort); resolve(value);
      }, error => { signal.removeEventListener("abort", abort); reject(error); });
    });
    signal.throwIfAborted();
    const payload = preferenceExtractionRequestSchema.parse(input);
    const response = await (this.options.request ?? fetch)(new URL("/v1/preferences/extract", this.origin), {
      method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify(payload), signal,
    });
    if (!response.ok || !response.body || !response.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      await response.body?.cancel(); throw new Error("Preference extraction unavailable");
    }
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = []; let count = 0;
    try {
      while (true) {
        signal.throwIfAborted();
        const { done, value } = await reader.read();
        if (done) break;
        count += value.byteLength;
        if (count > 16_384) throw new Error("Preference extraction response too large");
        chunks.push(value);
      }
      signal.throwIfAborted();
      const result = preferenceExtractionResponseSchema.parse(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      const ids = new Set(payload.observations.map(o => o.id));
      if (result.evidence.some(e => !ids.has(e.observationId))) throw new Error("Preference extraction response invalid");
      return result;
    } finally { await reader.cancel().catch(() => {}); }
  }
}
