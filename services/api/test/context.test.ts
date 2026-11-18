import { expect, it } from "vitest";
import { createContextApp } from "../src/context/routes.js";
function leases() {
  let active = 0;
  return {
    async acquire() {
      if (active >= 2) return null;
      active++;
      return async () => {
        active--;
      };
    },
  };
}
const auth = async () => ({ userId: "u" });
it("authenticates and validates before invoking models", async () => {
  let calls = 0;
  const app = createContextApp({
    leases: leases(),
    authenticate: async () => null,
    visual: async () => {
      calls++;
      return { text: "x" };
    },
    embed: async () => ({ embedding: Array(768).fill(0) }),
  });
  expect(
    (await app.request("/v1/context/visual", { method: "POST", body: "{}" }))
      .status,
  ).toBe(401);
  expect(calls).toBe(0);
});
it("shares two slots across visual and embedding and releases on completion", async () => {
  const releases: (() => void)[] = [];
  const wait = () => new Promise<void>((resolve) => releases.push(resolve));
  const app = createContextApp({
    leases: leases(),
    authenticate: auth,
    visual: async () => {
      await wait();
      return { text: "x" };
    },
    embed: async () => {
      await wait();
      return { embedding: Array(768).fill(0) };
    },
  });
  const request = () =>
    app.request("/v1/context/embeddings", {
      method: "POST",
      body: JSON.stringify({ text: "x" }),
    });
  const first = request(),
    second = request();
  await new Promise((resolve) => setTimeout(resolve, 10));
  expect((await request()).status).toBe(429);
  releases.splice(0).forEach((r) => r());
  expect((await first).status).toBe(200);
  expect((await second).status).toBe(200);
  const third = request();
  await new Promise((resolve) => setTimeout(resolve, 10));
  releases.splice(0).forEach((r) => r());
  expect((await third).status).toBe(200);
});
it("releases the account lease on provider errors", async () => {
  let releases = 0;
  const app = createContextApp({
    authenticate: auth,
    leases: {
      async acquire() {
        return async () => {
          releases++;
        };
      },
    },
    visual: async () => {
      throw new Error("provider");
    },
    embed: async () => {
      throw new Error("provider");
    },
  });
  const response = await app.request("/v1/context/embeddings", {
    method: "POST",
    body: JSON.stringify({ text: "x" }),
  });
  expect(response.status).toBe(502);
  expect(releases).toBe(1);
});
it("shares both account slots with preference learning and releases after it fails", async () => {
  const { createApp } = await import("../src/app.js");
  const pool = leases();
  let finish!: () => void;
  const app = createApp({
    authenticate: auth,
    backgroundLeases: pool,
    generator: { complete: async () => undefined },
    preferenceExtractor: {
      extract: async () => {
        await new Promise<void>((resolve) => {
          finish = resolve;
        });
        throw new Error("provider failure");
      },
    },
  });
  app.route(
    "/",
    createContextApp({
      authenticate: auth,
      leases: pool,
      visual: async () => ({ text: "x" }),
      embed: async () => ({ embedding: Array(768).fill(0) }),
    }),
  );
  const release = await pool.acquire();
  const request = {
    observations: [
      {
        id: "00000000-0000-4000-8000-000000000001",
        sessionId: "00000000-0000-4000-8000-000000000002",
        appId: "app",
        before: "before",
        after: "after",
      },
    ],
  };
  const learning = app.request("/v1/preferences/extract", {
    method: "POST",
    body: JSON.stringify(request),
  });
  await new Promise((resolve) => setTimeout(resolve, 0));
  const third = await app.request("/v1/context/embeddings", {
    method: "POST",
    body: JSON.stringify({ text: "x" }),
  });
  expect(third.status).toBe(429);
  finish();
  expect((await learning).status).toBe(502);
  expect(
    (
      await app.request("/v1/context/embeddings", {
        method: "POST",
        body: JSON.stringify({ text: "x" }),
      })
    ).status,
  ).toBe(200);
  await release!();
});
