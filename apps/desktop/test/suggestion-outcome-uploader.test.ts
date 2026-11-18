import { describe, expect, test } from "vitest";

import type { SuggestionOutcomeEvent } from "../src/main/suggestion-activity";
import { SuggestionOutcomeUploader } from "../src/main/suggestion-outcome-uploader";

function event(index: number): SuggestionOutcomeEvent {
  return {
    requestId: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    appId: "com.apple.Notes",
    surface: "text_editor",
    outcome: "requested",
  };
}

type Scheduled = { callback: () => void; delayMs: number };

function harness(options: { batchSize?: number; maxQueue?: number; fail?: () => boolean } = {}) {
  const batches: SuggestionOutcomeEvent[][] = [];
  const scheduled: Scheduled[] = [];
  const diagnostics: string[] = [];
  const uploader = new SuggestionOutcomeUploader({
    send: async (events) => {
      if (options.fail?.()) throw new Error("upload rejected");
      batches.push(events);
    },
    schedule: (callback, delayMs) => {
      const entry = { callback, delayMs };
      scheduled.push(entry);
      return () => {
        const index = scheduled.indexOf(entry);
        if (index >= 0) scheduled.splice(index, 1);
      };
    },
    onDiagnostic: (code) => diagnostics.push(code),
    ...(options.batchSize ? { batchSize: options.batchSize } : {}),
    ...(options.maxQueue ? { maxQueue: options.maxQueue } : {}),
  });
  return { uploader, batches, scheduled, diagnostics };
}

async function settle(): Promise<void> {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

describe("SuggestionOutcomeUploader", () => {
  test("sends a batch when the timer fires", async () => {
    const { uploader, batches, scheduled } = harness();

    uploader.enqueue(event(1));
    uploader.enqueue(event(2));
    expect(batches).toEqual([]);
    expect(scheduled).toHaveLength(1);

    scheduled[0]?.callback();
    await settle();

    expect(batches).toEqual([[event(1), event(2)]]);
    expect(scheduled).toHaveLength(1);
  });

  test("sends immediately once the batch size is reached", async () => {
    const { uploader, batches } = harness({ batchSize: 2 });

    uploader.enqueue(event(1));
    uploader.enqueue(event(2));
    await settle();

    expect(batches).toEqual([[event(1), event(2)]]);
  });

  test("drops a rejected batch and reports only a content-free code", async () => {
    let failures = 1;
    const { uploader, batches, diagnostics } = harness({
      batchSize: 1,
      fail: () => failures-- > 0,
    });

    uploader.enqueue(event(1));
    await settle();
    uploader.enqueue(event(2));
    await settle();

    expect(batches).toEqual([[event(2)]]);
    expect(diagnostics).toEqual(["outcome_upload_failed"]);
  });

  test("bounds the queue by discarding the oldest events", async () => {
    const { uploader, batches } = harness({ maxQueue: 3 });

    for (let index = 1; index <= 5; index += 1) uploader.enqueue(event(index));
    await uploader.flush();

    expect(batches).toEqual([[event(3), event(4), event(5)]]);
  });

  test("flush sends everything pending and dispose stops the timer", async () => {
    const { uploader, batches, scheduled } = harness();

    uploader.enqueue(event(1));
    await uploader.flush();
    expect(batches).toEqual([[event(1)]]);

    uploader.enqueue(event(2));
    uploader.dispose();
    expect(scheduled).toEqual([]);
    await settle();
    expect(batches).toEqual([[event(1)]]);
  });
});

test("a stalled upload retains only the newest bounded pending queue", async () => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const batches: SuggestionOutcomeEvent[][] = [];
  const uploader = new SuggestionOutcomeUploader({ batchSize: 1, maxQueue: 2,
    send: async events => { batches.push(events); if (batches.length === 1) await gate; },
  });
  uploader.enqueue(event(1));
  await settle();
  for (let i = 2; i <= 100; i++) uploader.enqueue(event(i));
  release();
  await uploader.flush();
  expect(batches).toEqual([[event(1)], [event(99)], [event(100)]]);
  uploader.dispose();
});

test("dispose aborts the active batch and never starts queued batches", async () => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const batches: SuggestionOutcomeEvent[][] = [];
  let signal!: AbortSignal;
  const uploader = new SuggestionOutcomeUploader({ batchSize: 1,
    send: async (events, activeSignal) => { batches.push(events); signal = activeSignal; await gate; },
  });
  uploader.enqueue(event(1));
  await settle();
  uploader.enqueue(event(2));
  uploader.enqueue(event(3));
  uploader.dispose();
  release();
  await uploader.flush();
  expect(signal.aborted).toBe(true);
  expect(batches).toEqual([[event(1)]]);
});
