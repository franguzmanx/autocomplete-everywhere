import { expect, test, vi } from "vitest";
import { LocalLibrary, libraryInputSchema } from "../src/main/local-library";

function fixture() {
  let data: unknown = null;
  const storage = { read: async <T>() => structuredClone(data) as T | null, write: vi.fn(async (next: unknown) => { data = structuredClone(next); }) };
  const changed = vi.fn();
  return { storage, changed, library: new LocalLibrary(storage, changed) };
}
const input = { title: "Acme prices", kind: "knowledge" as const, text: "Standard plan costs 90", scope: { appIds: ["com.apple.Notes"], anchor: "Acme project" }, expiresAt: null };

test("persists explicit sources, replaces revisions and invalidates removed knowledge", async () => {
  const { library, storage, changed } = fixture(); await library.load();
  const entry = await library.upsert(input);
  expect(entry).toMatchObject({ revision: 1, provenance: { kind: "user" } });
  const restarted = new LocalLibrary(storage, changed); await restarted.load();
  expect(restarted.list()).toEqual([entry]);
  const updated = await restarted.upsert({ ...input, id: entry.id, expectedRevision: 1, text: "Standard plan costs 120" });
  expect(updated.revision).toBe(2);
  expect(restarted.select({ appId: "com.apple.Notes", text: "Acme project pricing" })[0]?.text).toContain("120");
  await expect(restarted.upsert({ ...input, id: entry.id, expectedRevision: 1 })).rejects.toThrow(/changed/i);
  await restarted.delete(entry.id, 2);
  expect(restarted.select({ appId: "com.apple.Notes", text: "Acme project pricing" })).toEqual([]);
  expect(changed).toHaveBeenCalledTimes(3);
});

test("requires explicit app and anchored topic scope before lexical ranking", async () => {
  const { library } = fixture(); await library.load(); await library.upsert(input);
  expect(library.select({ appId: "com.apple.Mail", text: "Acme project Standard plan" })).toEqual([]);
  expect(library.select({ appId: "com.apple.Notes", text: "Other project Standard plan" })).toEqual([]);
  expect(library.select({ appId: "com.apple.Notes", text: "Acme projects" })).toEqual([]);
  expect(library.select({ appId: "com.apple.Notes", text: "Acme project: quote" })).toHaveLength(1);
  expect(libraryInputSchema.safeParse({ ...input, scope: { appIds: [], anchor: "" } }).success).toBe(false);
  const style = await library.upsert({ ...input, kind: "style", text: "Use short sentences", scope: { appIds: [], anchor: "" } });
  expect(library.select({ appId: "com.apple.Mail", text: "Hello" })[0]?.sourceId).toBe(style.id);
});

test("failed persistence preserves previous snapshot, expired sources are inadmissible, returned data cannot mutate index", async () => {
  const { library, storage, changed } = fixture(); await library.load();
  await library.upsert({ ...input, expiresAt: 1 });
  expect(library.select({ appId: "com.apple.Notes", text: "Acme project" })).toEqual([]);
  library.list()[0]!.text = "tampered";
  expect(library.list()[0]?.text).toBe(input.text);
  storage.write.mockRejectedValueOnce(new Error("disk unavailable"));
  await expect(library.upsert(input)).rejects.toThrow("disk unavailable");
  expect(library.list()).toHaveLength(1); expect(changed).toHaveBeenCalledTimes(1);
});

test("serializes concurrent edits and bounds candidate content", async () => {
  const { library } = fixture(); await library.load();
  await Promise.all(Array.from({ length: 8 }, (_, index) => library.upsert({ ...input, title: `Source ${index}`, text: "A".repeat(3000) })));
  const result = library.select({ appId: "com.apple.Notes", text: "Acme project" });
  expect(library.list()).toHaveLength(8); expect(result).toHaveLength(4);
  expect(result.reduce((sum, entry) => sum + entry.text.length, 0)).toBe(12000);
});

test("expiration cancels pending suggestions and disposal clears the timer", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1000);
  try {
    const { library, changed } = fixture(); await library.load();
    await library.upsert({ ...input, expiresAt: 1100 });
    changed.mockClear(); await vi.advanceTimersByTimeAsync(100);
    expect(changed).toHaveBeenCalledOnce();
    expect(library.select({ appId: "com.apple.Notes", text: "Acme project" })).toEqual([]);
    library.expire(); expect(changed).toHaveBeenCalledOnce(); library.dispose();
  } finally { vi.useRealTimers(); }
});
