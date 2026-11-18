import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const desktopDirectory = fileURLToPath(new URL("..", import.meta.url));

test("the local mac package can use an installed signing identity", async () => {
  const packageJson = JSON.parse(
    await readFile(new URL("../package.json", import.meta.url), "utf8"),
  ) as {
    scripts: Record<string, string>;
    build: { mac: { identity?: string | null } };
  };

  expect(packageJson.build.mac).not.toHaveProperty("identity");
  expect(packageJson.scripts["package:mac"]).toContain(
    "--config.mac.timestamp=none",
  );
});

test(
  "the packaged main bundle does not load workspace TypeScript at runtime",
  async () => {
    await execFileAsync("bun", ["run", "build"], {
      cwd: desktopDirectory,
      env: process.env,
    });

    const mainBundle = await readFile(
      new URL("../out/main/index.js", import.meta.url),
      "utf8",
    );

    expect(mainBundle).not.toContain('from "@autocompletion/protocol"');
  },
  15_000,
);
