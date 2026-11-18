import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { TransformInputSchema, TransformOutputSchema, type TransformInput } from '../../../packages/protocol/src/transforms.js';
import type { AuthenticateRequest } from './app.js';

export type TransformGenerationInput = TransformInput & { userId: string; signal: AbortSignal };
export function createTransformApp(dependencies: {
  authenticate: AuthenticateRequest;
  generate(input: TransformGenerationInput): Promise<string>;
}): Hono {
  const app = new Hono();
  app.use('*', async (c, next) => { c.header('cache-control', 'no-store'); await next(); });
  app.use('*', bodyLimit({ maxSize: 128_000, onError: c => c.json({ error: 'invalid_request' }, 413) }));
  app.post('/v1/transforms', async c => {
    let user;
    try { user = await dependencies.authenticate(c.req.raw); }
    catch { return c.json({ error: 'auth_unavailable' }, 503); }
    if (!user) return c.json({ error: 'unauthorized' }, 401);
    const input = TransformInputSchema.safeParse(await c.req.json().catch(() => null));
    if (!input.success) return c.json({ error: 'invalid_request' }, 400);
    try {
      const signal = AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(15_000)]);
      const text = await dependencies.generate({ ...input.data, userId: user.userId, signal });
      const output = TransformOutputSchema.safeParse({ text });
      if (signal.aborted || !output.success || (input.data.singleLine && /[\r\n\u2028\u2029]/u.test(text))) {
        return c.json({ error: 'invalid_result' }, 502);
      }
      return c.json(output.data);
    } catch { return c.json({ error: 'transform_unavailable' }, 502); }
  });
  return app;
}
