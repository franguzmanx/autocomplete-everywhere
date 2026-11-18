import { describe, expect, test, vi } from "vitest";

import { LOCAL_API_ORIGIN, LocalAccount } from "../src/main/local-account";
import { ProductState } from "../src/main/state";

function setup(stored: unknown = null, verdict: "accepted" | "rejected" | "unverified" = "accepted") {
  let value = stored;
  const state = new ProductState();
  const invalidate = vi.fn();
  const account = new LocalAccount({
    store: { read: async <T>() => value as T | null, write: async next => { value = next; } },
    state,
    openExternal: async () => {},
    invalidate,
    changed: () => {},
    verify: async () => verdict,
  });
  return { account, state, invalidate, stored: () => value };
}

describe("local account", () => {
  test("asks for a key and refuses requests until one is saved", async () => {
    const { account, state } = setup();
    expect(state.snapshot().account).toEqual({ state: "signed_out", identity: null, kind: "api_key" });
    await account.initialize();
    expect(state.snapshot().account.state).toBe("signed_out");
    await expect(account.tokenProvider.getAccessToken()).rejects.toThrow("unauthorized");
    expect((await account.request(`${LOCAL_API_ORIGIN}/health`)).status).toBe(401);
  });

  test("keeps a rejected or malformed key out of storage", async () => {
    const rejected = setup(null, "rejected");
    await expect(rejected.account.setApiKey("vck_rejected_key")).rejects.toThrow(/rejected/);
    expect(rejected.stored()).toBeNull();
    const malformed = setup();
    await expect(malformed.account.setApiKey("has spaces inside")).rejects.toThrow(/does not look like/);
    expect(malformed.stored()).toBeNull();
  });

  test("serves the API in process once a key is saved", async () => {
    const { account, state, invalidate, stored } = setup(null, "unverified");
    await account.setApiKey("  vck_example_key  ");
    expect(stored()).toEqual({ gatewayApiKey: "vck_example_key" });
    expect(invalidate).toHaveBeenCalledOnce();
    expect(state.snapshot().account).toEqual({
      state: "signed_in",
      identity: { subject: "local", name: "", email: "" },
      kind: "api_key",
    });
    const token = await account.tokenProvider.getAccessToken();
    expect((await account.request(`${LOCAL_API_ORIGIN}/health`)).status).toBe(200);
    // An authenticated route accepts the local user and then validates the body.
    const response = await account.request(`${LOCAL_API_ORIGIN}/v1/suggestions`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: "{}",
    });
    expect(response.status).not.toBe(401);
    expect(response.status).toBeGreaterThanOrEqual(400);
  });

  test("restores a saved key and removes it on sign-out", async () => {
    const { account, state, stored } = setup({ gatewayApiKey: "vck_saved_key" });
    await account.initialize();
    expect(state.snapshot().account.state).toBe("signed_in");
    await account.signOut();
    expect(stored()).toEqual({});
    expect(state.snapshot().account).toEqual({ state: "signed_out", identity: null, kind: "api_key" });
    expect((await account.request(`${LOCAL_API_ORIGIN}/health`)).status).toBe(401);
  });
});
