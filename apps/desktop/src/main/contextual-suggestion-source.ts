import { prepareContext } from "./context-preparation";
import type { SuggestionRequest, StylePreference } from "@autocompletion/protocol";
import type { SuggestionSource } from "./suggestion-coordinator";
import type { PipelineTraceRecorder } from "./pipeline-trace";

type ContextSourceOptions = {
  context?: {prepare(id:string,query:string,appId:string,signal:AbortSignal,screenText?:string):Promise<import("@autocompletion/protocol").PreparedContext|undefined>;valid(id:string,signal:AbortSignal):Promise<boolean>};
  transport: SuggestionSource;
  isAllowed(appId: string): boolean;
  trace?: PipelineTraceRecorder;
  preferencesForApp?(appId: string): StylePreference[];
};

/** Preserve captured source relationships; enforce current user boundaries. */
export class ContextualSuggestionSource implements SuggestionSource {
  constructor(private readonly options: ContextSourceOptions) {}

  async complete(request: SuggestionRequest, signal: AbortSignal): Promise<string> {
    if (signal.aborted || !this.options.isAllowed(request.payload.appId)) return "";
    // Library is disabled. Neither acquire references nor send dormant facts.
    const { knowledge: _disabledLibrary, writingPreferences: _untrustedPreferences, preparedContext: _untrustedContext, ...captured } = request.payload;
    const preferences = this.options.preferencesForApp?.(captured.appId) ?? [];
    const contextStarted=performance.now();
    const preparedContext = this.options.context ? await prepareContext(localSignal=>this.options.context!.prepare(request.identity.requestId,captured.textBefore,captured.appId,localSignal,captured.fieldContext.sources.map(source=>source.text).join("\n")),signal) : undefined;
    signal.throwIfAborted();
    const payload = {...captured, ...(preparedContext ? {preparedContext} : {}), ...(preferences.length ? {writingPreferences: preferences} : {})};
    try {
      this.options.trace?.record({ requestId: request.identity.requestId, event: "context_prepared", attrs: {
        ms: performance.now()-contextStarted, sourceCount: payload.fieldContext.sources.length, historyCount: preparedContext?.evidence.length??0,
      } });
    } catch { /* Diagnostics cannot affect delivery. */ }
    const completion = await this.options.transport.complete({ ...request, payload }, signal);
    if(preparedContext && !await prepareContext(localSignal=>this.options.context!.valid(request.identity.requestId,localSignal),signal))return "";
    return signal.aborted || !this.options.isAllowed(payload.appId) ? "" : completion;
  }
}
