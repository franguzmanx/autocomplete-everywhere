import type { GenerationFailureKind, GenerationFailureReason } from "@autocompletion/protocol";
import {
  appendFile,
  mkdir,
  rename,
  rm,
  stat,
} from "node:fs/promises";
import { dirname } from "node:path";
import { performance } from "node:perf_hooks";

export type DesktopTraceRecord =
  | { requestId?: never; event: "manual_request"; attrs: { stage: "invoked" | "sent" | "blocked" | "received" | "target_unavailable"; reason?: "disabled" | "helper_unavailable" } }
  | { requestId?: never; event: "render_diagnostic"; attrs: { code: string } }
  | { requestId?: never; event: "rewrite_diagnostic"; attrs: { code: string } }
  | {
      requestId: string;
      event: "context_prepared";
      attrs: { ms: number; sourceCount: number; historyCount: number };
    }
  | {
      requestId: string;
      event: "request_received";
      attrs: { focusSequence: number; explicit: boolean; artifactCount: number; recentWritingCount: number };
    }
  | {
      requestId: string;
      event: "token_ready";
      attrs: { source: "store" | "refresh"; ms: number };
    }
  | {
      requestId: string;
      event: "http_start";
      attrs: { attempt: "initial" | "refresh" };
    }
  | {
      requestId: string;
      event: "http_headers";
      attrs: {
        attempt: "initial" | "refresh";
        status: number;
        ttfbMs: number;
        failureKind?: GenerationFailureKind;
        failureReason?: GenerationFailureReason;
      };
    }
  | {
      requestId: string;
      event: "http_end";
      attrs: {
        attempt: "initial" | "refresh";
        status?: number;
        totalMs: number;
        result: "complete" | "unauthorized" | "error";
      };
    }
  | {
      requestId: string;
      event: "aborted";
      attrs: {
        reason: "cancel" | "supersede" | "timeout" | "shutdown";
        stage: "token" | "http" | "body";
      };
    }
  | {
      requestId: string;
      event: "helper_write";
      attrs: { result: "text" | "silence" | "failed" };
    };

export type PipelineTraceRecorder = {
  record(record: DesktopTraceRecord): void;
};

export type HelperTimelineRecord = {
  v: 1;
  requestId?: string;
  focusSequence?: number;
  proc: "helper";
  event:
    | "input_observed"
    | "content_stable"
    | "capture_skipped"
    | "request_written"
    | "final_received"
    | "presented"
    | "present_rejected"
    | "presentation_overflow"
    | "typography_measured"
    | "cancel_written"
    | "interaction";
  monoMs: number;
  wallMs: number;
  attrs: Readonly<Record<string, boolean | number | string>>;
};

type PipelineTraceWriterOptions = {
  maxBytes?: number;
  wallNow?: () => number;
  monotonicNow?: () => number;
};

const DEFAULT_MAX_BYTES = 2 * 1024 * 1024;

export class PipelineTraceWriter implements PipelineTraceRecorder {
  readonly #maxBytes: number;
  readonly #wallNow: () => number;
  readonly #monotonicNow: () => number;
  #pending: Promise<void> = Promise.resolve();
  #currentBytes: number | null = null;

  constructor(
    private readonly path: string,
    options: PipelineTraceWriterOptions = {},
  ) {
    this.#maxBytes = options.maxBytes ?? DEFAULT_MAX_BYTES;
    this.#wallNow = options.wallNow ?? Date.now;
    this.#monotonicNow = options.monotonicNow ?? (() => performance.now());
  }

  record(record: DesktopTraceRecord): void {
    this.#enqueue({
      v: 1,
      requestId: record.requestId,
      proc: "desktop",
      event: record.event,
      monoMs: this.#monotonicNow(),
      wallMs: this.#wallNow(),
      attrs: record.attrs,
    });
  }

  recordHelper(record: HelperTimelineRecord): void {
    this.#enqueue(record);
  }

  #enqueue(envelope: object): void {
    const line = `${JSON.stringify(envelope)}\n`;
    this.#pending = this.#pending
      .catch(() => undefined)
      .then(() => this.#append(line))
      .catch(() => undefined);
  }

  flush(): Promise<void> {
    return this.#pending;
  }

  async #append(line: string): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    if (this.#currentBytes === null) {
      this.#currentBytes = await stat(this.path)
        .then((value) => value.size)
        .catch(() => 0);
    }
    const lineBytes = Buffer.byteLength(line);
    if (
      this.#currentBytes > 0 &&
      this.#currentBytes + lineBytes > this.#maxBytes
    ) {
      await rm(`${this.path}.1`, { force: true });
      await rename(this.path, `${this.path}.1`);
      this.#currentBytes = 0;
    }
    await appendFile(this.path, line, { encoding: "utf8", mode: 0o600 });
    this.#currentBytes += lineBytes;
  }
}
