import { beforeEach, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({
  data: new Map<string, any>(),
  block: false,
  release: undefined as undefined | (() => void),
}));
vi.mock("../src/main/secure-store", () => ({
  SecureStore: class {
    constructor(private path: string) {}
    async read() {
      return mocks.data.get(this.path) ?? null;
    }
    async write(value: any) {
      if (mocks.block) {
        mocks.block = false;
        await new Promise<void>((r) => {
          mocks.release = r;
        });
      }
      mocks.data.set(this.path, value);
    }
  },
}));
vi.mock("../src/main/context-service", () => ({
  ContextServiceClient: class {
    async call(op: string) {
      return op === "history" ? { evidence: [], savedIds: [] } : {};
    }
    stop() {}
  },
}));
import { ContextController } from "../src/main/context-controller";
import { ProductState } from "../src/main/state";
const tick = () => new Promise((r) => setTimeout(r, 0));
function setup(verified = true) {
  const state = new ProductState();
  state.update({
    enabled: true,
    account: { state: "signed_in", identity: { subject: "one" } as any },
    permissions: { accessibility: "granted", inputMonitoring: "granted" },
  });
  const controller = new ContextController({
    root: "/synthetic",
    executable: "/unused",
    apiUrl: "https://example.test",
    tokenProvider: { getAccessToken: async () => "" },
    visionVerified: verified,
    open: async () => {},
    changed: () => {},
    send: () => {},
    invalidate: () => {},
  });
  controller.setEnvironment(state.snapshot());
  return { controller, state };
}
beforeEach(() => {
  mocks.data.clear();
  mocks.block = false;
  mocks.release = undefined;
});
it("requires separate persisted image consent and verified provider support", async () => {
  const { controller } = setup(false);
  await controller.engine.refresh();
  await controller.action({
    id: "1",
    action: "context_set_enabled",
    payload: { enabled: true },
  });
  expect(controller.imagesEnabled).toBe(false);
  await controller.action({
    id: "2",
    action: "context_set_visual_enabled",
    payload: { enabled: true },
  });
  expect(controller.snapshot().visualStatus).toBe("unverified");
  expect(controller.imagesEnabled).toBe(false);
  controller.dispose();
});
it("does not restore an earlier image enable after the user has disabled it", async () => {
  const { controller } = setup();
  await controller.engine.refresh();
  await controller.action({
    id: "1",
    action: "context_set_enabled",
    payload: { enabled: true },
  });
  mocks.block = true;
  const enabling = controller.action({
    id: "2",
    action: "context_set_visual_enabled",
    payload: { enabled: true },
  });
  await tick();
  const disabling = controller.action({
    id: "3",
    action: "context_set_visual_enabled",
    payload: { enabled: false },
  });
  expect(controller.imagesEnabled).toBe(false);
  mocks.release!();
  await enabling;
  expect(controller.imagesEnabled).toBe(false);
  await disabling;
  expect(controller.snapshot().visualEnabled).toBe(false);
  controller.dispose();
});
it("revokes capture synchronously on account change and lock", async () => {
  const { controller, state } = setup();
  await controller.engine.refresh();
  await controller.action({
    id: "1",
    action: "context_set_enabled",
    payload: { enabled: true },
  });
  expect(controller.enabled).toBe(true);
  controller.setLocked(true, state.snapshot());
  expect(controller.enabled).toBe(false);
  state.update({ account: { state: "signed_out", identity: null } });
  controller.setEnvironment(state.snapshot());
  expect(controller.snapshot().visualEnabled).toBe(false);
  expect(controller.enabled).toBe(false);
  controller.dispose();
});
