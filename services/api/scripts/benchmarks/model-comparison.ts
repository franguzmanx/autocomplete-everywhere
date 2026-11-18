import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";

import { gateway } from "@ai-sdk/gateway";
import { Output, streamText } from "ai";
import { z } from "zod";

import {
  buildContinuationPrompt,
  CONTINUATION_INSTRUCTIONS,
} from "../../src/prompts/continuation";
import type { SuggestionRequest } from "../../../../packages/protocol/src";

type CaseId =
  | "spanish"
  | "english"
  | "code_switch"
  | "empty_related"
  | "anti_meta"
  | "cjk"
  | "rtl";

type ModelArm = {
  id: string;
  provider: string;
  reasoning: "none" | "low";
  omitTemperature?: boolean;
  zeroDataRetention: boolean;
  adaptation: string | null;
};

type BenchmarkCase = {
  id: CaseId;
  request: SuggestionRequest;
};

type SafeError = {
  name: string;
  category: string;
  message: string;
};

type RunResult = {
  model: string;
  requestedProvider: string;
  reasoning: "none" | "low";
  zeroDataRetention: boolean;
  temperature: number | null;
  adaptation: string | null;
  phase: "preflight_strict" | "preflight_effective" | "warmup" | "measured";
  caseId: CaseId;
  repetition: number;
  ok: boolean;
  schemaValid: boolean;
  firstOutputMs: number | null;
  modelResponseMs: number | null;
  validObjectMs: number;
  inputTokens: number | null;
  outputTokens: number | null;
  resolvedModel: string | null;
  resolvedProvider: string | null;
  providerAttemptCount: number | null;
  warnings: string[];
  output: {
    hash: string | null;
    length: number;
    useful: boolean;
    metaLeak: boolean;
    repeatedPrefix: boolean;
    reasons: string[];
  };
  error: SafeError | null;
};

const continuationSchema = z.object({
  continuation: z
    .string()
    .min(1)
    .describe("Only the new text to insert at the cursor; never repeat existing text."),
});

const benchmarkKnowledgeText = "Prefers concise, direct writing in the language already being used. Acme builds inspection software for field teams.";

const arms: ModelArm[] = [
  {
    id: "alibaba/qwen3.8-flash",
    provider: "alibaba",
    reasoning: "none",
    zeroDataRetention: true,
    adaptation: null,
  },
  {
    id: "google/gemini-3.8-flash",
    provider: "vertex",
    reasoning: "low",
    zeroDataRetention: true,
    adaptation: null,
  },
  {
    id: "openai/gpt-5.6-luna-fast",
    provider: "openai",
    reasoning: "none",
    omitTemperature: true,
    zeroDataRetention: false,
    adaptation:
      "temperature and ZDR filter omitted for benchmark only; the live catalog marks temperature unsupported and OpenAI routing rejected ZDR",
  },
  {
    id: "zai/glm-5.3-fast",
    provider: "baseten",
    reasoning: "low",
    zeroDataRetention: true,
    adaptation: null,
  },
  {
    id: "meta/muse-spark-1.3",
    provider: "meta",
    reasoning: "none",
    zeroDataRetention: false,
    adaptation: "ZDR filter omitted for benchmark only because the live model catalog reports zdr=none",
  },
];

function request(
  textBefore: string,
  options: {
    shape?: "single_line" | "multiline";
    label?: string;
    relatedFields?: Array<{
      shape: "single_line" | "multiline";
      label?: string;
      text: string;
    }>;
  } = {},
): SuggestionRequest {
  return {
    protocolVersion: 5,
    type: "suggestion_request",
    identity: {
      requestId: "00000000-0000-4000-8000-000000000001",
      focusSequence: 1,
      contentSignature: "synthetic-benchmark-signature",
      timestampMs: 1_788_000_000_000,
    },
    payload: {
      appId: "com.autocompletion.synthetic-benchmark",
      surface: "text_editor",
      textBefore,
      textAfter: "",
      selectedText: "",
      explicit: false,
      knowledge: [{sourceId: "00000000-0000-4000-8000-000000000099", title: "Benchmark writing context", kind: "knowledge", text: benchmarkKnowledgeText, revision: 1, updatedAt: 1, expiresAt: null, scope: {appIds: ["com.autocompletion.synthetic-benchmark"], anchor: "inspection"}}],
      artifacts: [],
      fieldContext: { sources: [],
        shape: options.shape ?? "multiline",
        ...(options.label ? { label: options.label } : {}),
        relatedFields: options.relatedFields ?? [],
      },
    },
  };
}

const cases: BenchmarkCase[] = [
  { id: "spanish", request: request("Hola equipo, mañana podemos ") },
  {
    id: "english",
    request: request("The release candidate is ready, so we should "),
  },
  {
    id: "code_switch",
    request: request("El deploy está green, pero todavía necesitamos "),
  },
  {
    id: "empty_related",
    request: request("", {
      shape: "single_line",
      label: "Asunto",
      relatedFields: [
        {
          shape: "multiline",
          label: "Mensaje",
          text: "Hola Dana, te comparto la propuesta actualizada para revisar mañana.",
        },
      ],
    }),
  },
  {
    id: "anti_meta",
    request: request("¿Qué es esto? No sé, pero creo que "),
  },
  { id: "cjk", request: request("明日の会議では") },
  { id: "rtl", request: request("سنتابع غدًا ") },
];

const metaLeakPattern =
  /\b(the user|user is writing|writing state|text before|text after|active cursor|system prompt|prompt says|continuation should|el usuario|estado de escritura|texto antes|cursor activo)\b/iu;
const spanishPattern =
  /(?:[áéíóúñ¿¡]|\b(?:a|de|el|en|es|esto|hacer|hay|la|lo|mañana|me|no|nos|para|podemos|por|puede|que|reunir|revisar|ser|sería|sí|seguir|terminar|todavía|un|una|vamos|con|equipo|enviar|coordinar|creo|está)\b)/iu;
const englishPattern =
  /\b(?:the|we|should|can|release|ship|review|finish|send|next|team|ready|candidate|tomorrow)\b/iu;
const cjkPattern = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/u;
const rtlPattern = /[\p{Script=Arabic}\p{Script=Hebrew}]/u;

export function scoreContinuation(input: {
  caseId: CaseId;
  textBefore: string;
  continuation: string;
}): {
  useful: boolean;
  metaLeak: boolean;
  repeatedPrefix: boolean;
  outputLength: number;
  reasons: string[];
} {
  const continuation = input.continuation.trim();
  const textBefore = input.textBefore.trim();
  const reasons: string[] = [];
  const metaLeak = metaLeakPattern.test(continuation);
  const repeatedPrefix =
    textBefore.length > 0 &&
    continuation.toLocaleLowerCase().startsWith(textBefore.toLocaleLowerCase());

  if (!continuation) reasons.push("empty");
  if (continuation.length > 180) reasons.push("too_long");
  if (/```|^\s*[{[]|\n/u.test(continuation)) reasons.push("format_noise");
  if (metaLeak) reasons.push("meta_leak");
  if (repeatedPrefix) reasons.push("repeated_prefix");

  if (input.caseId === "spanish" || input.caseId === "anti_meta") {
    if (
      (englishPattern.test(continuation) && !spanishPattern.test(continuation)) ||
      cjkPattern.test(continuation) ||
      rtlPattern.test(continuation)
    ) {
      reasons.push("wrong_language");
    }
  } else if (input.caseId === "code_switch") {
    if (
      (!spanishPattern.test(continuation) && !englishPattern.test(continuation)) ||
      cjkPattern.test(continuation) ||
      rtlPattern.test(continuation)
    ) {
      reasons.push("wrong_language");
    }
  } else if (input.caseId === "english") {
    if (
      (spanishPattern.test(continuation) && !englishPattern.test(continuation)) ||
      cjkPattern.test(continuation) ||
      rtlPattern.test(continuation)
    ) {
      reasons.push("wrong_language");
    }
  } else if (input.caseId === "empty_related") {
    if (!/(?:propuesta|proposal|revisi|mañana|dana)/iu.test(continuation)) {
      reasons.push("not_grounded_in_related_field");
    }
  } else if (input.caseId === "cjk" && !cjkPattern.test(continuation)) {
    reasons.push("wrong_script");
  } else if (input.caseId === "rtl" && !rtlPattern.test(continuation)) {
    reasons.push("wrong_script");
  }

  return {
    useful: reasons.length === 0,
    metaLeak,
    repeatedPrefix,
    outputLength: continuation.length,
    reasons,
  };
}

export function percentile(values: number[], fraction: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.max(0, Math.ceil(sorted.length * fraction) - 1);
  return Math.round(sorted[index]! * 10) / 10;
}

function safeError(error: unknown): SafeError {
  const name =
    typeof error === "object" && error !== null && "name" in error
      ? String(error.name)
      : "Error";
  const rawMessage =
    typeof error === "object" && error !== null && "message" in error
      ? String(error.message)
      : String(error);
  const message = rawMessage
    .replace(/[\r\n\t]+/gu, " ")
    .replace(/\s+/gu, " ")
    .slice(0, 500);
  const lowered = `${name} ${message}`.toLocaleLowerCase();
  const category = lowered.includes("zero data retention") || lowered.includes("zdr")
    ? "zdr"
    : lowered.includes("temperature")
      ? "temperature"
      : lowered.includes("schema") || lowered.includes("structured") || lowered.includes("output")
        ? "structured_output"
        : lowered.includes("auth")
          ? "authentication"
          : lowered.includes("rate")
            ? "rate_limit"
            : "provider_error";
  return { name, category, message };
}

function hashOutput(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 16);
}

async function runOnce(input: {
  arm: ModelArm;
  benchmarkCase: BenchmarkCase;
  phase: RunResult["phase"];
  repetition: number;
  strict: boolean;
}): Promise<RunResult> {
  const { arm, benchmarkCase, phase, repetition, strict } = input;
  const startedAt = performance.now();
  let modelCallPerformance:
    | {
        responseTimeMs?: number;
        timeToFirstOutputMs?: number;
      }
    | undefined;
  let modelCallModel: string | undefined;
  let warnings: string[] = [];
  let underlyingError: unknown;

  const zeroDataRetention = strict ? true : arm.zeroDataRetention;
  const omitTemperature = strict ? false : arm.omitTemperature === true;
  const common = {
    model: gateway(arm.id),
    instructions: CONTINUATION_INSTRUCTIONS,
    prompt: buildContinuationPrompt(benchmarkCase.request),
    reasoning: arm.reasoning,
    ...(!omitTemperature ? { temperature: 0.2 } : {}),
    maxOutputTokens: 256,
    maxRetries: 0,
    timeout: { totalMs: 30_000, firstChunkMs: 15_000, chunkMs: 15_000 },
    providerOptions: {
      gateway: {
        user: "synthetic_model_benchmark",
        tags: ["feature:autocomplete", "purpose:isolated-model-benchmark"],
        only: [arm.provider],
        ...(zeroDataRetention ? { zeroDataRetention: true } : {}),
      },
    },
    onError: ({ error }: { error: unknown }) => {
      underlyingError = error;
    },
    onLanguageModelCallEnd: (event: {
      modelId: string;
      performance: {
        responseTimeMs?: number;
        timeToFirstOutputMs?: number;
      };
    }) => {
      modelCallModel = event.modelId;
      modelCallPerformance = event.performance;
    },
  };

  let continuation: string | undefined;
  let usage: { inputTokens?: number; outputTokens?: number } | undefined;
  let providerMetadata: Record<string, unknown> | undefined;
  let error: SafeError | null = null;

  try {
    const result = streamText({
      ...common,
      output: Output.object({
        name: "insert_continuation",
        description: "The candidate text to insert exactly at the active cursor.",
        schema: continuationSchema,
      }),
    });
    const parsed = continuationSchema.parse(await result.output);
    continuation = parsed.continuation;
    usage = await result.totalUsage;
    providerMetadata = await result.providerMetadata;
    warnings = (await result.warnings)?.map((warning) => warning.type) ?? [];
  } catch (caught) {
    error = safeError(underlyingError ?? caught);
  }

  const routing = (
    providerMetadata as {
      gateway?: {
        routing?: {
          canonicalSlug?: string;
          finalProvider?: string;
          totalProviderAttemptCount?: number;
        };
      };
    } | undefined
  )?.gateway?.routing;
  const score = continuation
    ? scoreContinuation({
        caseId: benchmarkCase.id,
        textBefore: benchmarkCase.request.payload.textBefore,
        continuation,
      })
    : {
        useful: false,
        metaLeak: false,
        repeatedPrefix: false,
        outputLength: 0,
        reasons: ["no_valid_object"],
      };

  return {
    model: arm.id,
    requestedProvider: arm.provider,
    reasoning: arm.reasoning,
    zeroDataRetention,
    temperature: omitTemperature ? null : 0.2,
    adaptation: strict ? null : arm.adaptation,
    phase,
    caseId: benchmarkCase.id,
    repetition,
    ok: continuation !== undefined,
    schemaValid: continuation !== undefined,
    firstOutputMs: modelCallPerformance?.timeToFirstOutputMs ?? null,
    modelResponseMs: modelCallPerformance?.responseTimeMs ?? null,
    validObjectMs: Math.round((performance.now() - startedAt) * 10) / 10,
    inputTokens: usage?.inputTokens ?? null,
    outputTokens: usage?.outputTokens ?? null,
    resolvedModel: routing?.canonicalSlug ?? modelCallModel ?? null,
    resolvedProvider: routing?.finalProvider ?? null,
    providerAttemptCount: routing?.totalProviderAttemptCount ?? null,
    warnings,
    output: {
      hash: continuation ? hashOutput(continuation) : null,
      length: score.outputLength,
      useful: score.useful,
      metaLeak: score.metaLeak,
      repeatedPrefix: score.repeatedPrefix,
      reasons: score.reasons,
    },
    error,
  };
}

function summarize(results: RunResult[]) {
  return arms.map((arm) => {
    const measured = results.filter(
      (result) => result.model === arm.id && result.phase === "measured",
    );
    const successes = measured.filter((result) => result.ok);
    const useful = successes.filter((result) => result.output.useful);
    const firstOutput = successes.flatMap((result) =>
      result.firstOutputMs === null ? [] : [result.firstOutputMs],
    );
    const validObject = successes.map((result) => result.validObjectMs);
    const response = successes.flatMap((result) =>
      result.modelResponseMs === null ? [] : [result.modelResponseMs],
    );
    const inputs = successes.flatMap((result) =>
      result.inputTokens === null ? [] : [result.inputTokens],
    );
    const outputs = successes.flatMap((result) =>
      result.outputTokens === null ? [] : [result.outputTokens],
    );
    return {
      model: arm.id,
      provider: arm.provider,
      reasoning: arm.reasoning,
      adaptation: arm.adaptation,
      attempts: measured.length,
      schemaSuccesses: successes.length,
      usefulSuccesses: useful.length,
      metaLeaks: successes.filter((result) => result.output.metaLeak).length,
      repeatedPrefixes: successes.filter((result) => result.output.repeatedPrefix).length,
      firstOutputMs: {
        p50: percentile(firstOutput, 0.5),
        p95: percentile(firstOutput, 0.95),
      },
      validObjectMs: {
        p50: percentile(validObject, 0.5),
        p95: percentile(validObject, 0.95),
      },
      modelResponseMs: {
        p50: percentile(response, 0.5),
        p95: percentile(response, 0.95),
      },
      averageTokens: {
        input:
          inputs.length === 0
            ? null
            : Math.round(inputs.reduce((sum, value) => sum + value, 0) / inputs.length),
        output:
          outputs.length === 0
            ? null
            : Math.round(outputs.reduce((sum, value) => sum + value, 0) / outputs.length),
      },
      resolvedProviders: [...new Set(successes.map((result) => result.resolvedProvider))],
      providerAttempts: [...new Set(successes.map((result) => result.providerAttemptCount))],
      failureCategories: measured
        .filter((result) => result.error)
        .map((result) => result.error!.category),
      qualityFailures: measured
        .filter((result) => result.ok && !result.output.useful)
        .reduce<Record<string, number>>((counts, result) => {
          for (const reason of result.output.reasons) {
            counts[reason] = (counts[reason] ?? 0) + 1;
          }
          return counts;
        }, {}),
    };
  });
}

async function liveCatalogSnapshot() {
  const response = await fetch("https://ai-gateway.vercel.sh/v1/models");
  if (!response.ok) throw new Error(`catalog_http_${response.status}`);
  const body = (await response.json()) as {
    data: Array<Record<string, unknown> & { id?: string }>;
  };
  return arms.map((arm) => {
    const model = body.data.find((candidate) => candidate.id === arm.id);
    return {
      id: arm.id,
      found: model !== undefined,
      zdr: model?.zdr ?? null,
      temperature: model?.temperature ?? null,
      reasoningOptions: model?.reasoning_options ?? null,
      supportedParameters: model?.supported_parameters ?? null,
    };
  });
}

async function main() {
  if (process.env.AI_GATEWAY_API_KEY === "[SENSITIVE]") {
    delete process.env.AI_GATEWAY_API_KEY;
  }
  const mode = process.argv.find((argument) => argument.startsWith("--mode="))?.split("=")[1] ?? "all";
  const outputPath = process.argv.find((argument) => argument.startsWith("--out="))?.slice(6);
  const results: RunResult[] = [];
  const catalog = await liveCatalogSnapshot();
  const preflightViable = new Set<string>();

  if (mode === "all" || mode === "preflight") {
    for (const arm of arms) {
      process.stderr.write(`preflight strict ${arm.id}@${arm.provider}\n`);
      const strict = await runOnce({
        arm,
        benchmarkCase: cases[0]!,
        phase: "preflight_strict",
        repetition: 0,
        strict: true,
      });
      results.push(strict);

      if (arm.adaptation === null) {
        if (strict.ok) preflightViable.add(arm.id);
        continue;
      }

      process.stderr.write(`preflight effective ${arm.id}@${arm.provider}\n`);
      const effective = await runOnce({
        arm,
        benchmarkCase: cases[0]!,
        phase: "preflight_effective",
        repetition: 0,
        strict: false,
      });
      results.push(effective);
      if (effective.ok) preflightViable.add(arm.id);
    }
  }

  if (mode === "all" || mode === "full") {
    if (mode === "full") arms.forEach((arm) => preflightViable.add(arm.id));
    for (const arm of arms.filter((candidate) => preflightViable.has(candidate.id))) {
      process.stderr.write(`warmup ${arm.id}@${arm.provider}\n`);
      results.push(
        await runOnce({
          arm,
          benchmarkCase: cases[0]!,
          phase: "warmup",
          repetition: 0,
          strict: false,
        }),
      );
    }
    for (let repetition = 1; repetition <= 3; repetition += 1) {
      for (const benchmarkCase of cases) {
        for (const arm of arms.filter((candidate) => preflightViable.has(candidate.id))) {
          process.stderr.write(
            `measure ${repetition}/3 ${benchmarkCase.id} ${arm.id}@${arm.provider}\n`,
          );
          results.push(
            await runOnce({
              arm,
              benchmarkCase,
              phase: "measured",
              repetition,
              strict: false,
            }),
          );
        }
      }
    }
  }

  const report = {
    generatedAt: new Date().toISOString(),
    methodology: {
      prompt: "production CONTINUATION_INSTRUCTIONS and buildContinuationPrompt",
      schema: "production-equivalent Output.object insert_continuation schema",
      warmupsExcluded: 1,
      cases: cases.map((benchmarkCase) => benchmarkCase.id),
      repetitions: 3,
      routing: "one exact provider in gateway.only; no sort; no fallback",
      privacy: "continuation text omitted; only a 16-character SHA-256 prefix and derived scores are stored",
    },
    catalog,
    preflight: results.filter((result) => result.phase.startsWith("preflight")),
    summary: summarize(results),
    runs: results.filter((result) => result.phase === "warmup" || result.phase === "measured"),
  };
  const serialized = `${JSON.stringify(report, null, 2)}\n`;
  if (outputPath) {
    await writeFile(outputPath, serialized, { encoding: "utf8", mode: 0o600 });
    process.stdout.write(`${outputPath}\n`);
  } else {
    process.stdout.write(serialized);
  }
}

if (import.meta.main) {
  await main();
}
