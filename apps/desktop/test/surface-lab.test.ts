import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { describe, expect, test } from "vitest";

describe("surface lab", () => {
  test("ships a local-only matrix for the supported writing shapes", async () => {
    const html = await readFile(
      join(import.meta.dirname, "../dev/surface-lab.html"),
      "utf8",
    );

    expect(html).toContain('data-surface="single-line"');
    expect(html).toContain('data-surface="wrapped-textarea"');
    expect(html).toContain('data-surface="auto-grow"');
    expect(html).toContain('data-surface="contenteditable"');
    expect(html).toContain('data-surface="context-subject"');
    expect(html).toContain('data-surface="context-body"');
    expect(html).toContain('type="password"');
    expect(html).toContain("navigator.clipboard.writeText");
    expect(html).not.toMatch(/https?:\/\//);
  });
});
