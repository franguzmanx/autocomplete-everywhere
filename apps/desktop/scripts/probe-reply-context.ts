// Run with Electron after bundling with Bun --target=node --format=cjs --external electron.
// Requires an existing, unexpired Autocomplete Everywhere session. Never refreshes or writes its store.
// Exactly four maximum API calls, one per case; lexical checks are not a semantic quality verdict.
// One-shot, read-only-session QA. No draft, completion, or credential logging.
import { app } from 'electron';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { SecureStore } from '../src/main/secure-store';
import { OAuthTokenProvider, type StoredProductData } from '../src/main/oauth-token-provider';
import { resolveDesktopRuntimeConfig } from '../src/main/runtime-config';
import { HttpSuggestionTransport } from '../src/main/suggestion-transport';
import { SuggestionRequestFailure } from '../src/main/suggestion-coordinator';
import { generationFailureKindSchema, generationFailureReasonSchema, type SuggestionRequest } from '../../../packages/protocol/src';

app.setName('Autocomplete Everywhere');
const emit = (value: unknown) => process.stdout.write(JSON.stringify(value) + '\n');
let calls = 0;
const timer = setTimeout(() => { emit({outcome:'probe_deadline',calls}); app.exit(2); }, 55_000);
async function main() {
  await app.whenReady();
  app.dock?.hide();
  const config = resolveDesktopRuntimeConfig(process.env);
  const store = new SecureStore(join(homedir(),'Library/Application Support/Autocomplete Everywhere/secure/product-state.bin'));
  const tokens = new OAuthTokenProvider({
    store: { read: () => store.read<StoredProductData>(), write: async () => { throw new Error('probe_read_only'); } },
    tokenEndpoint: config.tokenEndpoint, clientId: config.clientId,
    request: async () => { throw new Error('probe_refresh_disabled'); },
  });
  // Preflight normal session, failing closed if it requires refresh. Never print it.
  await tokens.getAccessToken();
  const cases = [
    {id:'reply_with_source', draft:'sí', source:'Assistant: ¿Querés que compare los intentos exitosos con los fallidos para encontrar la causa?'},
    {id:'reply_without_source', draft:'sí', source:''},
    {id:'corrected_source', draft:'Sí, confirmo que la entrega será el', source:'Assistant: La entrega sería el martes.\nUser: Corrección: la entrega es el viernes, no el martes.\nAssistant: Entendido, la fecha corregida es el viernes. ¿Confirmás esa fecha?'},
    {id:'unrelated_feed', draft:'Yes, give me', source:'Assistant: Would you like a short summary of the test failures?'}
  ];
  for (const item of cases) {
    let attemptCalls = 0;
    let status: number | null = null;
    let failureKind: string | null = null;
    let failureReason: string | null = null;
    const transport = new HttpSuggestionTransport({apiUrl:config.apiUrl,tokenProvider:tokens,
      request: async (input, init) => {
        if (String(input) !== new URL('/v1/suggestions',config.apiUrl).href || attemptCalls >= 1 || calls >= 4) throw new Error('probe_request_boundary');
        attemptCalls++; calls++;
        const response = await fetch(input,{...init,redirect:'error'});
        status=response.status;
        const kind=response.headers.get('x-autocompletion-failure-kind');
        const reason=response.headers.get('x-autocompletion-failure-reason');
        failureKind=generationFailureKindSchema.safeParse(kind).data ?? null;
        failureReason=generationFailureReasonSchema.safeParse(reason).data ?? null;
        return response;
      }
    });
    const request: SuggestionRequest = {
      protocolVersion:5,type:'suggestion_request',identity:{requestId:randomUUID(),focusSequence:1,contentSignature:'synthetic-'+item.id,timestampMs:Date.now()},
      payload:{appId:'synthetic.qa.editor',surface:'text_editor',textBefore:item.draft,textAfter:'',selectedText:'',explicit:true,artifacts:[],
        fieldContext:{shape:'multiline',label:'Reply',relatedFields:[],sources:item.source ? [
          {id:'current-message',containerId:'active-conversation',relation:'shared_container',text:item.source},
          ...(item.id==='unrelated_feed' ? [{id:'feed-item',containerId:'unrelated-feed',relation:'shared_container' as const,text:'Sponsored: annual plan costs $99. Buy now.'}]:[])
        ]:[]}}
    };
    const started=performance.now();
    try {
      const text=await transport.complete(request,AbortSignal.timeout(11_000));
      emit({caseId:item.id,requestId:request.identity.requestId,status,outcome:text.length?'text':'silence',characters:text.length,ms:Math.round(performance.now()-started),calls:attemptCalls,
        checks:text.length ? {
          hasAssistantRole:/\b(assistant|asistente)\s*:/i.test(text),
          ...(item.id==='reply_with_source'?{mentionsComparisonOrInvestigation:/compar|intent|fall|caus|investig/i.test(text)}:{}),
          ...(item.id==='corrected_source'?{mentionsCorrectedDay:/\bviernes\b/i.test(text),mentionsSupersededDay:/\bmartes\b/i.test(text)}:{}),
          ...(item.id==='unrelated_feed'?{mentionsUnrelatedPrice:/99|\$/.test(text),mentionsSummaryOrTests:/summar|test|fail/i.test(text)}:{})
        }:null});
    } catch(error) {
      emit({caseId:item.id,requestId:request.identity.requestId,status,failureKind,failureReason,outcome:error instanceof SuggestionRequestFailure ? error.code:'probe_failure',ms:Math.round(performance.now()-started),calls:attemptCalls});
    }
  }
  emit({outcome:'probe_complete',calls});
}
main().then(()=>{clearTimeout(timer);app.exit(0)}).catch(()=>{emit({outcome:'session_preflight_unavailable',calls});clearTimeout(timer);app.exit(2)});
