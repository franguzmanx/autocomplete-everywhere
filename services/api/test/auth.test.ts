import { describe, expect, test } from "vitest";

import {
  createCachedAuthenticateRequest,
  readBearerToken,
} from "../src/auth";

describe("readBearerToken", () => {
  test("returns exactly one Bearer credential", () => {
    expect(
      readBearerToken(
        new Request("https://api.example.test", {
          headers: { authorization: "Bearer clerk-token" },
        }),
      ),
    ).toBe("clerk-token");
  });

  test("rejects missing, malformed, or ambiguous credentials", () => {
    for (const authorization of [
      undefined,
      "Basic value",
      "Bearer",
      "Bearer token extra",
      "Bearer   ",
    ]) {
      const headers = authorization ? { authorization } : undefined;
      expect(
        readBearerToken(
          new Request(
            "https://api.example.test",
            headers ? { headers } : undefined,
          ),
        ),
      ).toBeNull();
    }
  });
});

function requestWithBearer(token: string): Request {
  return new Request("https://api.example.test", {
    headers: { authorization: `Bearer ${token}` },
  });
}

function jwtWithExpiry(exp: number): string {
  const payload = Buffer.from(JSON.stringify({ exp })).toString("base64url");
  return `header.${payload}.signature`;
}

describe("createCachedAuthenticateRequest", () => {
  test("reuses a positive authentication by bearer token", async () => {
    let calls = 0;
    const authenticate = createCachedAuthenticateRequest(
      async () => {
        calls += 1;
        return { userId: "user_a" };
      },
      { now: () => 1_000 },
    );

    expect(await authenticate(requestWithBearer("opaque-token"))).toEqual({
      userId: "user_a",
      source: "origin",
    });
    expect(await authenticate(requestWithBearer("opaque-token"))).toEqual({
      userId: "user_a",
      source: "cache",
    });
    expect(calls).toBe(1);
  });

  test("deduplicates concurrent authentication of the same bearer", async () => {
    let calls = 0;
    let resolve!: (value: { userId: string }) => void;
    const pending = new Promise<{ userId: string }>((done) => {
      resolve = done;
    });
    const authenticate = createCachedAuthenticateRequest(
      async () => {
        calls += 1;
        return pending;
      },
      { now: () => 1_000 },
    );

    const first = authenticate(requestWithBearer("same-token"));
    const second = authenticate(requestWithBearer("same-token"));
    resolve({ userId: "user_a" });

    expect(await first).toEqual({ userId: "user_a", source: "origin" });
    expect(await second).toEqual({ userId: "user_a", source: "inflight" });
    expect(calls).toBe(1);
  });

  test("does not cache rejected or unavailable authentication", async () => {
    let calls = 0;
    const authenticate = createCachedAuthenticateRequest(
      async () => {
        calls += 1;
        if (calls === 1) return null;
        if (calls === 2) throw new Error("unavailable");
        return { userId: "user_a" };
      },
      { now: () => 1_000 },
    );

    expect(await authenticate(requestWithBearer("same-token"))).toBeNull();
    await expect(authenticate(requestWithBearer("same-token"))).rejects.toThrow(
      "unavailable",
    );
    expect(await authenticate(requestWithBearer("same-token"))).toEqual({
      userId: "user_a",
      source: "origin",
    });
    expect(calls).toBe(3);
  });

  test("expires entries at the earlier of the TTL and JWT expiry", async () => {
    let now = 1_000;
    let calls = 0;
    const token = jwtWithExpiry(3);
    const authenticate = createCachedAuthenticateRequest(
      async () => ({ userId: `user_${++calls}` }),
      { now: () => now, ttlMs: 60_000 },
    );

    expect(await authenticate(requestWithBearer(token))).toMatchObject({
      userId: "user_1",
      source: "origin",
    });
    now = 2_999;
    expect(await authenticate(requestWithBearer(token))).toMatchObject({
      userId: "user_1",
      source: "cache",
    });
    now = 3_000;
    expect(await authenticate(requestWithBearer(token))).toMatchObject({
      userId: "user_2",
      source: "origin",
    });
  });

  test("evicts the oldest positive entry when the cache is full", async () => {
    let calls = 0;
    const authenticate = createCachedAuthenticateRequest(
      async () => ({ userId: `user_${++calls}` }),
      { now: () => 1_000, maxEntries: 2 },
    );

    await authenticate(requestWithBearer("token-a"));
    await authenticate(requestWithBearer("token-b"));
    await authenticate(requestWithBearer("token-c"));
    expect(await authenticate(requestWithBearer("token-a"))).toMatchObject({
      userId: "user_4",
      source: "origin",
    });
  });
});
