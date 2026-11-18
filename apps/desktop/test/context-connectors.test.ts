import { expect, it, vi } from "vitest";
import {
  ContextConnectors,
  observedResources,
} from "../src/main/context-connectors";
it("extracts explicit resources without credentials or misleading hosts", () => {
  expect(
    observedResources(
      "https://github.com.evil.test/o/r/pull/3 https://x@github.com/o/r/pull/3",
    ),
  ).toEqual([]);
  expect(
    observedResources(
      "https://www.figma.com/design/Abc/title?node-id=12-34 https://github.com/o/r/pull/3",
    ),
  ).toEqual([
    { provider: "figma", resourceId: "Abc/nodes/12:34" },
    { provider: "github", resourceId: "o/r/pulls/3" },
  ]);
});
it("completes the one-shot loopback callback without recursive abort and exchanges with PKCE", async () => {
  const write = vi.fn(async (_value: unknown) => {});
  let exchanges = 0;
  const connectors = new ContextConnectors({
    store: () => ({ read: async () => null, write }),
    changed: () => {},
    remote: {
      call: async (path, payload: any) => {
        if (path.endsWith("/start"))
          return {
            authorizationUrl:
              "https://github.com/login/oauth/authorize?state=signed-state",
            state: "signed-state",
          } as any;
        exchanges++;
        expect(payload.code).toBe("code");
        expect(payload.codeVerifier).toHaveLength(43);
        return { accessToken: "test-token" } as any;
      },
    },
    open: async () => {
      const response = await fetch(
        "http://127.0.0.1:43120/context/callback?state=signed-state&code=code",
      );
      expect(response.status).toBe(200);
    },
  });
  await connectors.setAccount("one");
  await connectors.connect("github");
  expect(exchanges).toBe(1);
  expect(write).toHaveBeenCalledTimes(1);
  expect(connectors.snapshot()).toHaveLength(1);
  connectors.dispose();
});
it("preserves refresh tokens omitted by provider and rejects mismatched source identity", async () => {
  const write = vi.fn(async (_value: unknown) => {});
  const connectors = new ContextConnectors({
    store: () => ({
      read: async () =>
        ({
          figma: {
            accessToken: "old",
            refreshToken: "refresh",
            expiresAtMs: 1,
          },
        }) as any,
      write,
    }),
    changed: () => {},
    open: async () => {},
    remote: {
      call: async (path) =>
        path.endsWith("/refresh")
          ? ({ accessToken: "new", expiresAtMs: Date.now() + 100000 } as any)
          : ({
              resourceId: "wrong",
              text: "private",
              revision: "r",
              capturedAtMs: Date.now(),
            } as any),
    },
  });
  await connectors.setAccount("one");
  await expect(
    connectors.read("figma", "expected", new AbortController().signal),
  ).rejects.toThrow("Invalid source");
  expect(write.mock.calls[0]?.[0]).toMatchObject({
    figma: { refreshToken: "refresh", accessToken: "new" },
  });
  connectors.dispose();
});
it("respects Retry-After without repeatedly hitting the provider", async () => {
  const { ContextRequestError } = await import("../src/main/context-transport");
  let calls = 0;
  const connectors = new ContextConnectors({
    store: () => ({
      read: async () => ({ github: { accessToken: "token" } }) as any,
      write: async () => {},
    }),
    changed: () => {},
    open: async () => {},
    remote: {
      call: async () => {
        calls++;
        throw new ContextRequestError(429, "rate_limited", 90000);
      },
    },
  });
  await connectors.setAccount("one");
  await connectors.read("github", "o/r/issues/1", new AbortController().signal);
  await connectors.read("github", "o/r/issues/2", new AbortController().signal);
  expect(calls).toBe(1);
  connectors.dispose();
});
it("purges revoked credentials and evidence but preserves credentials on Clerk authentication errors", async () => {
  const { ContextRequestError } = await import("../src/main/context-transport");
  const revoked = vi.fn(async () => {}),
    write = vi.fn(async (_value: unknown) => {});
  let code = "unauthorized";
  const connectors = new ContextConnectors({
    revoked,
    store: () => ({
      read: async () => ({ github: { accessToken: "token" } }) as any,
      write,
    }),
    changed: () => {},
    open: async () => {},
    remote: {
      call: async () => {
        throw new ContextRequestError(401, code);
      },
    },
  });
  await connectors.setAccount("one");
  await expect(
    connectors.read("github", "o/r/issues/1", new AbortController().signal),
  ).rejects.toThrow();
  expect(connectors.snapshot()).toHaveLength(1);
  code = "authorization_revoked";
  await connectors.read("github", "o/r/issues/1", new AbortController().signal);
  expect(connectors.snapshot()).toHaveLength(0);
  expect(write).toHaveBeenLastCalledWith({}, expect.any(AbortSignal));
  expect(revoked).toHaveBeenCalledWith("github");
  connectors.dispose();
});
it("returns manual Figma revocation instructions after clearing local credentials", async () => {
  const connectors = new ContextConnectors({
    store: () => ({
      read: async () => ({ figma: { accessToken: "token" } }) as any,
      write: async () => {},
    }),
    changed: () => {},
    open: async () => {},
    remote: {
      call: async () =>
        ({
          revoked: false,
          requiresProviderAction: true,
          settingsUrl: "https://www.figma.com/settings",
        }) as any,
    },
  });
  await connectors.setAccount("one");
  expect(await connectors.disconnect("figma")).toEqual({
    revoked: false,
    requiresProviderAction: true,
    settingsUrl: "https://www.figma.com/settings",
  });
  expect(connectors.snapshot()).toHaveLength(0);
  connectors.dispose();
});
