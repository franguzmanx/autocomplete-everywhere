import { expect, it } from 'vitest';
import { defaultTransformSettings } from '../../../packages/protocol/src/transforms';
import { TransformGenerator } from '../src/models/transform';
const input = { text: 'Synthetic source', transform: defaultTransformSettings().transforms[0]!, singleLine: false, userId: 'test', signal: new AbortController().signal };
it('rejects token-truncated rewrites even when the stream ends normally', async () => {
  const generate = (() => ({ textStream: (async function* () { yield 'Only half'; })(), finishReason: Promise.resolve('length') })) as never;
  const generator = new TransformGenerator(() => 'test' as never, 'configured-model', generate);
  await expect(generator.transform(input)).rejects.toThrow('incomplete_result');
});
it('uses the configured fast model and returns the entire completed rewrite', async () => {
  const generate = ((options: Record<string, unknown>) => {
    expect(options).toMatchObject({ model: 'configured-model', maxRetries: 0, providerOptions: { gateway: { only: ["vertex"], zeroDataRetention: true }, google: { thinkingConfig: { thinkingLevel: 'low', includeThoughts: false } } } });
    expect(JSON.parse(options.prompt as string).text).toBe(input.text);
    return { textStream: (async function* () { yield 'Complete '; yield 'rewrite'; })(), finishReason: Promise.resolve('stop') };
  }) as never;
  const generator = new TransformGenerator(id => id as never, 'configured-model', generate);
  expect(await generator.transform(input)).toBe('Complete rewrite');
});

it('rejects introduced em dashes but permits those already present in the selection', async () => {
  const generate = (() => ({ textStream: (async function* () { yield 'Clear — concise'; })(), finishReason: Promise.resolve('stop') })) as never;
  const generator = new TransformGenerator(() => 'test' as never, 'configured-model', generate);
  await expect(generator.transform(input)).rejects.toThrow('invalid_result');
  expect(await generator.transform({ ...input, text: 'Original — source' })).toBe('Clear — concise');
});
it('keeps selection boundary whitespace and does not add paragraph breaks to a single paragraph', async () => {
  const generate = (() => ({ textStream: (async function* () { yield '\n\nClear text.\n\nNext sentence.\n'; })(), finishReason: Promise.resolve('stop') })) as never;
  const generator = new TransformGenerator(() => 'test' as never, 'configured-model', generate);
  expect(await generator.transform({ ...input, text: ' Original paragraph. ' })).toBe(' Clear text. Next sentence. ');
});
it('does not introduce blank lines into a selection with ordinary line breaks', async () => {
  const generate = (() => ({ textStream: (async function* () { yield '\nFirst.\n\nSecond.\n'; })(), finishReason: Promise.resolve('stop') })) as never;
  const generator = new TransformGenerator(() => 'test' as never, 'configured-model', generate);
  expect(await generator.transform({ ...input, text: 'First line.\nSecond line.' })).toBe('First.\nSecond.');
});
