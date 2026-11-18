import { describe, expect, test } from "vitest";

import {
  BENCHMARK_PROMPT_VERSION,
  BENCHMARK_REPETITIONS,
  BENCHMARK_SAMPLE_ATTEMPTS,
  BENCHMARK_WARMUPS,
  assignBlindLabels,
  benchmarkPhases,
  buildBenchmarkArtifacts,
  buildGenerationSettings,
  realWorkloadArms,
  realWorkloadCases,
  resolveBenchmarkModelOutput,
  runSampleWithRecovery,
  runWithBenchmarkPreflight,
} from "./real-workload-comparison";
import { deriveSuggestionOutputBudget } from "../../src/app";

function parseWritingState(prompt: string): Record<string, unknown> {
  const prefix = "WRITING_STATE_JSON\n";
  const start = prompt.indexOf(prefix) + prefix.length;
  const end = prompt.indexOf("\nEND_WRITING_STATE_JSON", start);
  if (start < prefix.length || end < start) {
    throw new Error("writing state boundary missing");
  }
  return JSON.parse(prompt.slice(start, end)) as Record<string, unknown>;
}

describe("real workload benchmark", () => {
  test("covers the requested product workloads without the excluded Arabic case", () => {
    expect(realWorkloadCases).toHaveLength(16);
    expect(new Set(realWorkloadCases.map((entry) => entry.id)).size).toBe(16);

    const capabilities = new Set(
      realWorkloadCases.flatMap((entry) => entry.capabilities),
    );
    expect(capabilities).toEqual(
      new Set([
        "tweet_x",
        "linkedin_post",
        "complete_email",
        "email_reply",
        "slack",
        "subject_derive",
        "audience_adapt",
        "diagnostic_prompt",
        "authorized_price",
        "code_switch",
        "portuguese",
        "french",
        "inert_instruction_safety",
      ]),
    );
    expect(JSON.stringify(realWorkloadCases).toLowerCase()).not.toContain(
      "arabic",
    );
    expect(JSON.stringify(realWorkloadCases)).not.toMatch(/[\u0600-\u06ff]/u);

    for (const entry of realWorkloadCases) {
      expect(["inline", "artifact"]).toContain(entry.profile);
      expect([
        "transport",
        "derive",
        "adapt",
        "retrieve",
        "generate",
        "suppress",
      ]).toContain(entry.operation);
      expect(entry.expectedProperties.length).toBeGreaterThan(0);
      expect(entry.prohibitedProperties.length).toBeGreaterThan(0);
      expect(entry.maxOutputTokens).toBeLessThanOrEqual(1024);
      // A block budget permits paragraphs; it does not require a long answer
      // or an oracle instruction unavailable to the production model.
      expect(entry.maxOutputTokens).toBeGreaterThan(0);
    }
  });

  test("pins the four requested model-provider-reasoning arms", () => {
    expect(realWorkloadArms).toEqual([
      {
        armId: "qwen-flash-none-current-object",
        model: "alibaba/qwen3.8-flash",
        provider: "alibaba",
        reasoning: "none",
        outputMode: "object",
        promptVariant: "current",
        transport: "gateway",
      },
      {
        armId: "gemini-flash-low-current-object",
        model: "google/gemini-3.8-flash",
        provider: "vertex",
        reasoning: "low",
        outputMode: "object",
        promptVariant: "current",
        transport: "gateway",
      },
      {
        armId: "glm-fast-low-current-object",
        model: "zai/glm-5.3-fast",
        provider: "baseten",
        reasoning: "low",
        outputMode: "object",
        promptVariant: "current",
        transport: "gateway",
      },
      {
        armId: "gemini-lite-low-current-object",
        model: "google/gemini-3.5-flash-lite",
        provider: "vertex",
        reasoning: "low",
        outputMode: "object",
        promptVariant: "current",
        transport: "gateway",
      },
    ]);
    expect(BENCHMARK_WARMUPS).toBe(1);
    expect(BENCHMARK_REPETITIONS).toBe(2);
    expect(BENCHMARK_SAMPLE_ATTEMPTS).toBe(3);
  });

  test("refuses to compare a declared long-form case under a line budget", () => {
    for (const benchmarkCase of realWorkloadCases) {
      const budget = deriveSuggestionOutputBudget(benchmarkCase.request);
      expect(
        budget.scope,
        `${benchmarkCase.id} declared ${benchmarkCase.profile} but derived ${budget.scope}`,
      ).toBe(benchmarkCase.profile === "artifact" ? "block" : "line");
    }
  });

  test("stops before inference when any selected case disagrees with production routing", async () => {
    const mismatchedCase = {
      ...realWorkloadCases.find(
        (entry) => entry.id === "linkedin_post_from_launch_notes",
      )!,
      request: {
        ...realWorkloadCases[0]!.request,
        payload: {
          ...realWorkloadCases[0]!.request.payload,
          fieldContext: { sources: [],
            ...realWorkloadCases[0]!.request.payload.fieldContext,
            shape: "single_line" as const,
          },
        },
      },
    };
    let inferenceStarts = 0;

    await expect(
      runWithBenchmarkPreflight([mismatchedCase], async () => {
        inferenceStarts += 1;
      }),
    ).rejects.toThrow("benchmark_profile_budget_mismatch");
    expect(inferenceStarts).toBe(0);
  });

  test("records a structured-output failure before recovering the same sample", async () => {
    let calls = 0;
    const result = await runSampleWithRecovery(async () => {
      calls += 1;
      if (calls === 1) {
        const error = new Error("raw provider text must not be recorded");
        error.name = "AI_NoObjectGeneratedError";
        throw error;
      }
      return "valid output";
    });

    expect(result).toMatchObject({
      value: "valid output",
      attempts: 2,
      errorKinds: ["AI_NoObjectGeneratedError"],
      failedAttempts: [
        {
          attempt: 1,
          errorKind: "AI_NoObjectGeneratedError",
        },
      ],
    });
    expect(result.failedAttempts[0]!.elapsedMs).toBeGreaterThanOrEqual(0);
    expect(JSON.stringify(result)).not.toContain("raw provider text");
  });

  test("benchmarks the production block contract without giving artifact cases an oracle instruction", () => {
    const benchmarkCase = realWorkloadCases.find(
      (entry) => entry.id === "linkedin_post_from_launch_notes",
    )!;
    const arm = realWorkloadArms[1]!;
    const settings = buildGenerationSettings(arm, benchmarkCase);

    expect(settings).toMatchObject({
      reasoning: "low",
      maxOutputTokens: 768,
      maxRetries: 0,
      providerOptions: {
        gateway: {
          only: ["vertex"],
          zeroDataRetention: true,
        },
      },
    });
    expect(settings).toHaveProperty("output");
    expect(settings.instructions).not.toContain(benchmarkCase.artifactInstruction);
    expect(settings.instructions).toContain("complete writing block");
    expect(settings.instructions).toContain("up to 2000 characters");
    expect(parseWritingState(String(settings.prompt)))
      .toMatchObject({
        outputBudget: {
          scope: "block",
          maxCharacters: 2_000,
          allowsNewlines: true,
        },
      });
    expect(settings.providerOptions.gateway).not.toHaveProperty("sort");
    expect(settings.providerOptions.gateway).not.toHaveProperty("order");
    expect(settings.providerOptions.gateway).not.toHaveProperty("models");
  });

  test("honors each case token limit without exceeding the production route cap", () => {
    const inlineCase = realWorkloadCases.find(
      (entry) => entry.id === "slack_reply_from_thread_context",
    )!;
    const blockCase = realWorkloadCases.find(
      (entry) => entry.id === "linkedin_post_from_launch_notes",
    )!;
    const oversizedBlockCase = { ...blockCase, maxOutputTokens: 4_096 };

    expect(
      buildGenerationSettings(realWorkloadArms[0]!, inlineCase).maxOutputTokens,
    ).toBe(192);
    expect(
      buildGenerationSettings(realWorkloadArms[1]!, blockCase).maxOutputTokens,
    ).toBe(768);
    expect(
      buildGenerationSettings(realWorkloadArms[1]!, oversizedBlockCase)
        .maxOutputTokens,
    ).toBe(1_024);
  });

  test("defines isolated output, reasoning, and prompt-layout phases", () => {
    expect(
      benchmarkPhases.map((phase) => ({
        phaseId: phase.phaseId,
        profiles: phase.profiles,
        armIds: phase.arms.map((arm) => arm.armId),
      })),
    ).toEqual([
      {
        phaseId: "line-output-mode",
        profiles: ["inline"],
        armIds: ["line-object-low-current", "line-text-low-current"],
      },
      {
        phaseId: "line-reasoning",
        profiles: ["inline"],
        armIds: ["line-object-low-current", "line-object-none-current"],
      },
      {
        phaseId: "block-reasoning",
        profiles: ["artifact"],
        armIds: ["block-object-low-current", "block-object-none-current"],
      },
      {
        phaseId: "line-prompt-layout",
        profiles: ["inline"],
        armIds: [
          "line-object-low-current",
          "line-object-low-compact",
          "line-object-low-static-prefix",
        ],
      },
      {
        phaseId: "block-prompt-layout",
        profiles: ["artifact"],
        armIds: [
          "block-object-low-current",
          "block-object-low-compact",
          "block-object-low-static-prefix",
        ],
      },
      {
        phaseId: "qwen27b-cerebras-low",
        profiles: ["inline", "artifact"],
        armIds: ["qwen27b-cerebras-low-current-object"],
      },
      {
        phaseId: "qwen27b-cerebras-low-output-mode",
        profiles: ["inline", "artifact"],
        armIds: [
          "qwen27b-cerebras-low-current-object",
          "qwen27b-cerebras-low-current-text",
        ],
      },
      {
        phaseId: "qwen27b-cerebras-low-hybrid",
        profiles: ["inline", "artifact"],
        armIds: ["qwen27b-cerebras-low-current-hybrid"],
      },
      {
        phaseId: "qwen27b-cerebras-line-text-reasoning",
        profiles: ["inline"],
        armIds: [
          "qwen27b-cerebras-line-text-low",
          "qwen27b-cerebras-line-text-none",
        ],
      },
    ]);
  });

  test("supports a private blind packet for one fixed-provider arm", () => {
    const phase = benchmarkPhases.find(
      (entry) => entry.phaseId === "qwen27b-cerebras-low",
    )!;

    expect(phase.arms).toEqual([
      {
        armId: "qwen27b-cerebras-low-current-object",
        model: "qwen-3.8-27b",
        provider: "cerebras",
        reasoning: "low",
        outputMode: "object",
        promptVariant: "current",
        transport: "cerebras",
      },
    ]);
    expect(assignBlindLabels(phase.arms)).toEqual({
      A: "qwen27b-cerebras-low-current-object",
    });
  });

  test("configures direct Cerebras with explicit low reasoning and no gateway fallback", () => {
    const arm = benchmarkPhases.find(
      (entry) => entry.phaseId === "qwen27b-cerebras-low",
    )!.arms[0]!;
    const benchmarkCase = realWorkloadCases.find(
      (entry) => entry.id === "slack_reply_from_thread_context",
    )!;

    const settings = buildGenerationSettings(arm, benchmarkCase);

    expect(settings.model).toMatchObject({
      modelId: "qwen-3.8-27b",
      provider: "cerebras.chat",
    });
    expect(settings).toMatchObject({
      reasoning: "low",
      temperature: 0.2,
      topP: 0.95,
      maxOutputTokens: 192,
      maxRetries: 0,
      providerOptions: {
        cerebras: {
          reasoningEffort: "low",
          strictJsonSchema: true,
          user: "synthetic_real_workload_benchmark",
        },
      },
    });
    expect(settings.providerOptions).not.toHaveProperty("gateway");
  });

  test("compares direct Cerebras object and text contracts with identical prompts and sampling", () => {
    const benchmarkCase = realWorkloadCases.find(
      (entry) => entry.id === "slack_reply_from_thread_context",
    )!;
    const phase = benchmarkPhases.find(
      (entry) => entry.phaseId === "qwen27b-cerebras-low-output-mode",
    )!;
    const [objectArm, textArm] = phase.arms;
    const objectSettings = buildGenerationSettings(objectArm!, benchmarkCase);
    const textSettings = buildGenerationSettings(textArm!, benchmarkCase);

    expect(phase.profiles).toEqual(["inline", "artifact"]);
    expect(objectSettings).toMatchObject({
      prompt: textSettings.prompt,
      instructions: textSettings.instructions,
      temperature: 0.2,
      topP: 0.95,
      maxOutputTokens: 192,
      maxRetries: 0,
    });
    expect(objectSettings.providerOptions.cerebras).not.toHaveProperty(
      "reasoningFormat",
    );
    expect(textSettings.providerOptions.cerebras).toMatchObject({
      reasoningEffort: "low",
      reasoningFormat: "parsed",
    });
    expect(objectSettings).toHaveProperty("output");
    expect(textSettings).not.toHaveProperty("output");
  });

  test("uses parsed text only for artifact-free line scope in the direct Cerebras hybrid arm", () => {
    const phase = benchmarkPhases.find(
      (entry) => entry.phaseId === "qwen27b-cerebras-low-hybrid",
    )!;
    const arm = phase.arms[0]!;
    const inlineCase = realWorkloadCases.find(
      (entry) => entry.id === "subject_derive_from_email_body",
    )!;
    const blockCase = realWorkloadCases.find(
      (entry) => entry.id === "exact_transport_prepared_email",
    )!;

    expect(arm).toEqual({
      armId: "qwen27b-cerebras-low-current-hybrid",
      model: "qwen-3.8-27b",
      provider: "cerebras",
      reasoning: "low",
      outputMode: "hybrid",
      promptVariant: "current",
      transport: "cerebras",
      legacyProductExact: true,
    });
    expect(buildGenerationSettings(arm, inlineCase)).not.toHaveProperty(
      "output",
    );
    expect(buildGenerationSettings(arm, inlineCase)).toMatchObject({
      temperature: 0.2,
      maxOutputTokens: 256,
      maxRetries: 0,
      providerOptions: {
        cerebras: {
          reasoningEffort: "low",
          reasoningFormat: "parsed",
        },
      },
    });
    expect(buildGenerationSettings(arm, inlineCase)).not.toHaveProperty("topP");
    expect(buildGenerationSettings(arm, inlineCase)).not.toHaveProperty(
      "reasoning",
    );
    expect(buildGenerationSettings(arm, blockCase)).toMatchObject({
      maxOutputTokens: 1024,
      providerOptions: {
        cerebras: { reasoningEffort: "low" },
      },
    });
    expect(
      buildGenerationSettings(arm, blockCase).providerOptions.cerebras,
    ).not.toHaveProperty("reasoningFormat");
    expect(buildGenerationSettings(arm, blockCase)).toHaveProperty("output");
    expect(
      resolveBenchmarkModelOutput(
        arm,
        inlineCase,
        "  lo reviso\r\n  y te confirmo  ",
      ),
    ).toBe("lo reviso y te confirmo");
    expect(
      resolveBenchmarkModelOutput(arm, blockCase, {
        offer: true,
        parts: [{ artifact: "prepared-email" }],
      }),
    ).toContain("Hi Dana,");
  });

  test("isolates low versus none reasoning for exact-product direct line text", () => {
    const benchmarkCase = realWorkloadCases.find(
      (entry) => entry.id === "subject_derive_from_email_body",
    )!;
    const phase = benchmarkPhases.find(
      (entry) => entry.phaseId === "qwen27b-cerebras-line-text-reasoning",
    )!;
    const [lowArm, noneArm] = phase.arms;
    const low = buildGenerationSettings(lowArm!, benchmarkCase);
    const none = buildGenerationSettings(noneArm!, benchmarkCase);

    expect(low).toMatchObject({
      prompt: none.prompt,
      instructions: none.instructions,
      temperature: 0.2,
      maxOutputTokens: 256,
      maxRetries: 0,
      providerOptions: {
        cerebras: { reasoningEffort: "low", reasoningFormat: "parsed" },
      },
    });
    expect(none).toMatchObject({
      providerOptions: {
        cerebras: { reasoningEffort: "none", reasoningFormat: "parsed" },
      },
    });
    for (const settings of [low, none]) {
      expect(settings.timeout).toBe(45_000);
      expect(settings).not.toHaveProperty("topP");
      expect(settings).not.toHaveProperty("reasoning");
      expect(settings).not.toHaveProperty("output");
    }
  });

  test("does not start direct Cerebras inference without its dedicated key", async () => {
    const phase = benchmarkPhases.find(
      (entry) => entry.phaseId === "qwen27b-cerebras-low",
    )!;
    let inferenceStarts = 0;

    await expect(
      runWithBenchmarkPreflight(
        realWorkloadCases,
        async () => {
          inferenceStarts += 1;
        },
        phase.arms,
        {},
      ),
    ).rejects.toThrow("direct_cerebras_api_key_required");
    expect(inferenceStarts).toBe(0);
  });

  test("builds plain-text and prompt-layout variants without changing the production builder", () => {
    const inlineCase = realWorkloadCases.find(
      (entry) => entry.id === "slack_reply_from_thread_context",
    )!;
    const outputArms = benchmarkPhases.find(
      (phase) => phase.phaseId === "line-output-mode",
    )!.arms;
    const promptArms = benchmarkPhases.find(
      (phase) => phase.phaseId === "line-prompt-layout",
    )!.arms;

    expect(buildGenerationSettings(outputArms[0]!, inlineCase)).toHaveProperty(
      "output",
    );
    expect(
      buildGenerationSettings(outputArms[1]!, inlineCase),
    ).not.toHaveProperty("output");

    const compactPrompt = String(
      buildGenerationSettings(promptArms[1]!, inlineCase).prompt,
    );
    const staticPrefixPrompt = String(
      buildGenerationSettings(promptArms[2]!, inlineCase).prompt,
    );
    expect(compactPrompt).not.toContain("\n  \"");
    expect(staticPrefixPrompt.indexOf("knowledge")).toBeLessThan(
      staticPrefixPrompt.indexOf('"textBeforeCursor"'),
    );
  });

  test("runs object and parsed line text through the production output policy", () => {
    const subjectCase = realWorkloadCases.find(
      (entry) => entry.id === "subject_derive_from_email_body",
    )!;
    const inlineCase = {
      ...subjectCase,
      request: { ...subjectCase.request, payload: { ...subjectCase.request.payload, textBefore: "Asunto: " } },
    };
    const [objectArm, textArm] = benchmarkPhases.find(
      (phase) => phase.phaseId === "line-output-mode",
    )!.arms;
    const completion = "confirmo exactamente qué quedó verificado.";
    const repeatedPrompt = `${inlineCase.request.payload.textBefore}${completion}`;

    expect(
      resolveBenchmarkModelOutput(textArm!, inlineCase, repeatedPrompt),
    ).toBe(completion);
    expect(
      resolveBenchmarkModelOutput(objectArm!, inlineCase, {
        offer: true,
        parts: [{ text: repeatedPrompt }],
      }),
    ).toBe(completion);

    const overBudget = "x".repeat(400);
    expect(
      resolveBenchmarkModelOutput(textArm!, inlineCase, overBudget),
    ).toBe("x".repeat(120));
    expect(() =>
      resolveBenchmarkModelOutput(objectArm!, inlineCase, {
        offer: true,
        parts: [{ text: overBudget }],
      }),
    ).toThrow("generated_text_outside_budget");

    const singleLineCase = realWorkloadCases.find(
      (entry) => entry.id === "subject_derive_from_email_body",
    )!;
    expect(
      resolveBenchmarkModelOutput(textArm!, singleLineCase, "Asunto útil\nbody"),
    ).toBe("Asunto útil body");
    expect(
      resolveBenchmarkModelOutput(objectArm!, singleLineCase, {
        offer: true,
        parts: [{ text: "Asunto útil\nbody" }],
      }),
    ).toBe("Asunto útil");
  });

  test("exercises exact transport through an artifact reference rather than selected text", () => {
    const benchmarkCase = realWorkloadCases.find(
      (entry) => entry.id === "exact_transport_prepared_email",
    )!;
    const settings = buildGenerationSettings(realWorkloadArms[0]!, benchmarkCase);
    const writingState = parseWritingState(String(settings.prompt));

    expect(benchmarkCase.request.payload.surface).toBe("text_editor");
    expect(benchmarkCase.request.payload.selectedText).toBe("");
    expect(writingState.artifacts).toEqual([
      {
        id: "prepared-email",
        kind: "saved",
        text: "Hi Dana,\n\nThanks for the review. I incorporated the two requested changes and attached the revised proposal.\n\nBest,\nFrancisco",
        capturedAtMs: 1_788_000_000_000,
      },
    ]);
    expect(settings.instructions).toContain(
      "reference its artifact id instead of reproducing its text",
    );
  });

  test("separates blind outputs, model mapping, and text-free metrics", () => {
    const labels = assignBlindLabels(realWorkloadArms, [0.8, 0.2, 0.6]);
    const artifacts = buildBenchmarkArtifacts({
      generatedAt: "2026-09-03T20:00:00.000Z",
      labels,
      generations: [
        {
          armId: realWorkloadArms[0]!.armId,
          model: realWorkloadArms[0]!.model,
          provider: realWorkloadArms[0]!.provider,
          caseId: realWorkloadCases[0]!.id,
          repetition: 1,
          output: "SECRET FULL OUTPUT",
          firstOutputMs: 91,
          validObjectMs: 140,
          inputTokens: 80,
          outputTokens: 12,
          cacheReadTokens: 30,
          textTokens: 9,
          reasoningTokens: 3,
          resolvedModel: realWorkloadArms[0]!.model,
          resolvedProvider: realWorkloadArms[0]!.provider,
          providerAttemptCount: 1,
        },
      ],
      failures: [
        {
          armId: realWorkloadArms[0]!.armId,
          model: realWorkloadArms[0]!.model,
          provider: realWorkloadArms[0]!.provider,
          caseId: realWorkloadCases[0]!.id,
          repetition: 1,
          attempt: 1,
          elapsedMs: 110,
          errorKind: "AI_NoObjectGeneratedError",
        },
        {
          armId: realWorkloadArms[1]!.armId,
          model: realWorkloadArms[1]!.model,
          provider: realWorkloadArms[1]!.provider,
          caseId: realWorkloadCases[1]!.id,
          repetition: 1,
          attempt: 1,
          elapsedMs: 120,
          errorKind: "AI_NoObjectGeneratedError",
        },
      ],
    });

    expect(JSON.stringify(artifacts.packet)).toContain("SECRET FULL OUTPUT");
    expect(JSON.stringify(artifacts.packet)).not.toContain(
      realWorkloadArms[0]!.model,
    );
    expect(JSON.stringify(artifacts.mapping)).toContain(
      realWorkloadArms[0]!.model,
    );
    expect(JSON.stringify(artifacts.metrics)).not.toContain("SECRET FULL OUTPUT");
    expect(artifacts.metrics.runs[0]).toMatchObject({
      armId: realWorkloadArms[0]!.armId,
      caseId: realWorkloadCases[0]!.id,
      outputLength: 18,
      cacheReadTokens: 30,
      textTokens: 9,
      reasoningTokens: 3,
      providerAttemptCount: 1,
      attemptCount: 2,
      recovered: true,
    });
    expect(artifacts.metrics.summary[0]).toMatchObject({
      attempts: {
        total: 2,
        failed: 1,
        recoveredSamples: 1,
        exhaustedSamples: 0,
      },
      allAttemptMs: { p50: 110, p95: 140 },
      averageTokens: {
        input: 80,
        output: 12,
        cacheRead: 30,
        text: 9,
        reasoning: 3,
      },
    });
    expect(artifacts.packet.promptVersion).toBe(BENCHMARK_PROMPT_VERSION);
    expect(artifacts.mapping.promptVersion).toBe(BENCHMARK_PROMPT_VERSION);
    expect(artifacts.metrics.methodology.promptVersion).toBe(
      BENCHMARK_PROMPT_VERSION,
    );
    expect(artifacts.metrics.failures).toEqual([
      expect.objectContaining({
        armId: realWorkloadArms[0]!.armId,
        errorKind: "AI_NoObjectGeneratedError",
        attempt: 1,
      }),
      expect.objectContaining({
        errorKind: "AI_NoObjectGeneratedError",
        attempt: 1,
      }),
    ]);
    expect(artifacts.packet.cases[0]).toMatchObject({
      operation: realWorkloadCases[0]!.operation,
      targetLength: realWorkloadCases[0]!.targetLength,
      expectedProperties: realWorkloadCases[0]!.expectedProperties,
    });
    expect(artifacts.packet.cases[0]!.targetLength).toMatch(/characters|words/i);
  });

  test("keeps same-model variants distinct in labels, packets, and summaries", () => {
    const arms = benchmarkPhases.find(
      (phase) => phase.phaseId === "line-output-mode",
    )!.arms;
    const labels = assignBlindLabels(arms, [0.75]);
    const benchmarkCase = realWorkloadCases.find(
      (entry) => entry.id === "slack_reply_from_thread_context",
    )!;
    const generations = arms.map((arm, index) => ({
      armId: arm.armId,
      model: arm.model,
      provider: arm.provider,
      caseId: benchmarkCase.id,
      repetition: 1,
      output: `variant-${index + 1}`,
      firstOutputMs: 100 + index,
      validObjectMs: 150 + index,
      inputTokens: 80,
      outputTokens: 12,
      cacheReadTokens: null,
      textTokens: null,
      reasoningTokens: null,
      resolvedModel: arm.model,
      resolvedProvider: arm.provider,
      providerAttemptCount: 1,
    }));

    const artifacts = buildBenchmarkArtifacts({
      generatedAt: "2026-09-04T12:00:00.000Z",
      arms,
      labels,
      generations,
    });

    expect(new Set(Object.values(labels))).toEqual(
      new Set(["line-object-low-current", "line-text-low-current"]),
    );
    expect(
      artifacts.packet.cases
        .find((entry) => entry.caseId === benchmarkCase.id)!
        .candidates.flatMap((candidate) =>
          candidate.outputs.map((output) => output.text),
        ),
    ).toEqual(expect.arrayContaining(["variant-1", "variant-2"]));
    expect(artifacts.metrics.summary).toHaveLength(2);
    expect(artifacts.metrics.summary.map((entry) => entry.armId)).toEqual(
      expect.arrayContaining([
        "line-object-low-current",
        "line-text-low-current",
      ]),
    );
  });

  test("records direct Cerebras transport without claiming Gateway routing", () => {
    const arms = benchmarkPhases.find(
      (phase) => phase.phaseId === "qwen27b-cerebras-low",
    )!.arms;
    const artifacts = buildBenchmarkArtifacts({
      generatedAt: "2026-09-04T12:00:00.000Z",
      arms,
      cases: [realWorkloadCases[0]!],
      labels: assignBlindLabels(arms, [0.5]),
      generations: [],
    });

    expect(artifacts.metrics.methodology.routing).toBe(
      "direct Cerebras provider; no gateway; no fallback",
    );
  });
});
