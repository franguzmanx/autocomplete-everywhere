import { describe, expect, test } from "vitest";

import {
  hasCurrentOAuthSession,
  OAuthTokenProvider,
  type ProductDataStore,
  type StoredProductData,
} from "../src/main/oauth-token-provider";

class MemoryStore implements ProductDataStore {
  reads = 0;
  writes: StoredProductData[] = [];
  readError: Error | null = null;
  readGate: Promise<void> | null = null;

  constructor(public value: StoredProductData | null) {}

  async read(): Promise<StoredProductData | null> {
    this.reads += 1;
    await this.readGate;
    if (this.readError) {
      const error = this.readError;
      this.readError = null;
      throw error;
    }
    return this.value;
  }

  async write(value: StoredProductData): Promise<void> {
    this.value = value;
    this.writes.push(value);
  }
}

describe("OAuthTokenProvider", () => {
  test("accepts only tokens issued for the current desktop OAuth client", () => {
    const tokens = {
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: 60_000,
      tokenType: "Bearer",
    };

    expect(
      hasCurrentOAuthSession(
        { oauthClientId: "current-client", tokens },
        "current-client",
      ),
    ).toBe(true);
    expect(
      hasCurrentOAuthSession(
        { oauthClientId: "old-client", tokens },
        "current-client",
      ),
    ).toBe(false);
    expect(
      hasCurrentOAuthSession({ tokens }, "current-client"),
    ).toBe(false);
  });

  test("rejects a token stored by a different OAuth client before any request", async () => {
    const store = new MemoryStore({
      oauthClientId: "old-client",
      tokens: {
        accessToken: "fresh-access",
        refreshToken: "refresh",
        expiresAt: 60_000,
        tokenType: "Bearer",
      },
    });
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "current-client",
      now: () => 1_000,
      request: async () => {
        throw new Error("unexpected request");
      },
    });

    await expect(provider.getAccessToken()).rejects.toThrow("unauthorized");
  });

  test("reuses a fresh access token after reading the encrypted store once", async () => {
    const store = new MemoryStore({
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "fresh-access",
        refreshToken: "refresh",
        expiresAt: 60_000,
        tokenType: "Bearer",
      },
    });
    let requests = 0;
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 1_000,
      request: async () => {
        requests += 1;
        throw new Error("unexpected request");
      },
    });

    await expect(provider.getAccessToken()).resolves.toBe("fresh-access");
    await expect(provider.getAccessToken()).resolves.toBe("fresh-access");
    expect(store.reads).toBe(1);
    expect(requests).toBe(0);
  });

  test("shares the initial encrypted-store read across concurrent callers", async () => {
    let releaseRead: (() => void) | undefined;
    const store = new MemoryStore({
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "fresh-access",
        refreshToken: "refresh",
        expiresAt: 60_000,
        tokenType: "Bearer",
      },
    });
    store.readGate = new Promise<void>((resolve) => {
      releaseRead = resolve;
    });
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 1_000,
      request: async () => {
        throw new Error("unexpected request");
      },
    });

    const first = provider.getAccessToken();
    const second = provider.getAccessToken();
    await Promise.resolve();
    expect(store.reads).toBe(1);
    releaseRead?.();

    await expect(Promise.all([first, second])).resolves.toEqual([
      "fresh-access",
      "fresh-access",
    ]);
    expect(store.reads).toBe(1);
  });

  test("refreshes an expiring token once, merges current product data, and reuses the renewed token", async () => {
    const store = new MemoryStore({
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "expiring-access",
        refreshToken: "old-refresh",
        expiresAt: 20_000,
        tokenType: "Bearer",
      },
      enabled: true,
    });
    let requests = 0;
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 10_000,
      refreshSkewMs: 15_000,
      request: async () => {
        requests += 1;
        await new Promise((resolve) => setTimeout(resolve, 0));
        store.value = {
          ...store.value,
          enabled: false,
        };
        return new Response(
          JSON.stringify({
            access_token: "renewed-access",
            refresh_token: "rotated-refresh",
            expires_in: 300,
            token_type: "Bearer",
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    });

    await expect(
      Promise.all([provider.getAccessToken(), provider.getAccessToken()]),
    ).resolves.toEqual(["renewed-access", "renewed-access"]);
    await expect(provider.getAccessToken()).resolves.toBe("renewed-access");
    expect(requests).toBe(1);
    expect(store.reads).toBe(2);
    expect(store.writes).toHaveLength(1);
    expect(store.value).toMatchObject({
      tokens: {
        accessToken: "renewed-access",
        refreshToken: "rotated-refresh",
      },
      enabled: false,
    });
  });

  test("force refresh never returns the cached access token", async () => {
    const store = new MemoryStore({
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "cached-access",
        refreshToken: "refresh",
        expiresAt: 60_000,
        tokenType: "Bearer",
      },
    });
    let requests = 0;
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 1_000,
      request: async () => {
        requests += 1;
        return new Response(
          JSON.stringify({
            access_token: "renewed-access",
            refresh_token: "rotated-refresh",
            expires_in: 300,
            token_type: "Bearer",
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    });

    await expect(provider.getAccessToken()).resolves.toBe("cached-access");
    await expect(provider.getAccessToken(true)).resolves.toBe("renewed-access");
    expect(requests).toBe(1);
    expect(store.reads).toBe(2);
  });

  test("retries the encrypted-store read after a read failure", async () => {
    const store = new MemoryStore({
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "fresh-access",
        refreshToken: "refresh",
        expiresAt: 60_000,
        tokenType: "Bearer",
      },
    });
    store.readError = new Error("encrypted store unavailable");
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 1_000,
    });

    await expect(provider.getAccessToken()).rejects.toThrow(
      "encrypted store unavailable",
    );
    await expect(provider.getAccessToken()).resolves.toBe("fresh-access");
    expect(store.reads).toBe(2);
  });

  test("does not cache tokens from a different OAuth client session", async () => {
    const store = new MemoryStore({
      oauthClientId: "old-client",
      tokens: {
        accessToken: "old-access",
        refreshToken: "old-refresh",
        expiresAt: 60_000,
        tokenType: "Bearer",
      },
    });
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 1_000,
    });

    await expect(provider.getAccessToken()).rejects.toThrow("unauthorized");
    store.value = {
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "current-access",
        refreshToken: "current-refresh",
        expiresAt: 60_000,
        tokenType: "Bearer",
      },
    };

    await expect(provider.getAccessToken()).resolves.toBe("current-access");
    expect(store.reads).toBe(2);
  });

  test("retries refresh after a failed token request instead of caching the failure", async () => {
    const store = new MemoryStore({
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "expiring-access",
        refreshToken: "refresh",
        expiresAt: 2_000,
        tokenType: "Bearer",
      },
    });
    let requests = 0;
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 1_000,
      refreshSkewMs: 1_500,
      request: async () => {
        requests += 1;
        if (requests === 1) return new Response(null, { status: 503 });
        return new Response(
          JSON.stringify({
            access_token: "renewed-access",
            expires_in: 300,
            token_type: "Bearer",
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    });

    await expect(provider.getAccessToken()).rejects.toThrow(
      "OAuth token refresh failed with status 503",
    );
    await expect(provider.getAccessToken()).resolves.toBe("renewed-access");
    expect(requests).toBe(2);
    expect(store.writes).toHaveLength(1);
  });

  test("does not overwrite or cache a refresh when the stored OAuth session changes", async () => {
    const store = new MemoryStore({
      oauthClientId: "desktop-client",
      tokens: {
        accessToken: "expiring-access",
        refreshToken: "old-refresh",
        expiresAt: 2_000,
        tokenType: "Bearer",
      },
    });
    const provider = new OAuthTokenProvider({
      store,
      tokenEndpoint: "https://accounts.example.test/oauth/token",
      clientId: "desktop-client",
      now: () => 1_000,
      refreshSkewMs: 1_500,
      request: async () => {
        store.value = {
          oauthClientId: "desktop-client",
          tokens: {
            accessToken: "new-session-access",
            refreshToken: "new-session-refresh",
            expiresAt: 60_000,
            tokenType: "Bearer",
          },
          enabled: false,
        };
        return new Response(
          JSON.stringify({
            access_token: "stale-renewed-access",
            refresh_token: "stale-rotated-refresh",
            expires_in: 300,
            token_type: "Bearer",
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    });

    await expect(provider.getAccessToken()).rejects.toThrow("unauthorized");
    expect(store.writes).toHaveLength(0);
    expect(store.value?.tokens?.accessToken).toBe("new-session-access");
    await expect(provider.getAccessToken()).resolves.toBe("new-session-access");
    expect(store.reads).toBe(3);
  });
});
