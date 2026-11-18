export type ApiTraceTimestamp = {
  wallMs: number;
  monoMs: number;
};

export type ApiTraceEntry = {
  v: 1;
  requestId: string;
  proc: "api";
  event:
    | "received"
    | "auth_done"
    | "model_valid_object"
    | "model_done"
    | "response_end";
  wallMs: number;
  monoMs: number;
  attrs:
    | { region: string; cold: boolean; instanceAgeMs: number }
    | { ms: number; source?: "origin" | "cache" | "inflight" }
    | { validObjectMs: number }
    | { totalMs: number }
    | {
        ms: number;
        result: "text" | "silence" | "error" | "cancelled";
        clientAborted?: true;
        kind?: "invalid_output" | "timeout" | "cancelled" | "provider_error";
        reason?: string;
      };
};

export type ApiTraceRuntime = {
  region: string;
  instanceStartedWallMs: number;
  now(): ApiTraceTimestamp;
  claimCold(): boolean;
  write(entry: ApiTraceEntry): void;
};

type ApiTraceRuntimeOptions = {
  diagnostics: "off" | "full";
  environment?: Readonly<Record<string, string | undefined>>;
  wallNow?: () => number;
  monotonicNow?: () => number;
  writeLine?: (line: string) => void;
};

function safeRegion(value: string | undefined): string {
  return value && /^[a-z0-9-]{1,32}$/i.test(value) ? value : "unknown";
}

export function createApiTraceRuntime(
  options: ApiTraceRuntimeOptions,
): ApiTraceRuntime | undefined {
  if (options.diagnostics === "off") return undefined;

  const wallNow = options.wallNow ?? Date.now;
  const monotonicNow = options.monotonicNow ?? (() => performance.now());
  const writeLine = options.writeLine ?? ((line) => console.info(line));
  const instanceStartedWallMs = wallNow();
  let cold = true;

  return {
    region: safeRegion(options.environment?.VERCEL_REGION),
    instanceStartedWallMs,
    now: () => ({ wallMs: wallNow(), monoMs: monotonicNow() }),
    claimCold: () => {
      const claimed = cold;
      cold = false;
      return claimed;
    },
    write: (entry) => {
      try {
        writeLine(JSON.stringify(entry));
      } catch {
        writeLine(
          '{"v":1,"proc":"api","event":"trace_serialization_failed"}',
        );
      }
    },
  };
}
