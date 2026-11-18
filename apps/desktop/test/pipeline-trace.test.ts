import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, describe, expect, test } from "vitest";

import { PipelineTraceWriter } from "../src/main/pipeline-trace";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) => rm(path, { force: true, recursive: true })),
  );
});

async function temporaryTracePath(): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-trace-"));
  temporaryDirectories.push(directory);
  return join(directory, "pipeline-trace.ndjson");
}

describe("PipelineTraceWriter", () => {
  test("appends content-free desktop events as one NDJSON record per line", async () => {
    const path = await temporaryTracePath();
    let wallMs = 1_788_540_000_000;
    let monoMs = 12_000;
    const trace = new PipelineTraceWriter(path, {
      wallNow: () => wallMs++,
      monotonicNow: () => monoMs++,
    });

    trace.record({
      requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
      event: "request_received",
      attrs: { focusSequence: 7, explicit: false, artifactCount: 2, recentWritingCount: 1 },
    });
    trace.record({
      requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
      event: "token_ready",
      attrs: { source: "store", ms: 8 },
    });
    await trace.flush();

    const records = (await readFile(path, "utf8"))
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    expect(records).toEqual([
      {
        v: 1,
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        proc: "desktop",
        event: "request_received",
        monoMs: 12_000,
        wallMs: 1_788_540_000_000,
        attrs: { focusSequence: 7, explicit: false, artifactCount: 2, recentWritingCount: 1 },
      },
      {
        v: 1,
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        proc: "desktop",
        event: "token_ready",
        monoMs: 12_001,
        wallMs: 1_788_540_000_001,
        attrs: { source: "store", ms: 8 },
      },
    ]);
    expect(JSON.stringify(records)).not.toContain("draft");
    expect(JSON.stringify(records)).not.toContain("suggestion");
    expect(JSON.stringify(records)).not.toContain("clipboard");
  });

  test("rotates the NDJSON before it exceeds the configured bound", async () => {
    const path = await temporaryTracePath();
    const trace = new PipelineTraceWriter(path, {
      maxBytes: 300,
      wallNow: () => 1_788_540_000_000,
      monotonicNow: () => 12_000,
    });

    for (let focusSequence = 1; focusSequence <= 4; focusSequence += 1) {
      trace.record({
        requestId: `00000000-0000-4000-8000-00000000000${focusSequence}`,
        event: "request_received",
        attrs: { focusSequence, explicit: false, artifactCount: 0, recentWritingCount: 0 },
      });
    }
    await trace.flush();

    const current = await readFile(path, "utf8");
    const previous = await readFile(`${path}.1`, "utf8");
    expect(Buffer.byteLength(current)).toBeLessThanOrEqual(300);
    expect(Buffer.byteLength(previous)).toBeLessThanOrEqual(300);
    for (const line of `${previous}${current}`.trim().split("\n")) {
      expect(() => JSON.parse(line)).not.toThrow();
    }
  });

  test("preserves validated helper timestamps and pre-request focus correlation", async () => {
    const path = await temporaryTracePath();
    const trace = new PipelineTraceWriter(path);

    trace.recordHelper({
      v: 1,
      focusSequence: 14,
      proc: "helper",
      event: "input_observed",
      monoMs: 2_500.25,
      wallMs: 1_788_540_000_123,
      attrs: { captureSeq: 9, captureMs: 12.5 },
    });
    trace.recordHelper({
      v: 1,
      requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
      focusSequence: 14,
      proc: "helper",
      event: "request_written",
      monoMs: 2_812.5,
      wallMs: 1_788_540_000_435,
      attrs: {
        surface: "native",
        shape: "multiline",
        textBeforeBucket: "lt_100",
        textAfterBucket: "zero",
        hasSelection: false,
        related: 2,
        geometry: "exact",
        anchorResolved: true,
      },
    });
    await trace.flush();

    const records = (await readFile(path, "utf8"))
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    expect(records).toEqual([
      {
        v: 1,
        focusSequence: 14,
        proc: "helper",
        event: "input_observed",
        monoMs: 2_500.25,
        wallMs: 1_788_540_000_123,
        attrs: { captureSeq: 9, captureMs: 12.5 },
      },
      {
        v: 1,
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
        focusSequence: 14,
        proc: "helper",
        event: "request_written",
        monoMs: 2_812.5,
        wallMs: 1_788_540_000_435,
        attrs: {
          surface: "native",
          shape: "multiline",
          textBeforeBucket: "lt_100",
          textAfterBucket: "zero",
          hasSelection: false,
          related: 2,
          geometry: "exact",
          anchorResolved: true,
        },
      },
    ]);
  });
});
