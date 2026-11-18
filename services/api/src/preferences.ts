import type { ContextLeasePool } from './context/leases.js';
import type { Hono } from "hono";
import {
  preferenceExtractionRequestSchema,
  preferenceExtractionResponseSchema,
  type PreferenceExtractionRequest,
  type PreferenceExtractionResponse,
} from "../../../packages/protocol/src/learning.js";
import type { AuthenticateRequest } from "./app.js";

export type PreferenceExtractionInput = {
  request: PreferenceExtractionRequest;
  userId: string;
  signal: AbortSignal;
};
export interface PreferenceExtractor {
  extract(input: PreferenceExtractionInput): Promise<PreferenceExtractionResponse>;
}
export class PreferenceExtractionError extends Error {
  override name = "PreferenceExtractionError";
  constructor(readonly kind: "invalid_output" | "timeout" | "cancelled" | "provider_error") {
    super(`preference_extraction_failed:${kind}`);
  }
}
export function validatePreferenceEvidence(request: PreferenceExtractionRequest, output: unknown): PreferenceExtractionResponse {
  const result = preferenceExtractionResponseSchema.safeParse(output);
  const observationIds = new Set(request.observations.map(observation => observation.id));
  if (!result.success || result.data.evidence.some(evidence => !observationIds.has(evidence.observationId))) {
    throw new PreferenceExtractionError("invalid_output");
  }
  return result.data;
}

// Six pairs of 2000 UTF-16 units fit even if every JSON character is escaped.
const MAX_EXTRACTION_BODY_BYTES = 160_000;
class BodyTooLargeError extends Error {}
async function readBoundedBody(request: Request): Promise<unknown> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (declaredLength > MAX_EXTRACTION_BODY_BYTES) throw new BodyTooLargeError();
  const reader = request.body?.getReader();
  if (!reader) throw new SyntaxError();
  const chunks: Uint8Array[] = [];
  let size = 0;
  const cancelRead = () => { void reader.cancel().catch(() => {}); };
  request.signal.addEventListener("abort", cancelRead, {once:true});
  if (request.signal.aborted) cancelRead();
  try {
    while (true) {
      request.signal.throwIfAborted();
      const {value, done} = await reader.read();
      request.signal.throwIfAborted();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_EXTRACTION_BODY_BYTES) {
        await reader.cancel();
        throw new BodyTooLargeError();
      }
      chunks.push(value);
    }
  } finally {
    request.signal.removeEventListener("abort", cancelRead);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes));
}

export function registerPreferenceExtractionRoute(app: Hono, dependencies: {
  authenticate: AuthenticateRequest;
  preferenceExtractor?: PreferenceExtractor;
  backgroundLeases?:ContextLeasePool;
}): void {
  app.post("/v1/preferences/extract", async context => {
    context.header("cache-control", "no-store");
    let authenticated;
    try { authenticated = await dependencies.authenticate(context.req.raw); }
    catch { return context.json({error: "auth_unavailable"}, 503); }
    if (!authenticated) return context.json({error: "unauthorized"}, 401);
    let body: unknown;
    try { body = await readBoundedBody(context.req.raw); }
    catch (error) {
      if (context.req.raw.signal.aborted) return Response.json({error:"extraction_cancelled"}, {status:499});
      return context.json({error: error instanceof BodyTooLargeError ? "request_too_large" : "invalid_request"}, error instanceof BodyTooLargeError ? 413 : 400);
    }
    const parsed = preferenceExtractionRequestSchema.safeParse(body);
    if (!parsed.success) return context.json({error:"invalid_request"}, 400);
    if (!dependencies.preferenceExtractor) return context.json({error:"extraction_unavailable"}, 503);
    if(!dependencies.backgroundLeases)return context.json({error:'extraction_unavailable'},503);
    let release;try{release=await dependencies.backgroundLeases.acquire(authenticated.userId);}catch{return context.json({error:'extraction_unavailable'},503);}
    if(!release){context.header('retry-after','1');return context.json({error:'background_busy'},429);}
    const signal=AbortSignal.any([context.req.raw.signal,AbortSignal.timeout(10000)]);
    try {
      signal.throwIfAborted();
      const result = await dependencies.preferenceExtractor.extract({request:parsed.data, userId:authenticated.userId, signal});
      signal.throwIfAborted();
      return context.json(validatePreferenceEvidence(parsed.data, result));
    } catch (error) {
      if (signal.aborted || (error instanceof PreferenceExtractionError && error.kind === "cancelled")) {
        return Response.json({error:"extraction_cancelled"}, {status:499});
      }
      return context.json({error:"extraction_failed"}, 502);
    }finally{try{await release();}catch{/* Lease expiry bounds interrupted instances. */}}
  });
}
