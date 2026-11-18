import { expect, test } from "vitest";
import { readFile, readdir } from "node:fs/promises";
import ts from "typescript";

test("keeps the API root rewrite while pinning functions near the database", async () => {
  const config = JSON.parse(
    await readFile(new URL("../vercel.json", import.meta.url), "utf8"),
  ) as Record<string, unknown>;

  expect(config).toMatchObject({
    buildCommand: "",
    installCommand: "bun install --frozen-lockfile",
    regions: ["sfo1"],
    rewrites: [{ source: "/(.*)", destination: "/api" }],
  });
});

test("exposes the health route through Vercel's GET function", async () => {
  process.env.AI_GATEWAY_API_KEY = "gateway-test";
  process.env.AI_DIAGNOSTICS = "off";
  process.env.CLERK_SECRET_KEY = "clerk-secret-test";
  process.env.CLERK_PUBLISHABLE_KEY = "clerk-publishable-test";

  const deployment = (await import("../api/index")) as Record<string, unknown>;
  expect(deployment.default).toBeUndefined();
  expect(deployment.GET).toBeTypeOf("function");
  expect(deployment.PUT).toBeUndefined();

  const response = await (
    deployment.GET as (request: Request) => Promise<Response>
  )(new Request("https://autocompletion.example/health"));

  expect(response.status).toBe(200);
  await expect(response.json()).resolves.toEqual({ status: "ok" });
});

// Vercel compiles relative TS imports but leaves bare workspace packages external.
// This workspace exports source TS; Node cannot resolve its emitted .js siblings.
test("keeps source-only workspace dependencies in Vercel's compilation graph", async () => {
  const unresolved: string[] = [];
  for (const directory of ["../src/", "../api/"]) {
    const root = new URL(directory, import.meta.url);
    for (const file of await readdir(root, { recursive: true })) {
      if (!file.endsWith(".ts")) continue;
      const source = await readFile(new URL(file, root), "utf8");
      const emitted = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } }).outputText;
      for (const imported of ts.preProcessFile(emitted).importedFiles) {
        if (imported.fileName.startsWith("@autocompletion/")) unresolved.push(`${directory}${file}: ${imported.fileName}`);
      }
    }
  }
  expect(unresolved).toEqual([]);
});
