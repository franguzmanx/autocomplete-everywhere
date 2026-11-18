import { mkdtemp, writeFile, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import { readLibraryImport } from "../src/main/library-import";

test("imports only bounded UTF-8 text and Markdown selected by the main process", async () => {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-import-"));
  try {
    const path = join(directory, "prices.md"); await writeFile(path, "# Pricing\nPlan: 90");
    expect(await readLibraryImport(path)).toEqual({ text: "# Pricing\nPlan: 90", name: "prices.md" });
    const pdf = join(directory, "document.pdf"); await writeFile(pdf, "not a document");
    await expect(readLibraryImport(pdf)).rejects.toThrow(/text|Markdown/i);
    await writeFile(path, "x".repeat(48_001)); await expect(readLibraryImport(path)).rejects.toThrow(/large/i);
    await writeFile(path, Buffer.from([0xff, 0xfe])); await expect(readLibraryImport(path)).rejects.toThrow(/UTF-8/i);
    await writeFile(path, "hello\0world"); await expect(readLibraryImport(path)).rejects.toThrow(/text/i);
    const link = join(directory, "link.txt"); await symlink(path, link); await expect(readLibraryImport(link)).rejects.toThrow();
  } finally { await rm(directory, { recursive: true, force: true }); }
});
