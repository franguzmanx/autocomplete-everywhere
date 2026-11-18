import {
  generateText,
  NoObjectGeneratedError,
  NoOutputGeneratedError,
  Output,
  type LanguageModel,
} from "ai";
import { z } from "zod";

import { SuggestionGenerationError, type SuggestionCandidate, type SuggestionGenerationInput, type SuggestionGenerator } from "../app.js";
import {
  buildContinuationInstructions,
  buildContinuationPrompt,
  buildOutputContract,
} from "../prompts/continuation.js";

const continuationPart = z.union([
  z.object({ text: z.string().min(1).max(2_000) }).strict(),
  z.object({ artifact: z.string().min(1).max(64) }).strict(),
]);

export const continuationCompositionSchema = z
  .object({
    offer: z.boolean(),
    parts: z.array(continuationPart).max(16),
  })
  .strict();

const continuationCompositionWireSchema = z
  .object({
    offer: z.boolean(),
    parts: z.array(
      z.union([
        z.object({ text: z.string() }).strict(),
        z.object({ artifact: z.string() }).strict(),
      ]),
    ),
  })
  .strict();

type ContinuationGenerationResult = {
  output?: unknown;
  text?: string | PromiseLike<string>;
};

type GenerateContinuation = (
  options: Record<string, unknown>,
) => ContinuationGenerationResult | PromiseLike<ContinuationGenerationResult>;

const GENERATION_DEADLINE_MS = {
  line: 2_500,
  block: 8_000,
} as const;

class ContinuationCompositionError extends Error {
  override name = "ContinuationCompositionError";

  constructor(readonly code: string) {
    super(code);
  }
}

export type AiDiagnosticsEntry = {
  event:
    | "ai_generation_started"
    | "ai_model_call_finished"
    | "ai_generation_finished"
    | "ai_generation_error"
    | "ai_generation_outcome";
  requestId: string;
  payload: unknown;
};

type AiDiagnosticsLogger = (entry: AiDiagnosticsEntry) => void;

const GEMINI_MODEL_ID = "google/gemini-3.5-flash-lite";

export async function generateContinuation(options: Record<string, unknown>) {
  const result = await generateText(options as never);
  if (result.finishReason !== "stop") throw new ContinuationCompositionError("generation_incomplete");
  return options.output
    ? { output: result.output, usage: result.usage }
    : { text: result.text, usage: result.usage };
}

const logDiagnostics: AiDiagnosticsLogger = (entry) => {
  try {
    console.info(JSON.stringify(entry));
  } catch {
    console.info('{"event":"ai_diagnostics_serialization_failed"}');
  }
};

function safeErrorKind(error: unknown): string {
  if (typeof error !== "object" || error === null || !("name" in error)) return "unknown";
  // Provider-controlled names may contain response contents; emit only known
  // categories, never arbitrary names, messages, causes or stacks.
  switch (error.name) {
    case "TimeoutError": return "timeout";
    case "AbortError": return "aborterror";
    case "AI_APICallError": return "ai_apicallerror";
    case "AI_NoObjectGeneratedError": return "ai_noobjectgeneratederror";
    case "AI_NoOutputGeneratedError": return "ai_nooutputgeneratederror";
    case "Error": return "error";
    default: return "unknown";
  }
}

function numericDiagnostics(value: unknown): unknown {
  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    value === null
  ) {
    return value;
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }
  const output: Record<string, unknown> = {};
  for (const [key, entry] of Object.entries(value)) {
    const safe = numericDiagnostics(entry);
    if (safe !== undefined) output[key] = safe;
  }
  return output;
}

function contentFreeLifecyclePayload(
  event: "start" | "model_call_finished" | "finished",
  payload: unknown,
): Record<string, unknown> {
  if (event === "start" || typeof payload !== "object" || payload === null) {
    return {};
  }
  const source = payload as Record<string, unknown>;
  const output: Record<string, unknown> = {};
  if (
    typeof source.finishReason === "string" &&
    /^[A-Za-z0-9_-]{1,80}$/.test(source.finishReason)
  ) {
    output.finishReason = source.finishReason;
  }
  for (const key of ["usage", "performance"] as const) {
    const safe = numericDiagnostics(source[key]);
    if (safe !== undefined) output[key] = safe;
  }
  return output;
}

function normalizedForArtifactMatch(value: string): string {
  return value.normalize("NFC").replace(/\s+/gu, " ").trim();
}

export function composeContinuation(
  output: z.infer<typeof continuationCompositionSchema>,
  authoredArtifacts: SuggestionGenerationInput["request"]["payload"]["artifacts"],
  maxCharacters: number,
): SuggestionCandidate | undefined {
  if (!output.offer) {
    return undefined;
  }
  if (output.parts.length === 0) {
    throw new ContinuationCompositionError("offer_true_without_parts");
  }

  const artifactById = new Map(
    authoredArtifacts.map((artifact) => [artifact.id, artifact.text]),
  );
  const artifactTexts = [...artifactById.values()];
  let usesArtifact = false;
  let generatedLength = 0;
  const composed = output.parts
    .map((part) => {
      if ("artifact" in part) {
        usesArtifact = true;
        const exact = artifactById.get(part.artifact);
        if (exact === undefined) {
          throw new ContinuationCompositionError("unknown_artifact_reference");
        }
        return exact;
      }
      const normalized = normalizedForArtifactMatch(part.text);
      const matches = artifactTexts.filter(
        (artifact) => normalizedForArtifactMatch(artifact) === normalized,
      );
      if (matches.length === 1) {
        usesArtifact = true;
        return matches[0]!;
      }
      generatedLength += part.text.length;
      if (generatedLength > 2_000) throw new ContinuationCompositionError("generated_text_outside_budget");
      return part.text;
    })
    .join("");

  if (!composed) {
    throw new ContinuationCompositionError("empty_composition");
  }
  if (composed.length <= maxCharacters) return usesArtifact ? {text: composed, preservesExactArtifacts: true} : composed;
  throw new ContinuationCompositionError(
    usesArtifact ? "artifact_outside_budget" : "generated_text_outside_budget",
  );
}

export function normalizePlainTextLine(
  textBefore: string,
  generated: string,
): string {
  const startsWithWhitespace = /^\s/u.test(generated);
  const flattened = generated
    .replace(/[^\S\r\n]*[\r\n]+[^\S\r\n]*/gu, " ")
    .trimEnd();
  const withoutLeadingWhitespace = flattened.trimStart();
  if (!withoutLeadingWhitespace) return "";
  if (!textBefore) return withoutLeadingWhitespace;
  return startsWithWhitespace ? ` ${withoutLeadingWhitespace}` : flattened;
}

type GeminiSuggestionGeneratorOptions = {
  diagnostics?: "off" | "full";
  generate?: GenerateContinuation;
  diagnosticsLogger?: AiDiagnosticsLogger;
};

export class GeminiSuggestionGenerator implements SuggestionGenerator {
  private readonly diagnostics: "off" | "full";
  private readonly generate: GenerateContinuation;
  private readonly diagnosticsLogger: AiDiagnosticsLogger;

  constructor(
    private readonly modelProvider: (modelId: string) => LanguageModel,
    options: GeminiSuggestionGeneratorOptions = {},
  ) {
    this.diagnostics = options.diagnostics ?? "off";
    this.generate = options.generate ?? generateContinuation;
    this.diagnosticsLogger = options.diagnosticsLogger ?? logDiagnostics;
  }

  async complete(
    input: SuggestionGenerationInput,
  ): Promise<SuggestionCandidate | undefined> {
    const isLine = input.outputBudget.scope === "line";
    const usesPlainText =
      isLine &&
      input.request.payload.artifacts.length === 0;
    let reportedError: unknown;
    let completionEvidence: Record<string, unknown> | undefined;
    const diagnosticsCallbacks =
      this.diagnostics === "full"
        ? {
            onStart: (payload: unknown) =>
              this.diagnosticsLogger({
                event: "ai_generation_started",
                requestId: input.request.identity.requestId,
                payload: contentFreeLifecyclePayload("start", payload),
              }),
            onLanguageModelCallEnd: (payload: unknown) =>
              this.diagnosticsLogger({
                event: "ai_model_call_finished",
                requestId: input.request.identity.requestId,
                payload: contentFreeLifecyclePayload(
                  "model_call_finished",
                  payload,
                ),
              }),
            onEnd: (payload: unknown) =>
              this.diagnosticsLogger({
                event: "ai_generation_finished",
                requestId: input.request.identity.requestId,
                payload: contentFreeLifecyclePayload("finished", payload),
              }),
          }
        : {};
    const commonOptions = {
      model: this.modelProvider(GEMINI_MODEL_ID),
      instructions: [
        buildContinuationInstructions(buildOutputContract(input.outputBudget), Boolean(input.request.payload.writingPreferences?.length)),
        ...(usesPlainText
          ? [
              "Return only the raw text to insert. Do not return JSON, labels, analysis, explanations, or quotation marks. If no useful insertion exists, return an empty response.",
            ]
          : []),
      ].join(" "),
      prompt: buildContinuationPrompt(
        input.request,
        input.outputBudget,
      ),
      temperature: 0.2,
      maxOutputTokens: input.outputBudget.scope === "block" ? 4096 : 256,
      maxRetries: 0,
      abortSignal: input.signal,
      timeout: GENERATION_DEADLINE_MS[input.outputBudget.scope],
      ...diagnosticsCallbacks,
      onLanguageModelCallEnd: (payload: unknown) => {
        completionEvidence = contentFreeLifecyclePayload("model_call_finished", payload);
        diagnosticsCallbacks.onLanguageModelCallEnd?.(payload);
      },
      onError: ({ error }: { error: unknown }) => {
        reportedError = error;
      },
      providerOptions: {
        google: {
          thinkingConfig: { thinkingLevel: "low", includeThoughts: false },
        },
        gateway: { only: ["vertex"], zeroDataRetention: true },
      },
    };
    let continuation: SuggestionCandidate | undefined;
    try {
      input.signal.throwIfAborted();
      if (usesPlainText) {
        const result = await this.generate(commonOptions);
        const text = await result.text;
        if (typeof text !== "string") {
          throw new ContinuationCompositionError("plain_text_missing_or_invalid");
        }
        // Validate raw controls before trim/whitespace folding can erase them.
        // Tab, LF and CR remain valid writing whitespace.
        if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/u.test(text)) {
          throw new ContinuationCompositionError("plain_text_unsafe_controls");
        }
        const normalized = normalizePlainTextLine(input.request.payload.textBefore, text);
        if (normalized.length > input.outputBudget.maxCharacters) {
          throw new ContinuationCompositionError("generated_text_outside_budget");
        }
        if (normalized.length > 0) continuation = normalized;
      } else {
        const result = await this.generate({
          ...commonOptions,
          output: Output.object({
            name: "insert_continuation",
            description:
              "Whether to offer text and the ordered composition to insert at the cursor. Reference an artifact id to preserve authored source exactly; use a text part only to generate or transform content.",
            schema: continuationCompositionWireSchema,
          }),
        });
        const parsed = continuationCompositionSchema.safeParse(await result.output);
        if (!parsed.success) {
          throw new ContinuationCompositionError("required_object_missing_or_invalid");
        }
        continuation = composeContinuation(
          parsed.data,
          input.request.payload.artifacts,
          input.outputBudget.maxCharacters,
        );
      }
      input.signal.throwIfAborted();
      if (reportedError !== undefined) throw reportedError;
    } catch (error) {
      const reason = safeErrorKind(error);
      const failure = input.signal.aborted
        ? new SuggestionGenerationError("cancelled", "request_aborted")
        : error instanceof ContinuationCompositionError
          ? new SuggestionGenerationError("invalid_output", error.code)
          : NoObjectGeneratedError.isInstance(error) || NoOutputGeneratedError.isInstance(error)
            ? new SuggestionGenerationError("invalid_output", reason)
            : new SuggestionGenerationError(
                reason === "timeout" ? "timeout" : reason === "aborterror" ? "cancelled" : "provider_error",
                reason,
              );
      // Failed requests must remain diagnosable without enabling lifecycle logs.
      // Cancellations are ordinary typing behavior, not production errors.
      if (failure.kind !== "cancelled" || this.diagnostics === "full") {
        const status = typeof error === "object" && error !== null && "statusCode" in error
          ? error.statusCode : undefined;
        const providerStatus = reason === "ai_apicallerror" && typeof status === "number"
          && Number.isInteger(status) && status >= 400 && status <= 599 ? status : undefined;
        try {
          this.diagnosticsLogger({
            event: "ai_generation_error",
            requestId: input.request.identity.requestId,
            payload: { kind: failure.kind, reason: failure.reason,
              ...(completionEvidence ? { completion: completionEvidence } : {}),
              ...(providerStatus !== undefined ? { providerStatus } : {}) },
          });
        } catch {
          // A diagnostic sink must never replace the original failure.
        }
      }
      throw failure;
    }
    if (this.diagnostics === "full") {
      this.diagnosticsLogger({
        event: "ai_generation_outcome",
        requestId: input.request.identity.requestId,
        payload: { result: continuation === undefined ? "silence" : "text" },
      });
    }
    return continuation;
  }
}
