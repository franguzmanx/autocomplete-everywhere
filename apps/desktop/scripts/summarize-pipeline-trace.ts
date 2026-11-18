import { readFile } from "node:fs/promises";

import {
  summarizePipelineTrace,
  type PipelineTraceEvent,
} from "../src/main/pipeline-trace-summary";

const [path, start, end] = process.argv.slice(2);
if (!path) {
  throw new Error(
    "usage: bun trace:summary <pipeline-trace.ndjson> [startWallMs] [endWallMs]",
  );
}

const events = (await readFile(path, "utf8"))
  .split("\n")
  .filter(Boolean)
  .map((line) => JSON.parse(line) as PipelineTraceEvent);

const startWallMs = start === undefined ? undefined : Number(start);
const endWallMs = end === undefined ? undefined : Number(end);
if (
  (startWallMs !== undefined && !Number.isFinite(startWallMs)) ||
  (endWallMs !== undefined && !Number.isFinite(endWallMs))
) {
  throw new Error("trace window must use numeric wall-clock milliseconds");
}

console.log(
  JSON.stringify(
    summarizePipelineTrace(events, {
      ...(startWallMs === undefined ? {} : { startWallMs }),
      ...(endWallMs === undefined ? {} : { endWallMs }),
    }),
    null,
    2,
  ),
);
