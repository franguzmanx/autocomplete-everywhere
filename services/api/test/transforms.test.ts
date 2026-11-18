import { describe, expect, it } from 'vitest';
import { defaultTransformSettings } from '../../../packages/protocol/src/transforms';
import { createTransformApp } from '../src/transforms';

const input = { text: 'hola como estas', transform: defaultTransformSettings().transforms[0], singleLine: false };
const post = (app: ReturnType<typeof createTransformApp>, body: unknown = input) => app.request('/v1/transforms', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
describe('transform API', () => {
  it('authenticates before generation', async () => {
    const app = createTransformApp({ authenticate: async () => null, generate: async () => { throw new Error('must not call'); } });
    expect((await post(app)).status).toBe(401);
  });
  it('returns a complete rewrite without autocomplete truncation', async () => {
    const text = 'Rewritten paragraph. '.repeat(30);
    const app = createTransformApp({ authenticate: async () => ({ userId: 'u' }), generate: async () => text });
    const response = await post(app);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ text });
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
  it('rejects invalid input and unsafe or empty output', async () => {
    for (const text of ['', ' ', '\u0000bad', 'x'.repeat(8001)]) {
      const app = createTransformApp({ authenticate: async () => ({ userId: 'u' }), generate: async () => text });
      expect((await post(app)).status).toBe(502);
      expect((await post(app, { ...input, text: 'x'.repeat(2001) })).status).toBe(400);
    }
  });
  it('does not put multiple lines into a single-line field', async () => {
    const app = createTransformApp({ authenticate: async () => ({ userId: 'u' }), generate: async () => 'a\nb' });
    expect((await post(app, { ...input, singleLine: true })).status).toBe(502);
  });
  it('returns content-free failures when generation fails mid-response', async () => {
    const app = createTransformApp({ authenticate: async () => ({ userId: 'u' }), generate: async () => { throw new Error('private text'); } });
    const response = await post(app);
    expect(response.status).toBe(502);
    expect(await response.text()).not.toContain('private text');
  });
});
