/** Direct synthetic provider readiness. No deployment, database writes or private content. */
import { gateway } from "@ai-sdk/gateway";
import { ContextModels } from "../src/context/models.js";
import { createAuthenticatedPostgresRunner } from "../../../packages/database/src/postgres-client.js";
import type { BackgroundMetric } from "../src/context/telemetry.js";
const redacted = (value: string | undefined) =>
  /^\[(?:SENSITIVE|REDACTED[^\]]*)\]$/.test(value ?? "");
const databaseRedacted = redacted(process.env.DATABASE_URL);
if (redacted(process.env.AI_GATEWAY_API_KEY))
  delete process.env.AI_GATEWAY_API_KEY;
const metrics: BackgroundMetric[] = [];
const models = new ContextModels(gateway, (event) => metrics.push(event));
const syntheticPng =
  "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAb0lEQVR4nO3PAQkAAAyEwO9feoshgnABdLep8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3IPanc8OLDQitxAAAAAElFTkSuQmCC";
const probe = async (operation: "visual" | "embedding") => {
  const start = Date.now();
  try {
    const signal = AbortSignal.timeout(25000);
    const result =
      operation === "visual"
        ? await models.visual(
            { imageBase64: syntheticPng, mimeType: "image/png" },
            signal,
          )
        : await models.embedding(
            "Synthetic Autocomplete Everywhere capability probe. The blue square is beside the red circle.",
            signal,
          );
    return {
      operation,
      verified:
        "embedding" in result
          ? result.embedding.length === 768
          : result.text.trim().length > 0,
      durationMs: Date.now() - start,
      ...("embedding" in result
        ? { dimensions: result.embedding.length }
        : { nonempty: result.text.trim().length > 0 }),
    };
  } catch (error) {
    const status =
      error &&
      typeof error === "object" &&
      "statusCode" in error &&
      typeof error.statusCode === "number"
        ? error.statusCode
        : undefined;
    return {
      operation,
      verified: false,
      durationMs: Date.now() - start,
      ...(status ? { httpStatus: status } : {}),
    };
  }
};
if (!process.env.AI_GATEWAY_API_KEY && !process.env.VERCEL_OIDC_TOKEN) {
  console.info(
    JSON.stringify({ verified: false, status: "gateway_credentials_required" }),
  );
  process.exit(2);
}
const results = await Promise.all([probe("visual"), probe("embedding")]);
let database: Record<string, unknown> = {
  configured: !!process.env.DATABASE_URL,
};
if (databaseRedacted)
  database = { configured: true, credentialsAccessible: false };
else if (process.env.DATABASE_URL) {
  try {
    const runner = createAuthenticatedPostgresRunner(process.env.DATABASE_URL);
    const state = await runner.run("synthetic-readiness", async (sql) => {
      const rows =
        await sql`select to_regclass('public.context_background_leases') is not null as lease_table, to_regprocedure('public.acquire_context_background_lease(uuid)') is not null as lease_function`;
      return rows[0];
    });
    database = {
      configured: true,
      reachable: true,
      leaseTable: state?.lease_table === true,
      leaseFunction: state?.lease_function === true,
    };
  } catch {
    database = { configured: true, reachable: false };
  }
}
console.info(
  JSON.stringify({
    verified: results.every((result) => result.verified),
    capturedAtMs: Date.now(),
    results,
    metrics,
    database,
  }),
);
process.exit(results.every((result) => result.verified) ? 0 : 1);
