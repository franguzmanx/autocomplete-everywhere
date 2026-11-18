/** Synthetic comparison only. Does not change the production model or ZDR policy. */
import { embed } from "ai";
import { gateway } from "@ai-sdk/gateway";
for (const candidate of [
  { model: "google/gemini-embedding-2", provider: "google" },
  { model: "google/gemini-embedding-001", provider: "vertex" },
]) {
  const start = performance.now();
  try {
    const result = await embed({
      model: gateway.embeddingModel(candidate.model),
      value: "Synthetic reference: the design review is on Tuesday. Referencia: la revisión de diseño es el martes.",
      maxRetries: 0,
      abortSignal: AbortSignal.timeout(20000),
      providerOptions: {
        gateway: { only: [candidate.provider], zeroDataRetention: true },
        google: { outputDimensionality: 768 },
        vertex: { outputDimensionality: 768 },
      },
    });
    console.log(JSON.stringify({ ...candidate, zeroDataRetention: true,
      success: result.embedding.length === 768 && result.embedding.every(Number.isFinite),
      dimensions: result.embedding.length, tokens: result.usage.tokens,
      ms: Math.round(performance.now() - start) }));
  } catch (error) {
    const value = error as { statusCode?: number; message?: string };
    console.log(JSON.stringify({ ...candidate, zeroDataRetention: true, success: false,
      status: value.statusCode, noZdrRoute: /No ZDR|no_providers_available/i.test(value.message ?? ""),
      ms: Math.round(performance.now() - start) }));
  }
}
