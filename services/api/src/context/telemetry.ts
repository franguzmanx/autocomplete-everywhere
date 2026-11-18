/** Provider-reported billing only. Unknown usage/cost stays absent, never zero-filled. */
export type BackgroundMetric = {
  operation: "visual" | "embedding" | "learning";
  result: "success" | "error" | "cancelled";
  durationMs: number;
  tokens?: number;
  costUsd?: number;
};
export type BackgroundMetricSink = (event: BackgroundMetric) => void;
export function reportedCost(providerMetadata: unknown): number | undefined {
  if (!providerMetadata || typeof providerMetadata !== "object")
    return undefined;
  const gateway = (providerMetadata as { gateway?: unknown }).gateway;
  if (!gateway || typeof gateway !== "object") return undefined;
  const cost = (gateway as { cost?: unknown }).cost;
  if (typeof cost !== "number" && typeof cost !== "string") return undefined;
  if (typeof cost === "string" && !/^\d+(?:\.\d+)?$/.test(cost))
    return undefined;
  const value = Number(cost);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
}
export function reportBackground(
  sink: BackgroundMetricSink,
  event: BackgroundMetric,
): void {
  // Explicit construction excludes provider messages, metadata, prompts and source text.
  const safe: BackgroundMetric = {
    operation: event.operation,
    result: event.result,
    durationMs: Math.max(0, Math.round(event.durationMs)),
  };
  if (
    typeof event.tokens === "number" &&
    Number.isFinite(event.tokens) &&
    event.tokens >= 0
  )
    safe.tokens = event.tokens;
  if (
    typeof event.costUsd === "number" &&
    Number.isFinite(event.costUsd) &&
    event.costUsd >= 0
  )
    safe.costUsd = event.costUsd;
  try {
    sink(safe);
  } catch {
    /* Telemetry must never fail requests. */
  }
}
