import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { basename, extname } from "node:path";

/** The path must come from the main-process file dialog, never from IPC. */
export async function readLibraryImport(path: string): Promise<{ text: string; name: string }> {
  if (![".txt", ".md"].includes(extname(path).toLowerCase())) throw new Error("Choose a plain text or Markdown file (.txt or .md).");
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await file.stat();
    if (!stat.isFile()) throw new Error("Choose a regular text file.");
    if (stat.size > 48_000) throw new Error("This file is too large. Use up to 12,000 characters (48 KB).");
    const buffer = Buffer.alloc(48_001);
    const { bytesRead } = await file.read(buffer, 0, buffer.length, 0);
    if (bytesRead > 48_000) throw new Error("This file is too large.");
    let text: string;
    try { text = new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, bytesRead)); }
    catch { throw new Error("Save the file as UTF-8 text before importing."); }
    if (text.includes("\0") || !text.trim()) throw new Error("Choose a nonempty text file.");
    if (text.length > 12_000) throw new Error("This file is too large. Use up to 12,000 characters.");
    return { text, name: basename(path).slice(0, 255) };
  } finally { await file.close(); }
}
