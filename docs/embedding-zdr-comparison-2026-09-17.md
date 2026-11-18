# Embedding ZDR route comparison — 2026-09-17

Synthetic short Spanish/English queries, sequential rotating route order, eight rounds, no retries, 15-second timeout. Requests originated from the development Mac through production-project Vercel OIDC and AI Gateway. Each request pinned one provider and required zeroDataRetention. No production configuration changed. This measures end-to-end request latency, not model-only processing, retrieval quality, or deployed-backend latency. Different output dimensions are recorded explicitly.

| Model | Provider | Successes | Failures | Median ms | Min–max ms | Dimensions |
|---|---|---:|---:|---:|---|---|
| cohere/embed-v4.0 | bedrock | 1 | 7 | 385 | 385–385 | [512] |
| cohere/embed-v4.0 | cohere | 0 | 1 | None | None–None | [] |
| alibaba/qwen3-embedding-0.6b | deepinfra | 8 | 0 | 576 | 427–704 | [1024] |
| openai/text-embedding-3-small | azure | 8 | 0 | 471.5 | 346–645 | [768] |
| openai/text-embedding-3-small | openai | 0 | 1 | None | None–None | [] |
| google/text-multilingual-embedding-002 | vertex | 8 | 0 | 512.5 | 413–988 | [768] |
| google/gemini-embedding-001 | vertex | 8 | 0 | 510 | 416–590 | [768] |
| amazon/titan-embed-text-v2 | bedrock | 8 | 0 | 441 | 281–491 | [1024] |

Cohere direct and OpenAI direct were rejected by the ZDR route filter. Cohere through Bedrock returned HTTP 429 seven times and one valid response; this is current account/route availability evidence, not a general Cohere reliability conclusion. The probe now stops further samples for a route on HTTP 429; the recorded run predates that safeguard.

Titan was fastest among routes with eight valid responses, but these results do not establish a quality winner. Compare retrieval on Autocomplete Everywhere's multilingual context cases and latency from the deployed backend before switching. Cohere does not natively provide the currently planned 768 dimensions; its successful response was 512. Existing vectors cannot be reused across different embedding models.

Preparation should stay asynchronous: current context and exact matches remain available while semantic indexing/query preparation is pending.

Sources:
- https://ai-gateway.vercel.sh/v1/models
- https://vercel.com/docs/ai-gateway/security-and-compliance/zdr
- https://vercel.com/ai-gateway/models/embed-v4.0
- https://vercel.com/ai-gateway/models/titan-embed-text-v2
