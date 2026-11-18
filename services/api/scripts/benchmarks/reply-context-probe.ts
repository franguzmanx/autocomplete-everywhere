// Synthetic, bounded probe of the production generation and response path.
// Prints outcomes and timings only; never credentials, drafts, or model text.
import { gateway } from '@ai-sdk/gateway';
import { createApp } from '../../src/app';
import { GeminiSuggestionGenerator } from '../../src/models/generate';
import { realWorkloadCases } from './real-workload-comparison';

const provider = gateway;
const app = createApp({ authenticate: async () => ({ userId: 'synthetic-reply-context-probe' }),
  generator: new GeminiSuggestionGenerator(provider, {
    diagnosticsLogger: entry => console.log(JSON.stringify(entry)),
  }),
});
for (let repetition = 0; repetition < 2; repetition++) {
  for (const withSource of [false, true]) {
    const request = structuredClone(realWorkloadCases[0]!.request);
    request.identity.requestId = crypto.randomUUID();
    request.identity.timestampMs = Date.now();
    request.payload.appId = 'synthetic.qa.editor';
    request.payload.textBefore = 'sí';
    request.payload.textAfter = '';
    request.payload.explicit = true;
    request.payload.knowledge = [];
    request.payload.artifacts = [];
    request.payload.fieldContext = { shape: 'multiline', label: 'Reply', relatedFields: [],
      sources: withSource ? [{ id: 'assistant-message', containerId: 'active-conversation', relation: 'shared_container',
        text: 'Assistant: ¿Querés que compare los intentos exitosos con los fallidos para encontrar la causa?' }] : [],
    };
    const start = performance.now();
    const response = await app.request('/v1/suggestions', { method: 'POST',
      headers: { 'content-type': 'application/json' }, body: JSON.stringify(request) });
    const body = await response.text();
    console.log(JSON.stringify({ repetition, withSource, status: response.status,
      outcome: response.ok ? body.length ? 'text' : 'silence' : 'failure',
      characters: response.ok ? body.length : null, ms: Math.round(performance.now() - start) }));
    if (!response.ok) process.exit(1);
  }
}
