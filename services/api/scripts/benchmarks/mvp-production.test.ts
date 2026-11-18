import { expect, test, vi } from "vitest";
import { generateText } from "ai";
vi.mock("ai", async () => ({...await vi.importActual<typeof import("ai")>("ai"), generateText: vi.fn()}));
import { realWorkloadCases, runMvpProductionSample } from "./real-workload-comparison";

test("MVP baseline uses the real generator settings and exactly one final call", async () => {
  const generate = vi.fn(async () => ({ output: { offer: true, parts: [{ text: "Synthetic continuation." }] }, usage: { inputTokens: 100, outputTokens: 12 } }));
  const result = await runMvpProductionSample(realWorkloadCases[0]!, "baseline", generate);
  expect(generate).toHaveBeenCalledTimes(1);
  const options = generate.mock.calls[0]![0] as unknown as Record<string, unknown>;
  expect(options).toMatchObject({ timeout: 8000, maxRetries: 0, maxOutputTokens: 4096, temperature: 0.2, providerOptions: { google: { thinkingConfig: { thinkingLevel: "low", includeThoughts: false } } } });
  expect(result).toMatchObject({ outcome: "text", output: "Synthetic continuation.", inputTokens: 100, outputTokens: 12, calls: 1, useful: null });
});

test("compact JSON is benchmark-only and preserves the writing state exactly", async () => {
  const calls: Record<string, unknown>[] = [];
  const generate = async (options: Record<string, unknown>) => { calls.push(options); return { output: { offer: false, parts: [] } }; };
  await runMvpProductionSample(realWorkloadCases[0]!, "baseline", generate);
  await runMvpProductionSample(realWorkloadCases[0]!, "compact-json", generate);
  const state = (prompt: unknown) => JSON.parse(String(prompt).split("WRITING_STATE_JSON\n")[1]!.split("\nEND_WRITING_STATE_JSON")[0]!);
  expect(state(calls[0]!.prompt)).toEqual(state(calls[1]!.prompt));
  expect(String(calls[1]!.prompt).length).toBeLessThan(String(calls[0]!.prompt).length);
  expect(calls[0]!.instructions).toEqual(calls[1]!.instructions);
});

test("failed attempts remain failures and are never retried or counted as silence", async () => {
  const generate = vi.fn(async () => ({ output: { offer: true, parts: [] } }));
  expect(await runMvpProductionSample(realWorkloadCases[0]!, "baseline", generate)).toMatchObject({ outcome: "invalid_output", calls: 1, useful: null });
  expect(generate).toHaveBeenCalledTimes(1);
});

test("pre-cancelled samples have zero model calls", async () => {
  const generate = vi.fn(async () => ({ output: { offer: false, parts: [] } }));
  expect(await runMvpProductionSample(realWorkloadCases[0]!, "baseline", generate, AbortSignal.abort())).toMatchObject({ outcome: "cancelled", calls: 0 });
  expect(generate).not.toHaveBeenCalled();
});

test("production baseline reads raw text without accessing unavailable structured output", async () => {
  const spy = vi.mocked(generateText).mockResolvedValue({
    text: " tomorrow", finishReason: "stop", usage: { inputTokens: 10, outputTokens: 2 },
    get output() { throw new Error("No structured output requested"); },
  } as never);
  try {
    const entry = structuredClone(realWorkloadCases[0]!);
    entry.request.payload.textBefore = "We can meet";
    entry.request.payload.fieldContext.shape = "single_line";
    entry.request.payload.artifacts = [];
    expect(await runMvpProductionSample(entry, "baseline")).toMatchObject({outcome:"text",output:" tomorrow",calls:1,inputTokens:10,outputTokens:2});
  } finally { spy.mockReset(); }
});

test("production baseline rejects an incomplete provider result just like production", async () => {
  const spy = vi.mocked(generateText).mockResolvedValue({
    output: {offer:true,parts:[{text:"Incomplete draft"}]}, finishReason:"length", text:"", usage:{inputTokens:10,outputTokens:2},
  } as never);
  try {
    expect(await runMvpProductionSample(realWorkloadCases[0]!, "baseline")).toMatchObject({outcome:"invalid_output",calls:1});
  } finally { spy.mockReset(); }
});
