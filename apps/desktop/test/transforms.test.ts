import { expect, it } from 'vitest';
import { defaultTransformSettings, PROTOCOL_VERSION, type ProtocolMessage } from '@autocompletion/protocol';
import { TransformCoordinator } from '../src/main/transforms';
const settings = defaultTransformSettings(); settings.enabled = true;
const request: ProtocolMessage = { protocolVersion: PROTOCOL_VERSION, type: 'transform_request', identity: { requestId: 'c611fc31-91e3-4172-a74d-2c90e359c004', focusSequence: 1, contentSignature: 'a'.repeat(64), timestampMs: 1 }, payload: { appId:'test.editor', transformId: settings.transforms[0]!.id, text: 'hello', singleLine: false } };
it('drops a late result after cancellation even when the source ignores abort', async () => {
  let finish!: (text: string) => void;
  const sent: ProtocolMessage[] = [];
  const coordinator = new TransformCoordinator({ getSettings: () => settings, transform: () => new Promise(resolve => { finish = resolve; }), send: m => sent.push(m) });
  const pending = coordinator.handle(request);
  await coordinator.handle({ protocolVersion: PROTOCOL_VERSION, type: 'cancel_request', identity: request.identity, payload: { reason: 'focus_changed' } });
  finish('changed'); await pending;
  expect(sent).toEqual([]);
});
it('passes the chosen rules and returns a complete result', async () => {
  const sent: ProtocolMessage[] = [];
  const coordinator = new TransformCoordinator({ getSettings: () => settings, transform: async input => { expect(input.transform).toEqual(settings.transforms[0]); return 'Hello!'; }, send: m => sent.push(m) });
  await coordinator.handle(request);
  expect(sent[0]).toEqual({ protocolVersion: PROTOCOL_VERSION, type: 'transform_result', identity: request.identity, payload: { text: 'Hello!' } });
});
it('does not call the model for disabled transforms or an unknown shortcut', async () => {
  const sent: ProtocolMessage[] = [];
  const coordinator = new TransformCoordinator({ getSettings: () => ({ ...settings, enabled: false }), transform: async () => { throw new Error('must not call'); }, send: m => sent.push(m) });
  await coordinator.handle(request);
  expect(sent[0]?.type).toBe('transform_result');
  expect(sent[0]).toHaveProperty('payload.error', 'unavailable');
});
