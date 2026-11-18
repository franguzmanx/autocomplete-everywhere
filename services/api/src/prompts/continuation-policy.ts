import { normalizeContinuation } from "./continuation.js";

const FENCE_PREFIXES = ["```", "~~~"] as const;

export type ContinuationPolicyOptions = {
  maxOutputLength?: number;
  singleLine?: boolean;
  preserveLineEndings?: boolean;
  preserveExactComposition?: boolean;
};

export function finalizeContinuation(
  textBefore: string,
  candidate: string | undefined,
  options: ContinuationPolicyOptions = {},
): string {
  if (candidate === undefined) return "";
  if (options.preserveExactComposition) {
    // An exact transport is indivisible: reject incompatible shape or unsafe
    // bytes rather than trim, repeat-strip, normalize or truncate the source.
    if (!candidate.trim() ||
      safeUnicodePrefix(candidate).length !== candidate.length ||
      candidate.length > (options.maxOutputLength ?? 2_000) ||
      (options.singleLine && /[\r\n]/u.test(candidate))) return "";
    return candidate;
  }
  const preserveLineEndings = options.preserveLineEndings === true;
  const normalizedBefore = preserveLineEndings
    ? textBefore
    : textBefore.replace(/\r\n?/gu, "\n");
  const normalizedCandidate = preserveLineEndings
    ? candidate
    : candidate.replace(/\r\n?/gu, "\n");
  const safety = safeUnicodePrefix(normalizedCandidate);
  const safeCandidate = normalizedCandidate.slice(0, safety.length);
  if (!safeCandidate.trim()) return "";

  const trimmed = safeCandidate.trimStart();
  if (
    FENCE_PREFIXES.some(
      (prefix) => trimmed.startsWith(prefix) || prefix.startsWith(trimmed),
    )
  ) {
    return "";
  }

  const continuation = normalizeContinuation(
    normalizedBefore,
    safeCandidate,
    preserveLineEndings,
  );
  if (continuation === null) return "";
  const firstLine = continuation.split(/\r\n?|\n/u, 1)[0] ?? "";
  const shaped = options.singleLine
    ? normalizedBefore.length === 0
      ? firstLine.trim()
      : firstLine
    : continuation;
  return truncateAtGraphemeBoundary(
    shaped,
    options.maxOutputLength ?? 2_000,
  );
}

function safeUnicodePrefix(input: string): { length: number } {
  let index = 0;
  while (index < input.length) {
    const codeUnit = input.charCodeAt(index);
    if (isUnsafeControl(codeUnit) || isLowSurrogate(codeUnit)) {
      return { length: index };
    }
    if (!isHighSurrogate(codeUnit)) {
      index += 1;
      continue;
    }
    if (
      index + 1 === input.length ||
      !isLowSurrogate(input.charCodeAt(index + 1))
    ) {
      return { length: index };
    }
    index += 2;
  }
  return { length: input.length };
}

function isHighSurrogate(codeUnit: number): boolean {
  return codeUnit >= 0xd800 && codeUnit <= 0xdbff;
}

function isLowSurrogate(codeUnit: number): boolean {
  return codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
}

function isUnsafeControl(codeUnit: number): boolean {
  return (
    (codeUnit >= 0x00 && codeUnit <= 0x08) ||
    codeUnit === 0x0b ||
    codeUnit === 0x0c ||
    (codeUnit >= 0x0e && codeUnit <= 0x1f) ||
    (codeUnit >= 0x7f && codeUnit <= 0x9f)
  );
}

function truncateAtGraphemeBoundary(input: string, maxLength: number): string {
  if (input.length <= maxLength) return input;
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  let output = "";
  for (const { segment } of segmenter.segment(input)) {
    if (output.length + segment.length > maxLength) break;
    output += segment;
  }
  return output;
}
