import { describe, expect, test } from "vitest";

import {
  buildAuthorizationUrl,
  createPkcePair,
  exchangeAuthorizationCode,
  exchangeRefreshToken,
  parseAuthorizationCallback,
} from "../src/main/auth";

describe("desktop OAuth PKCE", () => {
  test("creates an RFC 7636 verifier and S256 challenge", () => {
    const pair = createPkcePair(Buffer.alloc(32, 7));

    expect(pair.verifier).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(pair.challenge).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(pair.challenge).not.toBe(pair.verifier);
  });

  test("builds a public-client authorization request without a secret", () => {
    const url = buildAuthorizationUrl({
      authorizationEndpoint: "https://accounts.example.test/oauth/authorize",
      clientId: "desktop-client",
      redirectUri: "http://127.0.0.1:43119/callback",
      state: "state-value",
      challenge: "challenge-value",
      scopes: ["openid", "profile", "offline_access"],
    });

    expect(url.searchParams.get("response_type")).toBe("code");
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    expect(url.searchParams.get("client_secret")).toBeNull();
  });

  test("accepts only the exact loopback callback and matching state", () => {
    expect(
      parseAuthorizationCallback(
        "http://127.0.0.1:43119/callback?code=one-time&state=expected",
        "http://127.0.0.1:43119/callback",
        "expected",
      ),
    ).toEqual({ code: "one-time" });

    expect(() =>
      parseAuthorizationCallback(
        "http://127.0.0.1:43119/callback?code=one-time&state=wrong",
        "http://127.0.0.1:43119/callback",
        "expected",
      ),
    ).toThrow("OAuth state mismatch");

    expect(() =>
      parseAuthorizationCallback(
        "http://attacker.example/callback?code=one-time&state=expected",
        "http://127.0.0.1:43119/callback",
        "expected",
      ),
    ).toThrow("OAuth callback URL mismatch");
  });

  test("exchanges the code as a public client and requires refresh credentials", async () => {
    let submitted = "";
    const tokens = await exchangeAuthorizationCode(
      {
        tokenEndpoint: "https://accounts.example.test/oauth/token",
        clientId: "desktop-client",
        redirectUri: "http://127.0.0.1:43119/callback",
        code: "one-time",
        verifier: "verifier-value",
      },
      async (_url, init) => {
        submitted = String(init?.body);
        return new Response(
          JSON.stringify({
            access_token: "short-lived",
            refresh_token: "long-lived",
            expires_in: 300,
            token_type: "Bearer",
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    );

    expect(tokens.refreshToken).toBe("long-lived");
    expect(submitted).toContain("code_verifier=verifier-value");
    expect(submitted).not.toContain("client_secret");
  });

  test("refreshes a public-client session and preserves an unrotated refresh token", async () => {
    let submitted = "";
    const tokens = await exchangeRefreshToken(
      {
        tokenEndpoint: "https://accounts.example.test/oauth/token",
        clientId: "desktop-client",
        refreshToken: "existing-refresh",
      },
      async (_url, init) => {
        submitted = String(init?.body);
        return new Response(
          JSON.stringify({
            access_token: "renewed-access",
            expires_in: 300,
            token_type: "Bearer",
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    );

    expect(tokens.accessToken).toBe("renewed-access");
    expect(tokens.refreshToken).toBe("existing-refresh");
    expect(submitted).toContain("grant_type=refresh_token");
    expect(submitted).toContain("refresh_token=existing-refresh");
    expect(submitted).not.toContain("client_secret");
  });
});
