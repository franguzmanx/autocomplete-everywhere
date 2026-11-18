import { expect, it, vi } from "vitest";
import { prepareContext } from "../src/main/context-preparation";
it("continues without history after 100ms even when a service ignores cancellation", async () => {
  vi.useFakeTimers();
  try {
    let operationSignal: AbortSignal | undefined;
    const result = prepareContext(signal => { operationSignal = signal; return new Promise(() => {}); }, new AbortController().signal);
    await vi.advanceTimersByTimeAsync(100);
    expect(await result).toBeUndefined();
    expect(operationSignal?.aborted).toBe(true);
  } finally { vi.useRealTimers(); }
});
it("uses prepared context immediately", async () => {
  const context = { revision: "1" };
  expect(await prepareContext(async () => context, new AbortController().signal)).toBe(context);
});
it("parent cancellation never permits a new generation", async () => {
  const parent = new AbortController();
  parent.abort();
  const work = vi.fn(async () => ({}));
  await expect(prepareContext(work, parent.signal)).rejects.toThrow();
  expect(work).not.toHaveBeenCalled();
});
