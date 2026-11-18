import { describe, it, expect, vi } from "vitest";
import { ContextEngine } from "../src/main/context-engine";
function setup() {
  const calls: any[] = [];
  let persisted = true;
  const store = {
    call: vi.fn(async (op: string, payload?: any) => {
      calls.push({ op, payload });
      if (op === "history") return { evidence: [], savedIds: [] };
      if (op === "retrieve")
        return {
          availability: { text: "ready", semantic: "not_prepared" },
          evidence: [],
          dependencies: [],
          revision: "1",
        };
      if (op === "validate") return true;
      return {};
    }),
  };
  const remote = {
    call: vi.fn(async () => ({ embedding: Array(768).fill(0) })),
  };
  const engine = new ContextEngine({
    store: store as any,
    remote: remote as any,
    changed: () => {},
    invalidate: vi.fn(),
    readEnabled: async () => persisted,
    writeEnabled: async (_a, v) => {
      persisted = v;
    },
  });
  return { engine, calls, store, remote };
}
const observation = {
  appId: "com.test",
  documentId: "doc",
  capturedAtMs: Date.now(),
  sources: [{ id: "1", text: "a source" }],
};
describe("context account boundaries", () => {
  it("does not observe until enabled for a signed in account", async () => {
    const { engine, calls } = setup();
    await engine.observe(observation);
    expect(calls).toEqual([]);
    engine.setEnvironment("one", true, []);
    await engine.refresh();
    await engine.observe(observation);
    expect(calls.some((c) => c.op === "put")).toBe(true);
  });
  it("deduplicates source revisions and excludes blocked apps", async () => {
    const { engine, calls } = setup();
    engine.setEnvironment("one", true, []);
    await engine.refresh();
    await engine.observe(observation);
    await engine.observe(observation);
    expect(calls.filter((c) => c.op === "put")).toHaveLength(1);
    engine.setEnvironment("one", true, ["com.test"]);
    await engine.refresh();
    await engine.observe({
      ...observation,
      sources: [{ id: "1", text: "new" }],
    });
    expect(calls.filter((c) => c.op === "put")).toHaveLength(1);
    expect(calls.some((c) => c.op === "purgeApp")).toBe(true);
  });
  it("pausing immediately suppresses acquisition and retrieval", async () => {
    const { engine } = setup();
    engine.setEnvironment("one", true, []);
    await engine.refresh();
    engine.setEnvironment("one", false, []);
    expect(engine.captureEnabled).toBe(false);
    expect(
      await engine.prepare(
        "id",
        "hello",
        "com.test",
        new AbortController().signal,
      ),
    ).toBeUndefined();
  });
  it("disable persists and clears active context", async () => {
    const { engine } = setup();
    engine.setEnvironment("one", true, []);
    await engine.refresh();
    await engine.setEnabled(false);
    expect(engine.captureEnabled).toBe(false);
  });
});
it("does not resurrect enabled state after account changes during settings load", async () => {
  let finish!: (value: boolean) => void;
  const base = setup();
  const engine = new ContextEngine({
    store: base.store as any,
    remote: base.remote as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await new Promise((resolve) => setTimeout(resolve, 0));
  engine.setEnvironment(null, true, []);
  finish(true);
  await engine.refresh();
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(engine.captureEnabled).toBe(false);
  expect(engine.snapshot().enabled).toBe(false);
});
it("does not write a reference into a new account after waiting for the old account", async () => {
  let finish!: (value: boolean) => void;
  const base = setup();
  const engine = new ContextEngine({
    store: base.store as any,
    remote: base.remote as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await new Promise((resolve) => setTimeout(resolve, 0));
  const adding = engine.addReference("private first account");
  engine.setEnvironment(null, true, []);
  finish(true);
  await expect(adding).rejects.toThrow("Account changed");
  expect(base.calls.some((c) => c.op === "put")).toBe(false);
});
it("only retrieves explicit resources in background and throttles repeated references", async () => {
  const base = setup();
  const readResource = vi.fn(async (_provider: string, resourceId: string) => ({
    resourceId,
    text: "Observed issue",
    revision: "resource-revision",
    capturedAtMs: Date.now(),
  }));
  const engine = new ContextEngine({
    store: base.store as any,
    remote: base.remote as any,
    readResource: readResource as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: async () => true,
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  const source = {
    ...observation,
    capturedAtMs: Date.now(),
    sources: [{ id: "s", text: "See https://github.com/owner/repo/issues/3" }],
  };
  await engine.observe(source);
  await new Promise((resolve) => setTimeout(resolve, 0));
  await engine.observe(source);
  expect(readResource).toHaveBeenCalledTimes(1);
  expect(
    base.calls.some(
      (c) =>
        c.op === "put" &&
        c.payload.evidence.appId === "connector.github" &&
        c.payload.evidence.provenance === "observed",
    ),
  ).toBe(true);
  await engine.observe({ ...source, capturedAtMs: Date.now() + 60000 });
  expect(readResource).toHaveBeenCalledTimes(1);
});
it("retains only the latest pending image while a visual request is running", async () => {
  const base = setup();
  let finish!: (value: { text: string }) => void;
  const seen: string[] = [];
  const remote = {
    call: vi.fn(async (path: string, payload: any) => {
      if (path !== "visual") return { embedding: Array(768).fill(0) };
      seen.push(payload.imageBase64);
      if (seen.length === 1)
        return new Promise((resolve) => {
          finish = resolve;
        });
      return { text: "latest visible source" };
    }),
  };
  const engine = new ContextEngine({
    store: base.store as any,
    remote: remote as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: async () => true,
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  const image = (data: string) => ({
    ...observation,
    capturedAtMs: Date.now(),
    image: { data, mediaType: "image/jpeg" as const },
  });
  await engine.observe(image("AAAA"));
  await new Promise((resolve) => setTimeout(resolve, 0));
  await engine.observe(image("BBBB"));
  await engine.observe(image("CCCC"));
  expect(seen).toEqual(["AAAA"]);
  finish({ text: "stale visible source" });
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(seen).toEqual(["AAAA", "CCCC"]);
  expect(
    base.calls
      .filter((c) => c.op === "put")
      .some((c) => c.payload.evidence.text === "stale visible source"),
  ).toBe(false);
  engine.dispose();
});
it("retrieves across applications rather than filtering history to the destination app", async () => {
  const { engine, calls } = setup();
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  await engine.observe({ ...observation, appId: "source.browser" });
  await engine.prepare(
    "request",
    "a source",
    "destination.chat",
    new AbortController().signal,
  );
  const retrieval = calls.find((c) => c.op === "retrieve");
  expect(retrieval.payload).not.toHaveProperty("appId");
  engine.dispose();
});
it("reuses prepared semantic context as a draft grows but not when the draft is replaced", async () => {
  const { engine, calls } = setup();
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  const signal = new AbortController().signal;
  await engine.prepare("first", "The launch date", "destination.chat", signal);
  await new Promise((resolve) => setTimeout(resolve, 0));
  await engine.prepare(
    "second",
    "The launch date is",
    "destination.chat",
    signal,
  );
  expect(
    calls.filter((c) => c.op === "retrieve").at(-1).payload.embedding,
  ).toHaveLength(768);
  await engine.prepare(
    "third",
    "Completely different topic",
    "destination.chat",
    signal,
  );
  expect(
    calls.filter((c) => c.op === "retrieve").at(-1).payload,
  ).not.toHaveProperty("embedding");
  engine.dispose();
});
it("cannot start visual analysis when consent was revoked while storing its observation", async () => {
  const base = setup();
  let release!: () => void;
  const original = base.store.call;
  const store = {
    call: async (op: string, payload: any) => {
      if (op === "put")
        await new Promise<void>((resolve) => {
          release = resolve;
        });
      return original(op, payload);
    },
  };
  const engine = new ContextEngine({
    store: store as any,
    remote: base.remote as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: async () => true,
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  const observing = engine.observe({
    ...observation,
    capturedAtMs: Date.now(),
    image: { mediaType: "image/jpeg", data: "AAAA" },
  });
  await new Promise((resolve) => setTimeout(resolve, 0));
  engine.stopVisual();
  release();
  await observing;
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(
    base.remote.call.mock.calls.some((args: any[]) => args[0] === "visual"),
  ).toBe(false);
  engine.dispose();
});
it("runs the latest search after an earlier refresh finishes and never publishes obsolete results", async () => {
  const base = setup();
  let release!: (value: any) => void;
  const queries: string[] = [];
  const store = {
    call: async (op: string, payload: any) => {
      if (op === "search") {
        queries.push(payload.query);
        if (payload.query === "first")
          return new Promise((resolve) => {
            release = resolve;
          });
        return { evidence: [], savedIds: [] };
      }
      return base.store.call(op, payload);
    },
  };
  const engine = new ContextEngine({
    store: store as any,
    remote: base.remote as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: async () => true,
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  const first = engine.browse("first");
  await new Promise((resolve) => setTimeout(resolve, 0));
  await engine.browse("second");
  release({ evidence: [], savedIds: [] });
  await first;
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(queries).toEqual(["first", "second"]);
  engine.dispose();
});
it("reports unavailable semantic preparation without blocking complementary text retrieval", async () => {
  const base = setup();
  const remote = {
    call: vi.fn(async () => {
      throw new Error("provider unavailable");
    }),
  };
  const engine = new ContextEngine({
    store: base.store as any,
    remote: remote as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: async () => true,
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  await engine.prepare(
    "1",
    "launch details",
    "chat",
    new AbortController().signal,
  );
  await new Promise((r) => setTimeout(r, 0));
  const context = await engine.prepare(
    "2",
    "launch details now",
    "chat",
    new AbortController().signal,
  );
  expect(context?.availability.semantic).toBe("unavailable");
  expect(engine.snapshot().semanticStatus).toBe("unavailable");
  expect(remote.call).toHaveBeenCalledTimes(1);
  engine.dispose();
});
it("resumes indexing retained unembedded evidence after restart", async () => {
  const base = setup();
  const now = Date.now();
  const evidence = {
    id: "pending",
    sourceId: "pending",
    revision: "1",
    appId: "browser",
    provenance: "observed",
    text: "Synthetic retained context",
    capturedAtMs: now,
    expiresAtMs: now + 10000,
    dependencies: [],
  };
  const store = {
    call: async (op: string, payload: any) =>
      op === "pendingEmbeddings"
        ? { evidence: [evidence] }
        : base.store.call(op, payload),
  };
  const engine = new ContextEngine({
    store: store as any,
    remote: base.remote as any,
    changed: () => {},
    invalidate: () => {},
    readEnabled: async () => true,
    writeEnabled: async () => {},
  });
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  await engine.maintain();
  await new Promise((r) => setTimeout(r, 0));
  expect(
    base.calls.some(
      (c) => c.op === "embed" && c.payload.evidenceId === "pending",
    ),
  ).toBe(true);
  engine.dispose();
});

it("uses a completed matching screen embedding on the first proactive request without waiting for a new one", async () => {
  const { engine, remote, calls } = setup();
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  await engine.observe(observation);
  await new Promise(resolve => setTimeout(resolve, 0));
  remote.call.mockImplementation(() => new Promise(() => {}));
  await engine.prepare("first-proactive", "a", observation.appId, new AbortController().signal, "a source");
  expect(calls.filter(c => c.op === "retrieve").at(-1).payload.embedding).toHaveLength(768);
  engine.dispose();
});

it("does not borrow a prepared screen vector from another app or changed screen", async () => {
  const { engine, calls } = setup();
  engine.setEnvironment("one", true, []);
  await engine.refresh();
  await engine.observe(observation);
  await new Promise(resolve => setTimeout(resolve, 0));
  await engine.prepare("other-app", "", "another.app", new AbortController().signal, "a source");
  expect(calls.filter(c => c.op === "retrieve").at(-1).payload).not.toHaveProperty("embedding");
  await engine.prepare("other-screen", "", observation.appId, new AbortController().signal, "different source");
  expect(calls.filter(c => c.op === "retrieve").at(-1).payload).not.toHaveProperty("embedding");
  engine.dispose();
});
