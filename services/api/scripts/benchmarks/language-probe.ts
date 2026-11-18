// Synthetic authored drafts only. Never use captured user text in this probe.
import { gateway } from '@ai-sdk/gateway';
import { createApp } from '../../src/app';
import { GeminiSuggestionGenerator } from '../../src/models/generate';
import { realWorkloadCases } from './real-workload-comparison';
const cases = [
  ['spanish', 'Me gustaría que revisemos este problema porque'],
  ['technical-word', 'Sigue fallando cuando abro Codex'],
  ['borrowed-word', 'Ya hice el deploy'],
  ['short-spanish', 'sí, revisalo'],
  ['typos', 'salio de diez pero se pierde con los idiomas y quiero que'],
  ['intentional-switch', 'Ya funciona bien. Now I would like to'],
  ['english', 'It works now, but I would like to'],
  ['mixed', 'Bueno, makes sense, pero todavía necesito que'],
];
const app = createApp({authenticate: async () => ({userId:'synthetic-language-qa'}), generator: new GeminiSuggestionGenerator(gateway, {diagnosticsLogger:()=>{}})});
for (const [id, draft] of cases) {
 const request=structuredClone(realWorkloadCases[0]!.request);
 request.identity.requestId=crypto.randomUUID(); request.identity.timestampMs=Date.now();
 Object.assign(request.payload,{textBefore:draft,textAfter:'',selectedText:'',explicit:true,knowledge:[],artifacts:[],appId:'synthetic.qa.editor'});
 request.payload.fieldContext={shape:'multiline',label:'Reply',placeholder:'Ask anything',relatedFields:[],sources:[{id:'assistant',containerId:'thread',relation:'shared_container',text:'Assistant: The rendering fix is ready. I can investigate language selection next and compare successful and failed cases. Would you like me to proceed?'}]};
 const response=await app.request('/v1/suggestions',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(request)});
 if (!response.ok) {
   console.error(JSON.stringify({id,status:response.status,outcome:'failed'}));
   process.exit(1);
 }
 console.log(JSON.stringify({id,status:response.status,continuation:await response.text()}));
}
