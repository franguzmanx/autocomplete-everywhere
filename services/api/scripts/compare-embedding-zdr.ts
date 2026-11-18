/** Synthetic latency probe. No production settings or private content are used. */
import { embed } from "ai";
import { gateway } from "@ai-sdk/gateway";

const candidates = [
  { model: "cohere/embed-v4.0", provider: "bedrock" },
  { model: "cohere/embed-v4.0", provider: "cohere" },
  { model: "alibaba/qwen3-embedding-0.6b", provider: "deepinfra" },
  { model: "openai/text-embedding-3-small", provider: "azure" },
  { model: "openai/text-embedding-3-small", provider: "openai" },
  { model: "google/text-multilingual-embedding-002", provider: "vertex" },
  { model: "google/gemini-embedding-001", provider: "vertex" },
  { model: "amazon/titan-embed-text-v2", provider: "bedrock" },
];
const inputs = [
  "¿Cuándo revisamos el diseño del formulario?",
  "Find the discussion about moving the design review to Tuesday.",
  "El error de autenticación aparece al volver de suspensión.",
  "Which pull request fixes the keyboard shortcut?",
  "La propuesta azul conserva el espacio para comentarios.",
  "Locate the message about the revised deployment date.",
  "¿Qué habíamos decidido sobre las etiquetas del panel?",
  "The component needs accessible labels and a visible focus state.",
];
const results = candidates.map(candidate => ({ ...candidate, times: [] as number[], dimensions: [] as number[], failures: 0, disabled: false }));
// Rotate sequential requests so concurrency and candidate ordering do not bias latency.
for (let round = 0; round < inputs.length; round++) {
  for (let i = 0; i < results.length; i++) {
    const c = results[(i + round) % results.length]!;
    if (c.disabled) continue;
    const start = performance.now();
    try {
      const r = await embed({
        model: gateway.embeddingModel(c.model), value: inputs[round]!,
        maxRetries: 0, abortSignal: AbortSignal.timeout(15000),
        providerOptions: {
          gateway: { only: [c.provider], zeroDataRetention: true },
          cohere: { inputType: "search_query", outputDimension: 512 },
          google: { outputDimensionality: 768 },
          vertex: { outputDimensionality: 768 },
          openai: { dimensions: 768 },
          azure: { dimensions: 768 },
        },
      });
      if (!r.embedding.length || !r.embedding.every(Number.isFinite)) throw new Error("Invalid vector");
      const ms = Math.round(performance.now() - start);
      c.times.push(ms); c.dimensions.push(r.embedding.length);
      console.log(JSON.stringify({ kind: "sample", model: c.model, provider: c.provider, round, ms, dimensions: r.embedding.length }));
    } catch (e) {
      const error = e as { statusCode?: number; message?: string };
      c.failures++;
      const noRoute = /No ZDR|no_providers_available/i.test(error.message ?? "");
      // Do not keep probing a rate-limited provider in subsequent rounds.
      if (noRoute || error.statusCode === 400 || error.statusCode === 429) c.disabled = true;
      console.log(JSON.stringify({ kind: "failure", model: c.model, provider: c.provider, round, status: error.statusCode, noRoute }));
    }
  }
}
for (const c of results) {
  const sorted = [...c.times].sort((a,b) => a-b);
  const n = sorted.length;
  console.log(JSON.stringify({ kind: "summary", model: c.model, provider: c.provider, zeroDataRetention: true,
    successes: n, failures: c.failures, dimensions: [...new Set(c.dimensions)],
    medianMs: n ? (sorted[Math.floor((n-1)/2)]! + sorted[Math.floor(n/2)]!)/2 : null,
    minMs: sorted[0] ?? null, maxMs: sorted[n-1] ?? null }));
}
