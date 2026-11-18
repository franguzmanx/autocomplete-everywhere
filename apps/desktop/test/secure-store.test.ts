import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test, vi } from "vitest";
vi.mock("electron", () => ({ safeStorage: {
  isEncryptionAvailable: vi.fn(() => true),
  encryptString: (text: string) => Buffer.from(`encrypted:${text}`, "utf8"),
  decryptString: (buffer: Buffer) => buffer.toString("utf8").replace(/^encrypted:/, ""),
} }));
vi.mock("node:fs/promises", async importOriginal => {
  const actual = await importOriginal<typeof import("node:fs/promises")>();
  return { ...actual, rename: vi.fn(actual.rename), open: vi.fn(actual.open) };
});
import { rename, open } from "node:fs/promises";
import { safeStorage } from "electron";
import { SecureStore } from "../src/main/secure-store";

test("atomic encrypted replacement preserves the existing store when rename fails", async () => {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-secure-"));
  try {
    const path = join(directory, "library.enc"); const store = new SecureStore(path);
    await store.write({ tokens: { refresh: "fixture" } }); const previous = await readFile(path);
    vi.mocked(rename).mockRejectedValueOnce(new Error("disk failure"));
    await expect(store.write({ entries: [] })).rejects.toThrow("disk failure");
    expect(await readFile(path)).toEqual(previous);
    expect(await store.read()).toEqual({ tokens: { refresh: "fixture" } });
    expect(await readdir(directory)).toEqual(["library.enc"]);
    await store.write({ entries: [] }); expect(await store.read()).toEqual({ entries: [] });
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("an aborted write preserves the encrypted file and removes its temporary file", async () => {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-secure-cancel-"));
  try {
    const path = join(directory, "learning.enc"), store = new SecureStore(path);
    await store.write({ preferences: [] }); const previous = await readFile(path);
    const controller = new AbortController(); controller.abort();
    await expect(store.write({ preferences: ["cancelled"] }, controller.signal)).rejects.toThrow();
    expect(await readFile(path)).toEqual(previous); expect(await readdir(directory)).toEqual(["learning.enc"]);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("encryption unavailability is not an empty account store", async () => {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-secure-unavailable-"));
  try {
    const store = new SecureStore(join(directory, "learning.enc")); await store.write({ attempts: [1,2,3] });
    vi.mocked(safeStorage.isEncryptionAvailable).mockReturnValueOnce(false);
    await expect(store.read()).rejects.toThrow("encryption is unavailable");
    expect(await store.read()).toEqual({ attempts: [1,2,3] });
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("cancellation after encrypted temporary I/O prevents its atomic publication", async () => {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-secure-midwrite-"));
  try {
    const path = join(directory,"learning.enc"), store = new SecureStore(path);
    await store.write({preferences:[]}); const previous = await readFile(path);
    const actual = await vi.importActual<typeof import("node:fs/promises")>("node:fs/promises");
    const controller = new AbortController();
    vi.mocked(open).mockImplementationOnce(async (path,flags,mode) => {
      const file = await actual.open(path,flags,mode); const sync=file.sync.bind(file);
      file.sync=async()=>{await sync();controller.abort();}; return file;
    });
    await expect(store.write({preferences:["cancelled"]},controller.signal)).rejects.toThrow();
    expect(await readFile(path)).toEqual(previous); expect(await readdir(directory)).toEqual(["learning.enc"]);
  } finally { await rm(directory,{recursive:true,force:true}); }
});
