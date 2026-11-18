import { expect, it } from "vitest";
import {
  connectorResourceUrl,
  createConnectorApp,
} from "../src/context/connectors.js";
it("constructs only provider GET endpoints and rejects traversal and SSRF", () => {
  expect(connectorResourceUrl("github", "owner/repo/issues/3")).toBe(
    "https://api.github.com/repos/owner/repo/issues/3",
  );
  for (const value of [
    "https://127.0.0.1",
    "owner/../issues/3",
    "owner/repo/issues/3?x=1",
    "owner/repo/actions",
  ])
    expect(() => connectorResourceUrl("github", value)).toThrow();
  expect(connectorResourceUrl("figma", "abc123")).toBe(
    "https://api.figma.com/v1/files/abc123?depth=2",
  );
});
it("honestly reports OAuth configuration unavailable", async () => {
  const app = createConnectorApp({
    authenticate: async () => ({ userId: "u" }),
    environment: {},
  });
  const response = await app.request("/v1/context/connectors/github/start", {
    method: "POST",
    body: JSON.stringify({ codeChallenge: "a".repeat(43) }),
  });
  expect(response.status).toBe(503);
});
it("binds authorization exchanges to account and PKCE verifier without invoking the provider", async () => {
  const { createHash } = await import("node:crypto");
  const verifier = "v".repeat(43),
    challenge = createHash("sha256").update(verifier).digest("base64url");
  let account = "first",
    calls = 0;
  const app = createConnectorApp({
    authenticate: async () => ({ userId: account }),
    environment: {
      GITHUB_CONTEXT_CLIENT_ID: "id",
      GITHUB_CONTEXT_CLIENT_SECRET: "secret",
      GITHUB_CONTEXT_REDIRECT_URI: "http://127.0.0.1:43120/context/callback",
      CONTEXT_OAUTH_STATE_SECRET: "s".repeat(32),
    },
    fetch: (async () => {
      calls++;
      throw new Error();
    }) as never,
  });
  const started = await (
    await app.request("/v1/context/connectors/github/start", {
      method: "POST",
      body: JSON.stringify({ codeChallenge: challenge }),
    })
  ).json();
  expect(
    new URL(started.authorizationUrl).searchParams.get("scope"),
  ).toBeNull();
  account = "second";
  const response = await app.request("/v1/context/connectors/github/exchange", {
    method: "POST",
    body: JSON.stringify({
      code: "code",
      state: started.state,
      codeVerifier: verifier,
    }),
  });
  expect(response.status).toBe(400);
  expect(calls).toBe(0);
});
it("preserves provider retry-after and disables redirects", async () => {
  const app = createConnectorApp({
    authenticate: async () => ({ userId: "u" }),
    environment: {},
    fetch: (async (_url: unknown, options: RequestInit) => {
      expect(options.redirect).toBe("error");
      expect(options.method).toBeUndefined();
      return new Response("", {
        status: 429,
        headers: { "retry-after": "90" },
      });
    }) as never,
  });
  const response = await app.request("/v1/context/connectors/figma/read", {
    method: "POST",
    body: JSON.stringify({ accessToken: "secret", resourceId: "abc" }),
  });
  expect(response.status).toBe(429);
  expect(response.headers.get("retry-after")).toBe("90");
});
it("retrieves bounded PR files, reviews and checks from fixed hosts", async () => {
  const urls: string[] = [];
  const app = createConnectorApp({
    authenticate: async () => ({ userId: "u" }),
    environment: {},
    fetch: (async (url: string) => {
      urls.push(url);
      const data = url.includes("/files?")
        ? [{ filename: "a.ts", patch: "+ change" }]
        : url.includes("/reviews?")
          ? [{ state: "APPROVED", body: "Reviewed" }]
          : url.includes("/check-runs?")
            ? { check_runs: [{ name: "CI", conclusion: "success" }] }
            : { title: "Change", head: { sha: "a".repeat(40) } };
      return Response.json(data);
    }) as never,
  });
  const response = await app.request("/v1/context/connectors/github/read", {
    method: "POST",
    body: JSON.stringify({
      accessToken: "secret",
      resourceId: "owner/repo/pulls/3",
    }),
  });
  expect(response.status).toBe(200);
  const data = await response.json();
  expect(data.text).toContain("APPROVED");
  expect(data.text).toContain("success");
  expect(data.text).toContain("a.ts");
  expect(urls).toHaveLength(4);
});
it("supports specific Figma nodes and comments and safe repository content paths", async () => {
  expect(connectorResourceUrl("figma", "abc/nodes/12:34")).toContain(
    "/nodes?ids=12%3A34",
  );
  expect(
    connectorResourceUrl("github", "owner/repo/contents/docs/file.md?ref=main"),
  ).toBe(
    "https://api.github.com/repos/owner/repo/contents/docs/file.md?ref=main",
  );
  expect(() =>
    connectorResourceUrl("github", "owner/repo/contents/../secret"),
  ).toThrow();
  const app = createConnectorApp({
    authenticate: async () => ({ userId: "u" }),
    environment: {},
    fetch: (async (url: string) =>
      Response.json(
        url.endsWith("/comments")
          ? { comments: [{ message: "Observed feedback" }] }
          : { nodes: { "12:34": { document: { name: "Screen" } } } },
      )) as never,
  });
  const response = await app.request("/v1/context/connectors/figma/read", {
    method: "POST",
    body: JSON.stringify({
      accessToken: "secret",
      resourceId: "abc/nodes/12:34",
    }),
  });
  expect(response.status).toBe(200);
  expect((await response.json()).text).toContain("Observed feedback");
});
