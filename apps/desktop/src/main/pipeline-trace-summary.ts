export type PipelineTraceEvent = {
  requestId?: string;
  proc: string;
  event: string;
  monoMs: number;
  wallMs: number;
  attrs: Readonly<Record<string, unknown>>;
};

export type PipelineTraceSummary = {
  requests: number;
  presented: number;
  visibleRate: number;
  requestToVisibleMs: { p50: number | null; p95: number | null };
  httpTtfbMs: { p50: number | null; p95: number | null };
  helperWrites: Record<string, number>;
  aborts: Record<string, number>;
  presentationRejections: Record<string, number>;
};

export function summarizePipelineTrace(
  events: readonly PipelineTraceEvent[],
  window: { startWallMs?: number; endWallMs?: number } = {},
): PipelineTraceSummary {
  const filtered = events.filter(
    (event) =>
      (window.startWallMs === undefined || event.wallMs >= window.startWallMs) &&
      (window.endWallMs === undefined || event.wallMs <= window.endWallMs),
  );
  const requests = firstByRequestId(
    filtered.filter((event) => event.event === "request_written"),
  );
  // All metrics describe requests that started inside this window. A rotated
  // trace or a boundary-crossing response must not inflate their success rate.
  const cohort = filtered.filter(
    (event) => event.requestId !== undefined && requests.has(event.requestId),
  );
  const presentations = firstByRequestId(
    cohort.filter((event) => event.event === "presented"),
  );
  const requestToVisible = [...requests.entries()].flatMap(
    ([requestId, request]) => {
      const presented = presentations.get(requestId);
      return presented ? [Math.max(0, presented.monoMs - request.monoMs)] : [];
    },
  );
  const ttfb = cohort.flatMap((event) => {
    const value = event.event === "http_headers" ? event.attrs.ttfbMs : undefined;
    return typeof value === "number" ? [value] : [];
  });

  return {
    requests: requests.size,
    presented: presentations.size,
    visibleRate: requests.size === 0 ? 0 : presentations.size / requests.size,
    requestToVisibleMs: percentiles(requestToVisible),
    httpTtfbMs: percentiles(ttfb),
    helperWrites: countAttribute(cohort, "helper_write", "result"),
    aborts: countAttribute(cohort, "aborted", "reason"),
    presentationRejections: countAttribute(
      cohort,
      "present_rejected",
      "rejection",
    ),
  };
}

function firstByRequestId(
  events: readonly PipelineTraceEvent[],
): Map<string, PipelineTraceEvent> {
  const result = new Map<string, PipelineTraceEvent>();
  for (const event of events) {
    if (!event.requestId) continue;
    const current = result.get(event.requestId);
    if (!current || event.monoMs < current.monoMs) {
      result.set(event.requestId, event);
    }
  }
  return result;
}

function percentiles(values: readonly number[]): {
  p50: number | null;
  p95: number | null;
} {
  if (values.length === 0) return { p50: null, p95: null };
  const sorted = [...values].sort((a, b) => a - b);
  return {
    p50: nearestRank(sorted, 0.5),
    p95: nearestRank(sorted, 0.95),
  };
}

function nearestRank(sorted: readonly number[], percentile: number): number {
  return sorted[Math.ceil(sorted.length * percentile) - 1]!;
}

function countAttribute(
  events: readonly PipelineTraceEvent[],
  eventName: string,
  attribute: string,
): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const event of events) {
    if (event.event !== eventName) continue;
    const value = event.attrs[attribute];
    if (typeof value !== "string") continue;
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts;
}
