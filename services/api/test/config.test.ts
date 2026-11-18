import { describe, expect, test } from "vitest";

import { parseApiEnvironment } from "../src/config";

const completeEnvironment = {
  AI_DIAGNOSTICS: "full",
  CLERK_SECRET_KEY: "clerk-secret-test",
  CLERK_PUBLISHABLE_KEY: "clerk-publishable-test",
};

describe("API environment", () => {
  test("does not require a provider key when AI Gateway uses Vercel OIDC", () => {
    expect(
      parseApiEnvironment({
        ...completeEnvironment,
        AI_TRANSPORT: "gateway",
        AI_GATEWAY_API_KEY: "obsolete-gateway-key",
        AI_GATEWAY_LINE_MODEL: "obsolete-line-model",
      }),
    ).toEqual({
      aiDiagnostics: "full",
      clerkSecretKey: "clerk-secret-test",
      clerkPublishableKey: "clerk-publishable-test",
    });
  });

  test("requires every server-only credential", () => {
    expect(() => parseApiEnvironment({})).toThrow(
      "API environment is incomplete",
    );
    expect(() =>
      parseApiEnvironment({ ...completeEnvironment, CLERK_SECRET_KEY: "" }),
    ).toThrow("API environment is incomplete");
  });

  test("rejects an unknown diagnostics mode", () => {
    expect(() =>
      parseApiEnvironment({ ...completeEnvironment, AI_DIAGNOSTICS: "sometimes" }),
    ).toThrow("API environment is incomplete");
  });
});
