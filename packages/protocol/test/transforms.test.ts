import { describe, expect, it } from 'vitest';
import { TransformSettingsSchema, defaultTransformSettings, TransformInputSchema } from '../src/transforms';

describe('transforms', () => {
  it('has three usable presets and rejects conflicting shortcuts', () => {
    const settings = defaultTransformSettings();
    expect(TransformSettingsSchema.safeParse(settings).success).toBe(true);
    settings.transforms[1]!.shortcut = settings.transforms[0]!.shortcut;
    expect(TransformSettingsSchema.safeParse(settings).success).toBe(false);
  });
  it('rejects empty and oversized selections without truncating', () => {
    const transform = defaultTransformSettings().transforms[0]!;
    for (const text of ['', '   ', 'a'.repeat(2001)]) {
      expect(TransformInputSchema.safeParse({ text, transform, singleLine: false }).success).toBe(false);
    }
    expect(TransformInputSchema.safeParse({ text: 'Hola 👋', transform, singleLine: false }).success).toBe(true);
  });
  it('bounds instructions and examples and requires a usable rule or prompt', () => {
    const settings = defaultTransformSettings();
    const transform = settings.transforms[0]!;
    transform.examples = ['a'.repeat(4001)];
    expect(TransformSettingsSchema.safeParse(settings).success).toBe(false);
    transform.examples = [];
    transform.rules = [];
    transform.prompt = ' ';
    expect(TransformSettingsSchema.safeParse(settings).success).toBe(false);
  });
});

import { parseProtocolMessage, PROTOCOL_VERSION } from '../src/messages';
it('validates transform requests and complete results across the helper boundary', () => {
  const identity = { requestId: 'c611fc31-91e3-4172-a74d-2c90e359c001', focusSequence: 1, contentSignature: 'a'.repeat(64), timestampMs: 1 };
  const request = { protocolVersion: PROTOCOL_VERSION, type: 'transform_request', identity, payload: { appId:'test.editor', transformId: identity.requestId, text: 'hello', singleLine: false } };
  expect(parseProtocolMessage(request)).toEqual(request);
  expect(parseProtocolMessage({ ...request, payload: { ...request.payload, text: 'x'.repeat(2001) } })).toEqual({ ok: false, code: 'invalid_message' });
});
