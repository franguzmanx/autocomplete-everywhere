import { spawn as spawnProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { StringDecoder } from "node:string_decoder";
import type { Readable, Writable } from "node:stream";

type Child = {
  stdin: Writable;
  stdout: Readable;
  stderr: Readable;
  on(event: string, listener: (...args: any[]) => void): unknown;
  kill(): boolean;
};
type Pending = {
  resolve(value: unknown): void;
  reject(error: Error): void;
  cleanup(): void;
};
/** Private pipe only. Content and service stderr never enter diagnostics. */
export class ContextServiceClient {
  private child: Child | null = null;
  private pending = new Map<string, Pending>();
  private disposed = false;
  private account: string | null = null;
  private accountEpoch = 0;
  private openedGeneration = 0;
  private queued = 0;
  private serial: Promise<unknown> = Promise.resolve();
  generation = 0;
  constructor(
    private options: {
      executable: string;
      root: string;
      spawn?: () => Child;
      onExit?(): void;
    },
  ) {}
  private start(): Child {
    if (this.disposed) throw new Error("Context service stopped");
    if (this.child) return this.child;
    const child =
      this.options.spawn?.() ??
      spawnProcess(this.options.executable, ["--root", this.options.root], {
        stdio: ["pipe", "pipe", "pipe"],
      });
    this.child = child;
    this.generation++;
    let buffer = "";
    const decoder = new StringDecoder("utf8");
    child.stderr.resume();
    const failed = () => {
      if (this.child !== child) return;
      this.child = null;
      for (const p of this.pending.values()) {
        p.cleanup();
        p.reject(new Error("Context service unavailable"));
      }
      this.pending.clear();
      this.options.onExit?.();
    };
    child.on("error", failed);
    child.on("exit", failed);
    child.stdin.on("error", failed);
    child.stdout.on("data", (bytes: Buffer) => {
      if (this.child !== child) return;
      buffer += decoder.write(bytes);
      if (Buffer.byteLength(buffer) > 4_000_000) {
        child.kill();
        failed();
        return;
      }
      let boundary: number;
      while ((boundary = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 1);
        try {
          const message = JSON.parse(line);
          const p = this.pending.get(message.id);
          if (!p) continue;
          this.pending.delete(message.id);
          p.cleanup();
          if (message.ok === true) p.resolve(message.result);
          else p.reject(new Error("Context service unavailable"));
        } catch {
          child.kill();
          failed();
          return;
        }
      }
    });
    return child;
  }
  call<T = unknown>(
    op: string,
    payload: Record<string, unknown> = {},
    signal?: AbortSignal,
  ): Promise<T> {
    if (this.disposed || signal?.aborted)
      return Promise.reject(new Error("Context operation cancelled"));
    if (this.queued >= 32)
      return Promise.reject(new Error("Context service busy"));
    if (op === "open") {
      if (typeof payload.accountId !== "string" || !payload.accountId)
        return Promise.reject(new Error("Invalid context account"));
      this.account = payload.accountId;
      this.accountEpoch++;
    } else if (op === "close") {
      this.account = null;
      this.accountEpoch++;
    }
    const epoch = this.accountEpoch,
      account = this.account;
    this.queued++;
    const operation = this.serial
      .catch(() => {})
      .then(async () => {
        signal?.throwIfAborted();
        if (epoch !== this.accountEpoch || this.disposed)
          throw new Error("Context account changed");
        if (op === "close") {
          const result = await this.rawCall<T>(op, payload, signal);
          this.openedGeneration = 0;
          return result;
        }
        if (!account) throw new Error("Context account unavailable");
        this.start();
        if (op === "open") {
          const result = await this.rawCall<T>(op, payload, signal);
          this.openedGeneration = this.generation;
          return result;
        }
        if (this.openedGeneration !== this.generation) {
          await this.rawCall("open", { accountId: account }, signal);
          this.openedGeneration = this.generation;
        }
        signal?.throwIfAborted();
        if (epoch !== this.accountEpoch)
          throw new Error("Context account changed");
        return this.rawCall<T>(op, payload, signal);
      })
      .finally(() => {
        this.queued--;
      });
    this.serial = operation;
    return operation;
  }
  private rawCall<T = unknown>(
    op: string,
    payload: Record<string, unknown> = {},
    signal?: AbortSignal,
  ): Promise<T> {
    if (signal?.aborted)
      return Promise.reject(new Error("Context operation cancelled"));
    if (this.pending.size >= 32)
      return Promise.reject(new Error("Context service busy"));
    let child: Child;
    try {
      child = this.start();
    } catch {
      return Promise.reject(new Error("Context service unavailable"));
    }
    const id = randomUUID();
    let encoded: string;
    try {
      encoded = JSON.stringify({ ...payload, id, op }) + "\n";
      if (Buffer.byteLength(encoded) > 4_000_000) throw new Error();
    } catch {
      return Promise.reject(new Error("Context request too large or invalid"));
    }
    return new Promise<T>((resolve, reject) => {
      const abort = () => {
        const p = this.pending.get(id);
        if (!p) return;
        this.pending.delete(id);
        p.cleanup();
        reject(new Error("Context operation cancelled"));
      };
      const timer = setTimeout(() => {
        abort();
        child.kill();
      }, 10_000);
      const cleanup = () => {
        clearTimeout(timer);
        signal?.removeEventListener("abort", abort);
      };
      this.pending.set(id, {
        resolve: (value) => resolve(value as T),
        reject,
        cleanup,
      });
      signal?.addEventListener("abort", abort, { once: true });
      if (child.stdin.writableLength > 4_000_000) {
        abort();
        return;
      }
      try {
        child.stdin.write(encoded);
      } catch {
        abort();
        child.kill();
      }
    });
  }
  stop(): void {
    this.disposed = true;
    this.account = null;
    this.accountEpoch++;
    this.child?.kill();
    for (const p of this.pending.values()) {
      p.cleanup();
      p.reject(new Error("Context service stopped"));
    }
    this.pending.clear();
    this.child = null;
  }
}
