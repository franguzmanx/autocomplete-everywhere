import { mkdir, open, readFile, rename, rm } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { dirname } from "node:path";

import { safeStorage } from "electron";

export class SecureStore {
  constructor(private readonly filePath: string) {}

  async write(value: unknown, signal?: AbortSignal): Promise<void> {
    signal?.throwIfAborted();
    if (!safeStorage.isEncryptionAvailable()) {
      throw new Error("Operating-system credential encryption is unavailable");
    }

    signal?.throwIfAborted();
    const encrypted = safeStorage.encryptString(JSON.stringify(value));
    await mkdir(dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.${randomUUID()}.tmp`;
    try {
      signal?.throwIfAborted();
      const file = await open(temporaryPath, "wx", 0o600);
      try { await file.writeFile(encrypted); await file.sync(); }
      finally { await file.close(); }
      signal?.throwIfAborted();
      await rename(temporaryPath, this.filePath);
    } finally { await rm(temporaryPath, { force: true }); }
  }

  async read<T>(): Promise<T | null> {
    if (!safeStorage.isEncryptionAvailable()) {
      throw new Error("Operating-system credential encryption is unavailable");
    }

    try {
      const encrypted = await readFile(this.filePath);
      return JSON.parse(safeStorage.decryptString(encrypted)) as T;
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code === "ENOENT") return null;
      throw error;
    }
  }
}
