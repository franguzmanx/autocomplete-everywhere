import { expect, it } from "vitest";
import { BackgroundOperations } from "../src/main/background-operations";
it("shares two slots, removes cancelled work, and releases failures", async () => {
  const queue = new BackgroundOperations();
  const signal = new AbortController().signal;
  let release!: () => void;
  let count = 0;
  const first = queue.run(
    signal,
    () =>
      new Promise<void>((resolve) => {
        release = resolve;
        count++;
      }),
  );
  const second = queue.run(signal, async () => {
    count++;
    throw new Error("expected");
  });
  const cancelled = new AbortController();
  const third = queue.run(cancelled.signal, async () => {
    count += 100;
  });
  cancelled.abort();
  await expect(third).rejects.toThrow("cancelled");
  await expect(second).rejects.toThrow("expected");
  const fourth = queue.run(signal, async () => {
    count++;
  });
  await fourth;
  expect(count).toBe(3);
  release();
  await first;
});
