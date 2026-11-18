import { expect, it } from "vitest";
import { ContextModels } from "../src/context/models.js";
it("pins visual and multilingual embeddings to Vertex ZDR and requests exactly 768 dimensions", async () => {
  const events: unknown[] = [];
  const provider = Object.assign((id: string) => id, {
    embeddingModel: (id: string) => id,
  }) as never;
  const generate = ((options: Record<string, unknown>) => {
    expect(options).toMatchObject({
      model: "google/gemini-3.5-flash-lite",
      maxRetries: 0,
      providerOptions: {
        gateway: { only: ["vertex"], zeroDataRetention: true },
      },
    });
    return {
      text: "derived observation",
      finishReason: "stop",
      usage: { totalTokens: 20 },
    };
  }) as never;
  const embed = ((options: Record<string, unknown>) => {
    expect(options).toMatchObject({
      model: "google/text-multilingual-embedding-002",
      maxRetries: 0,
      providerOptions: {
        gateway: { only: ["vertex"], zeroDataRetention: true },
        vertex: { outputDimensionality: 768 },
      },
    });
    expect(options.providerOptions).toEqual({
      gateway: { only: ["vertex"], zeroDataRetention: true },
      vertex: { outputDimensionality: 768 },
    });
    return { embedding: Array(768).fill(0), usage: { tokens: 4 } };
  }) as never;
  const models = new ContextModels(
    provider,
    (event) => events.push(event),
    generate,
    embed,
  );
  await models.visual(
    { imageBase64: "YWJj", mimeType: "image/png" },
    new AbortController().signal,
  );
  expect(
    (await models.embedding("private text", new AbortController().signal))
      .embedding,
  ).toHaveLength(768);
  expect(events).toHaveLength(2);
  expect(JSON.stringify(events)).not.toMatch(/private|observation|YWJj/);
});
it("reports errors and cancellation without invented tokens, prices or provider messages", async () => {
  const provider = Object.assign((id: string) => id, {
      embeddingModel: (id: string) => id,
    }) as never,
    events: unknown[] = [];
  const controller = new AbortController();
  const models = new ContextModels(
    provider,
    (event) => events.push(event),
    undefined,
    (async () => {
      throw new Error("PRIVATE response");
    }) as never,
  );
  await expect(
    models.embedding("PRIVATE source", controller.signal),
  ).rejects.toThrow();
  controller.abort();
  await expect(
    models.embedding("PRIVATE source", controller.signal),
  ).rejects.toThrow();
  expect(events).toEqual([
    expect.objectContaining({ operation: "embedding", result: "error" }),
    expect.objectContaining({ operation: "embedding", result: "cancelled" }),
  ]);
  expect(JSON.stringify(events)).not.toMatch(/PRIVATE|tokens|costUsd/);
});
it("accepts only numeric Gateway reported costs and excludes arbitrary metadata", async () => {
  const { reportedCost, reportBackground } = await import(
    "../src/context/telemetry.js"
  );
  const events: unknown[] = [];
  expect(reportedCost({ gateway: { cost: "0.000012" } })).toBe(0.000012);
  expect(reportedCost({ gateway: { cost: "secret" } })).toBeUndefined();
  expect(reportedCost({ gateway: { cost: -1 } })).toBeUndefined();
  reportBackground((event) => events.push(event), {
    operation: "learning",
    result: "success",
    durationMs: 2,
    tokens: 5,
    costUsd: 0.000012,
    private: "secret",
  } as never);
  expect(events).toEqual([
    {
      operation: "learning",
      result: "success",
      durationMs: 2,
      tokens: 5,
      costUsd: 0.000012,
    },
  ]);
});
