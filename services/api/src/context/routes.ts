import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { z } from "zod";
import type { ContextLeasePool } from "./leases.js";
import type { AuthenticateRequest } from "../app.js";
export const VisualInputSchema = z
  .object({
    imageBase64: z
      .string()
      .min(4)
      .max(2_800_000)
      .regex(
        /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/,
      ),
    mimeType: z.enum(["image/png", "image/jpeg", "image/webp"]),
  })
  .strict();
export type VisualInput = z.infer<typeof VisualInputSchema>;
export const EmbeddingInputSchema = z
  .object({ text: z.string().min(1).max(16000) })
  .strict();
export function createContextApp(deps: {
  authenticate: AuthenticateRequest;
  leases: ContextLeasePool;
  visual: (
    input: VisualInput,
    signal: AbortSignal,
  ) => Promise<{ text: string }>;
  embed: (
    text: string,
    signal: AbortSignal,
  ) => Promise<{ embedding: number[] }>;
}) {
  const app = new Hono();
  app.use("*", async (c, next) => {
    c.header("cache-control", "no-store");
    await next();
  });
  app.use(
    "*",
    bodyLimit({
      maxSize: 2_810_000,
      onError: (c) => c.json({ error: "invalid_request" }, 413),
    }),
  );
  for (const operation of ["visual", "embeddings"] as const)
    app.post(`/v1/context/${operation}`, async (c) => {
      let user;
      try {
        user = await deps.authenticate(c.req.raw);
      } catch {
        return c.json({ error: "auth_unavailable" }, 503);
      }
      if (!user) return c.json({ error: "unauthorized" }, 401);
      const parsed = (
        operation === "visual" ? VisualInputSchema : EmbeddingInputSchema
      ).safeParse(await c.req.json().catch(() => null));
      if (!parsed.success) return c.json({ error: "invalid_request" }, 400);
      let release;
      try {
        release = await deps.leases.acquire(user.userId);
      } catch {
        return c.json({ error: "context_unavailable" }, 503);
      }
      if (!release) {
        c.header("retry-after", "1");
        return c.json({ error: "context_busy" }, 429);
      }
      const signal = AbortSignal.any([
        c.req.raw.signal,
        AbortSignal.timeout(20_000),
      ]);
      try {
        signal.throwIfAborted();
        const result =
          operation === "visual"
            ? await deps.visual(parsed.data as VisualInput, signal)
            : await deps.embed((parsed.data as { text: string }).text, signal);
        signal.throwIfAborted();
        const valid =
          operation === "visual"
            ? z.object({ text: z.string().max(16000) }).safeParse(result)
            : z
                .object({ embedding: z.array(z.number().finite()).length(768) })
                .safeParse(result);
        if (!valid.success) return c.json({ error: "invalid_result" }, 502);
        return c.json(valid.data);
      } catch {
        return Response.json(
          {
            error: signal.aborted ? "context_cancelled" : "context_unavailable",
          },
          {
            status: signal.aborted ? 499 : 502,
            headers: { "cache-control": "no-store" },
          },
        );
      } finally {
        try {
          await release();
        } catch {
          /* A bounded database lease expires even when release fails. */
        }
      }
    });
  return app;
}
