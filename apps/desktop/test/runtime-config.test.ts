import { describe, expect, test } from "vitest";

import {
  MissingRuntimeConfigError,
  resolveBackend,
  resolveDesktopRuntimeConfig,
} from "../src/main/runtime-config";

const backend = {
  AUTOCOMPLETION_API_URL: "https://api.example.test",
  AUTOCOMPLETION_CLERK_AUTHORIZATION_URL: "https://identity.example.test/authorize",
  AUTOCOMPLETION_CLERK_TOKEN_URL: "https://identity.example.test/token",
  AUTOCOMPLETION_CLERK_CLIENT_ID: "local-client",
  AUTOCOMPLETION_CLERK_USERINFO_URL: "https://identity.example.test/userinfo",
  AUTOCOMPLETION_CLERK_REVOCATION_URL: "https://identity.example.test/revoke",
  AUTOCOMPLETION_ACCOUNT_URL: "https://accounts.example.test/user",
};

describe("desktop runtime configuration", () => {
  test("ships without a hosted backend and names every missing variable", () => {
    expect(() => resolveDesktopRuntimeConfig({})).toThrow(MissingRuntimeConfigError);
    try {
      resolveDesktopRuntimeConfig({ AUTOCOMPLETION_API_URL: "https://api.example.test" });
      throw new Error("expected a missing configuration error");
    } catch (error) {
      expect((error as MissingRuntimeConfigError).missing).toEqual([
        "AUTOCOMPLETION_CLERK_AUTHORIZATION_URL",
        "AUTOCOMPLETION_CLERK_TOKEN_URL",
        "AUTOCOMPLETION_CLERK_CLIENT_ID",
        "AUTOCOMPLETION_CLERK_USERINFO_URL",
        "AUTOCOMPLETION_CLERK_REVOCATION_URL",
        "AUTOCOMPLETION_ACCOUNT_URL",
      ]);
    }
  });

  test("resolves a self-hosted backend from the environment", () => {
    expect(resolveDesktopRuntimeConfig(backend)).toEqual({
      apiUrl: "https://api.example.test",
      authorizationEndpoint: "https://identity.example.test/authorize",
      tokenEndpoint: "https://identity.example.test/token",
      clientId: "local-client",
      redirectUri: "http://127.0.0.1:43119/callback",
      userinfoEndpoint: "https://identity.example.test/userinfo",
      revocationEndpoint: "https://identity.example.test/revoke",
      manageAccountUrl: "https://accounts.example.test/user",
    });
  });

  test("uses build-time values and lets the runtime environment override them", () => {
    const config = resolveDesktopRuntimeConfig(
      {
        AUTOCOMPLETION_API_URL: "https://override.example.test",
        AUTOCOMPLETION_CLERK_REDIRECT_URI: "http://127.0.0.1:54321/callback",
      },
      backend,
    );
    expect(config.apiUrl).toBe("https://override.example.test");
    expect(config.clientId).toBe("local-client");
    expect(config.redirectUri).toBe("http://127.0.0.1:54321/callback");
  });

  test("runs locally when no hosted backend is configured", () => {
    expect(resolveBackend({})).toEqual({ mode: "local" });
    expect(resolveBackend({ AUTOCOMPLETION_CLERK_REDIRECT_URI: "http://127.0.0.1:54321/callback" })).toEqual({ mode: "local" });
  });

  test("selects the hosted backend from runtime or build-time values", () => {
    expect(resolveBackend(backend)).toMatchObject({ mode: "hosted", config: { apiUrl: "https://api.example.test" } });
    expect(resolveBackend({}, backend)).toMatchObject({ mode: "hosted", config: { clientId: "local-client" } });
  });

  test("rejects a partial hosted configuration instead of falling back to local", () => {
    expect(() => resolveBackend({ AUTOCOMPLETION_API_URL: "https://api.example.test" })).toThrow(MissingRuntimeConfigError);
  });
});
