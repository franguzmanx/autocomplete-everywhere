import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { LearningService, learningFileForAccount } from "../src/main/learning-service";

const subject = "account-A";
const appId = "com.example.Editor";
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const edit = (enabled = true) => ({ accountSubject: subject, enabled, edits: [], forgetIds: [], reset: false });
function fixture() {
  const disk = new Map<string, unknown>();
  const writes: unknown[] = [];
  const extract = vi.fn(async (input: any, _signal: AbortSignal) => ({ evidence: input.observations.map((o: any) => ({ observationId: o.id, dimension: "concision", value: "concise" })) }));
  let failWrite = false;
  const options = {
    storeForAccount: (id: string) => ({ read: async () => structuredClone(disk.get(id) ?? null), write: async (value: unknown) => { if (failWrite) throw Error("disk"); writes.push(structuredClone(value)); disk.set(id, structuredClone(value)); } }),
    extract, changed: vi.fn(), now: () => Date.now(),
  };
  const service = new LearningService(options);
  const observe = (n: number, session = 1) => { service.registerRequest(uuid(n), appId); service.interaction(uuid(n), "accepted_full"); service.observe(uuid(n), { appId, sessionId: uuid(session + 1000), before: "A rather lengthy generated answer", after: "A short corrected answer", observedAtMs: Date.now() }); };
  return { service, options, disk, writes, extract, observe, fail: () => { failWrite = true; } };
}
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date("2026-09-05T12:00:00Z")); });
afterEach(() => vi.useRealTimers());

describe("bounded learning", () => {
  it("is off by default and persists no raw observations", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, []);
    f.observe(1); await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).not.toHaveBeenCalled();
    await f.service.save(edit()); f.observe(2); await vi.advanceTimersByTimeAsync(30_000);
    expect(f.extract).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(f.writes)).not.toContain("generated answer");
    expect(JSON.stringify(f.writes)).not.toContain("corrected answer");
    expect(f.service.snapshot().preferences).toEqual([]);
  });
  it("activates after three corrections in two sessions, scoped to the app", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
    f.observe(1); f.observe(2); f.observe(3, 2); await vi.advanceTimersByTimeAsync(30_000);
    expect(f.service.snapshot().preferences).toEqual([expect.objectContaining({ appId, dimension: "concision", value: "concise", origin: "learned" })]);
    expect(f.service.preferencesForApp("com.other.Editor")).toEqual([]);
    expect(f.service.preferencesForApp(appId)).toHaveLength(1);
  });
  it("does not activate from repeated delivery of one correction or one session", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
    f.observe(1); f.observe(1); f.observe(2); f.observe(3); await vi.advanceTimersByTimeAsync(30_000);
    expect(f.extract.mock.calls[0]![0].observations).toHaveLength(3);
    expect(f.service.snapshot().preferences).toEqual([]);
  });
  it("cancels on typing, counts attempts, and expires rather than queues observations", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
    let resolve!: (result: any) => void;
    f.extract.mockImplementationOnce((_i, _s) => new Promise(r => { resolve = r; }));
    f.observe(1); f.observe(2); f.observe(3, 2); await vi.advanceTimersByTimeAsync(30_000);
    const signal = f.extract.mock.calls[0]![1]; f.service.userActivity(); expect(signal.aborted).toBe(true);
    resolve({ evidence: [1, 2, 3].map(n => ({ observationId: uuid(n), dimension: "concision", value: "concise" })) });
    await vi.advanceTimersByTimeAsync(1); expect(f.service.snapshot().preferences).toEqual([]);
    f.observe(4); await vi.advanceTimersByTimeAsync(15 * 60_000); expect(f.extract).toHaveBeenCalledTimes(1);
    f.observe(5); await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).toHaveBeenCalledTimes(2);
  });
  it("persists budget before sending and does not send when persistence fails", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit()); f.fail();
    f.observe(1); await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).not.toHaveBeenCalled();
  });
  it("separates accounts and drops in-flight results after account change", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
    let resolve!: (result: any) => void;
    f.extract.mockImplementationOnce((_i, _s) => new Promise(r => { resolve = r; }));
    f.observe(1); await vi.advanceTimersByTimeAsync(30_000);
    await f.service.setEnvironment("account-B", true, []); expect(f.service.snapshot().enabled).toBe(false);
    resolve({ evidence: [{ observationId: uuid(1), dimension: "concision", value: "concise" }] }); await vi.advanceTimersByTimeAsync(1);
    await expect(f.service.save(edit())).rejects.toThrow("Account changed");
    await f.service.setEnvironment(subject, true, []); expect(f.service.snapshot().enabled).toBe(true);
    expect(f.service.snapshot().preferences).toEqual([]);
    expect(learningFileForAccount("/secure", subject)).not.toBe(learningFileForAccount("/secure", "account-B"));
  });
  it("applies draft patches without losing concurrent additions and makes edits explicit", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
    const draft = edit(); f.observe(1); f.observe(2); f.observe(3, 2); await vi.advanceTimersByTimeAsync(30_000);
    await f.service.save(draft); const p = f.service.snapshot().preferences[0]!;
    expect(p).toBeDefined();
    await f.service.save({ ...edit(), edits: [{ ...p, dimension: "concision", value: "detailed", appId: null, origin: "explicit" }] });
    expect(f.service.preferencesForApp("com.other.Editor")[0]).toMatchObject({ value: "detailed", origin: "explicit", appId: null });
    await f.service.save(edit(false)); expect(f.service.preferencesForApp(appId)).toEqual([]);
    expect(f.service.snapshot().preferences).toHaveLength(1);
    await f.service.save({ ...edit(false), reset: true }); expect(f.service.snapshot().preferences).toEqual([]);
  });
  it("ignores excluded, expired and malformed observations; disabling cancels work", async () => {
    const f = fixture(); await f.service.setEnvironment(subject, true, [appId]); await f.service.save(edit());
    f.observe(1); await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).not.toHaveBeenCalled();
    await f.service.setEnvironment(subject, true, []);
    f.service.observe(uuid(2), { appId, sessionId: uuid(2), before: "x", after: "y", observedAtMs: Date.now() - 300_001 });
    f.observe(3); await f.service.save(edit(false)); await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).not.toHaveBeenCalled();
  });
});

it("rejects a stale account disable draft without disrupting the active account", async () => {
  const f = fixture(); await f.service.setEnvironment("account-B", true, []);
  await f.service.save({ ...edit(), accountSubject: "account-B" });
  await expect(f.service.save(edit(false))).rejects.toThrow("Account changed");
  f.observe(1); await vi.advanceTimersByTimeAsync(30_000);
  expect(f.extract).toHaveBeenCalledTimes(1); expect(f.service.snapshot().enabled).toBe(true);
});
it("keeps the quota through restart and reset, with at most twelve daily requests", async () => {
  const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
  for (let n = 1; n <= 12; n++) { f.observe(n); await vi.advanceTimersByTimeAsync(30_000); await vi.advanceTimersByTimeAsync(15 * 60_000); }
  expect(f.extract).toHaveBeenCalledTimes(12);
  await f.service.save({ ...edit(), reset: true }); f.service.dispose();
  const restarted = new LearningService(f.options); await restarted.setEnvironment(subject, true, []);
  restarted.registerRequest(uuid(13), appId); restarted.interaction(uuid(13), "accepted_full");
  restarted.observe(uuid(13), { appId, sessionId: uuid(1001), before: "More words", after: "Fewer", observedAtMs: Date.now() });
  await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).toHaveBeenCalledTimes(12);
  await vi.advanceTimersByTimeAsync(24 * 60 * 60_000); // expired queued data never becomes tomorrow's input
  expect(f.extract).toHaveBeenCalledTimes(12);
  restarted.registerRequest(uuid(14), appId); restarted.interaction(uuid(14), "accepted_full");
  restarted.observe(uuid(14), { appId, sessionId: uuid(1001), before: "More words", after: "Fewer", observedAtMs: Date.now() });
  await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).toHaveBeenCalledTimes(13);
});
it("reports partial save failures without acknowledging unsaved personalization", async () => {
  const f = fixture(); await f.service.setEnvironment(subject, true, []); const controls = vi.fn(async () => {}); f.fail();
  await expect(f.service.save(edit(), controls)).rejects.toThrow("Writing controls saved. Personalization could not be saved");
  expect(controls).toHaveBeenCalledTimes(1); expect(f.service.snapshot().enabled).toBe(false);
});
it("finishes account loading across permission changes and cancels an active extraction on exclusion", async () => {
  const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
  let release!: (raw: unknown) => void;
  const service = new LearningService({ ...f.options, storeForAccount: () => ({ read: () => new Promise(r => { release = r; }), write: async () => {} }) });
  const loading = service.setEnvironment(subject, true, []); await Promise.resolve();
  await service.setEnvironment(subject, false, []); release(f.disk.get(subject)); await loading;
  expect(service.snapshot().enabled).toBe(true);
  await service.setEnvironment(subject, true, []);
  let finish!: (raw: any) => void;
  f.extract.mockImplementationOnce(() => new Promise(r => { finish = r; }));
  service.registerRequest(uuid(90), appId); service.interaction(uuid(90), "accepted_full");
  service.observe(uuid(90), { appId, sessionId: uuid(1001), before: "Long words", after: "Short", observedAtMs: Date.now() });
  await vi.advanceTimersByTimeAsync(30_000);
  const signal = f.extract.mock.calls[0]![1]; await service.setEnvironment(subject, true, [appId]);
  expect(signal.aborted).toBe(true); finish({ evidence: [] }); await vi.advanceTimersByTimeAsync(1);
});
it("does not send snippets that expire while waiting for the encrypted budget write", async () => {
  const f = fixture(); let release!: () => void; let slow = false;
  const service = new LearningService({ ...f.options, storeForAccount: () => ({ read: async () => null, write: async () => { if (slow) await new Promise<void>(r => { release = r; }); } }) });
  await service.setEnvironment(subject, true, []); await service.save(edit()); slow = true;
  service.registerRequest(uuid(91), appId); service.interaction(uuid(91), "accepted_full");
  service.observe(uuid(91), { appId, sessionId: uuid(1001), before: "Long words", after: "Short", observedAtMs: Date.now() });
  await vi.advanceTimersByTimeAsync(30_000); await vi.advanceTimersByTimeAsync(5 * 60_000); release();
  await vi.advanceTimersByTimeAsync(1); expect(f.extract).not.toHaveBeenCalled();
});
it("requires a verified accepted request in the current account and destination", async () => {
  const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
  const correction = { appId, sessionId: uuid(1001), before: "Long words", after: "Short", observedAtMs: Date.now() };
  f.service.observe(uuid(1), correction); // invented/unseen
  f.service.registerRequest(uuid(2), appId); f.service.interaction(uuid(2), "failed"); f.service.observe(uuid(2), correction);
  f.service.registerRequest(uuid(3), appId); f.service.interaction(uuid(3), "accepted_full");
  f.service.observe(uuid(3), { ...correction, appId: "com.other.Editor" });
  await f.service.setEnvironment("account-B", true, []); await f.service.save({ ...edit(), accountSubject: "account-B" });
  f.service.observe(uuid(3), correction); await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).not.toHaveBeenCalled();
});
it("rejects queued save after an A-B-A account switch", async () => {
  const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit());
  let release!: () => void;
  const first = f.service.save(edit(), () => new Promise<void>(r => { release = r; }));
  await Promise.resolve();
  const controls = vi.fn(async () => {}); const queued = f.service.save(edit(), controls);
  const b = f.service.setEnvironment("account-B", true, []); const a = f.service.setEnvironment(subject, true, []);
  release(); await expect(first).rejects.toThrow("Account changed"); await expect(queued).rejects.toThrow("Account changed");
  await Promise.all([a,b]); expect(controls).not.toHaveBeenCalled();
});
it("does not overwrite an inaccessible account store and restores quota after recovery", async () => {
  const f = fixture(); await f.service.setEnvironment(subject, true, []); await f.service.save(edit()); f.observe(1); await vi.advanceTimersByTimeAsync(30_000); f.service.dispose();
  let unavailable = true;
  const restored = new LearningService({ ...f.options, storeForAccount: account => {
    const store = f.options.storeForAccount(account); return { ...store, read: async () => { if (unavailable) throw Error("Encryption unavailable"); return store.read(); } };
  } });
  await expect(restored.setEnvironment(subject, true, [])).rejects.toThrow("Encryption unavailable"); unavailable = false;
  await expect(restored.save(edit())).rejects.toThrow("not available");
  await restored.setEnvironment(null, false, []); await restored.setEnvironment(subject, true, []);
  restored.registerRequest(uuid(2),appId); restored.interaction(uuid(2),"accepted_full");
  restored.observe(uuid(2),{appId,sessionId:uuid(1001),before:"Longer text",after:"Short",observedAtMs:Date.now()});
  await vi.advanceTimersByTimeAsync(30_000); expect(f.extract).toHaveBeenCalledTimes(1);
});
it("bounds retained corrections to twelve and one extraction batch to six", async()=>{
  const f=fixture(); await f.service.setEnvironment(subject,true,[]); await f.service.save(edit());
  for(let n=1;n<=20;n++)f.observe(n);
  await vi.advanceTimersByTimeAsync(30_000);
  const batch=f.extract.mock.calls[0]![0].observations;
  expect(batch).toHaveLength(6); expect(batch[0].id).toBe(uuid(9));
  expect(batch.every((o:any)=>o.before===""&&o.after==="")).toBe(true); // disposed after completion
  await vi.advanceTimersByTimeAsync(15*60_000); expect(f.extract).toHaveBeenCalledTimes(1);
});
