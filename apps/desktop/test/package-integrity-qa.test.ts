import { execFile } from "node:child_process";
import {
  appendFile,
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { afterEach, expect, test } from "vitest";

// codesign and plutil exist only on macOS. The signature and bundle tests are
// skipped there, not passed: a Linux run never counts as package
// verification. The package.json assertion below is portable and always runs.
const macOnly = test.skipIf(process.platform !== "darwin");

const execFileAsync = promisify(execFile);
const desktopDirectory = fileURLToPath(new URL("..", import.meta.url));
const verifierPath = join(
  desktopDirectory,
  "scripts",
  "verify-mac-package.mjs",
);
const temporaryDirectories: string[] = [];

async function createSignedApp(
  bundleIdentifier = "com.autocompletion.desktop",
): Promise<{ appPath: string; helperPath: string; infoPath: string }> {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-package-qa-"));
  temporaryDirectories.push(directory);

  const appPath = join(directory, "AutocompleteEverywhere.app");
  const contentsPath = join(appPath, "Contents");
  const mainExecutablePath = join(contentsPath, "MacOS", "Autocomplete Everywhere");
  const helperPath = join(
    contentsPath,
    "Resources",
    "native",
    "AutocompleteHelper",
  );
  const infoPath = join(contentsPath, "Info.plist");

  await mkdir(join(contentsPath, "MacOS"), { recursive: true });
  await mkdir(join(contentsPath, "Resources", "native"), { recursive: true });
  await copyFile("/usr/bin/true", mainExecutablePath);
  await copyFile("/usr/bin/true", helperPath);
  const contextService = join(contentsPath, "Resources", "native", "AutocompleteContextService");
  await copyFile("/usr/bin/true", contextService);
  await chmod(contextService, 0o755);
  await writeFile(join(contentsPath, "Resources", "native", "SQLCipher-LICENSE"), "SQLCipher test fixture license");
  await execFileAsync("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", contextService]);
  await chmod(mainExecutablePath, 0o755);
  await chmod(helperPath, 0o755);
  const nativeUI = join(contentsPath, "Resources", "native", "AutocompleteEverywhere.app");
  await mkdir(join(nativeUI, "Contents", "MacOS"), { recursive: true });
  await mkdir(join(nativeUI, "Contents", "Resources", "KeyboardShortcuts_KeyboardShortcuts.bundle"), { recursive: true });
  await copyFile("/usr/bin/true", join(nativeUI, "Contents", "MacOS", "AutocompleteEverywhere"));
  await writeFile(join(nativeUI, "Contents", "Info.plist"), `<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>AutocompleteEverywhere</string><key>CFBundleIdentifier</key><string>com.autocompletion.settings</string><key>CFBundleIconName</key><string>AutocompleteEverywhere</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string></dict></plist>`);
  await writeFile(
    infoPath,
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Autocomplete Everywhere</string>
  <key>CFBundleIdentifier</key><string>${bundleIdentifier}</string>
  <key>CFBundleName</key><string>Autocomplete Everywhere</string>
  <key>CFBundleIconName</key><string>AutocompleteEverywhere</string><key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
`,
  );

  await writeFile(join(contentsPath, "Resources", "Assets.car"), "fixture");
  await writeFile(join(nativeUI, "Contents", "Resources", "Assets.car"), "fixture");
  await execFileAsync("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", nativeUI]);
  await execFileAsync("/usr/bin/codesign", [
    "--force",
    "--sign",
    "-",
    "--timestamp=none",
    helperPath,
  ]);
  await execFileAsync("/usr/bin/codesign", [
    "--force",
    "--deep",
    "--sign",
    "-",
    "--timestamp=none",
    appPath,
  ]);

  return { appPath, helperPath, infoPath };
}

async function runVerifier(appPath: string) {
  try {
    const result = await execFileAsync(process.execPath, [verifierPath, appPath], {
      cwd: desktopDirectory,
    });
    return { exitCode: 0, stderr: result.stderr, stdout: result.stdout };
  } catch (error) {
    const result = error as {
      code: number;
      stderr: string;
      stdout: string;
    };
    return {
      exitCode: result.code,
      stderr: result.stderr,
      stdout: result.stdout,
    };
  }
}

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) =>
      rm(directory, { force: true, recursive: true }),
    ),
  );
});

macOnly("accepts a packaged app with the expected bundle and valid signatures", async () => {
  const { appPath } = await createSignedApp();

  const result = await runVerifier(appPath);

  expect(result).toMatchObject({
    exitCode: 0,
    stderr: "",
    stdout: expect.stringContaining("macOS package integrity verified"),
  });
});

macOnly("fails clearly when the packaged app is missing", async () => {
  const directory = await mkdtemp(join(tmpdir(), "autocompletion-package-qa-"));
  temporaryDirectories.push(directory);

  const result = await runVerifier(join(directory, "AutocompleteEverywhere.app"));

  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("Packaged app not found");
});

macOnly("fails clearly when AutocompleteHelper is missing", async () => {
  const { appPath, helperPath } = await createSignedApp();
  await rm(helperPath);

  const result = await runVerifier(appPath);

  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("AutocompleteHelper not found");
});

macOnly("rejects an unexpected bundle identifier", async () => {
  const { appPath } = await createSignedApp("com.example.wrong");

  const result = await runVerifier(appPath);

  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain(
    'Unexpected bundle identifier "com.example.wrong"; expected "com.autocompletion.desktop"',
  );
});

macOnly("rejects a helper whose signed contents were changed", async () => {
  const { appPath, helperPath } = await createSignedApp();
  await appendFile(helperPath, "tampered");

  const result = await runVerifier(appPath);

  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("AutocompleteHelper signature is invalid");
});

macOnly("rejects an app whose signed contents were changed", async () => {
  const { appPath, infoPath } = await createSignedApp();
  const info = await readFile(infoPath, "utf8");
  await writeFile(infoPath, info.replace("</dict>", "<key>Changed</key><true/></dict>"));

  const result = await runVerifier(appPath);

  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("AutocompleteEverywhere.app signature is invalid");
});

test("removes Electron's unused privacy usage descriptions", async () => {
  const packageJson = JSON.parse(
    await readFile(new URL("../package.json", import.meta.url), "utf8"),
  ) as {
    build: { mac: { extendInfo?: Record<string, unknown> } };
  };

  expect(packageJson.build.mac.extendInfo).toEqual({
    CFBundleDisplayName: "Autocomplete Everywhere",
    CFBundleIconName: "AutocompleteEverywhere",
    NSAudioCaptureUsageDescription: null,
    NSBluetoothAlwaysUsageDescription: null,
    NSBluetoothPeripheralUsageDescription: null,
    NSCameraUsageDescription: null,
    NSMicrophoneUsageDescription: null,
  });
});

macOnly("rejects a missing context service", async () => {
  const { appPath } = await createSignedApp();
  await rm(join(appPath, "Contents", "Resources", "native", "AutocompleteContextService"));
  const result = await runVerifier(appPath);
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("AutocompleteContextService not found");
});

macOnly("rejects a context service whose signed contents changed", async () => {
  const { appPath } = await createSignedApp();
  await appendFile(join(appPath, "Contents", "Resources", "native", "AutocompleteContextService"), "tampered");
  const result = await runVerifier(appPath);
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("AutocompleteContextService signature is invalid");
});

macOnly("requires the bundled SQLCipher license", async () => {
  const { appPath } = await createSignedApp();
  await rm(join(appPath, "Contents", "Resources", "native", "SQLCipher-LICENSE"));
  const result = await runVerifier(appPath);
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("SQLCipher-LICENSE");
});

macOnly("rejects a context service linked to a Homebrew dylib", async () => {
  const { appPath } = await createSignedApp();
  const root = join(appPath, "..");
  const librarySource = join(root, "dependency.c");
  const mainSource = join(root, "service.c");
  const library = join(root, "libfixture.dylib");
  await writeFile(librarySource, "int dependency(void) { return 0; }");
  await writeFile(mainSource, "int dependency(void); int main(void) { return dependency(); }");
  await execFileAsync("/usr/bin/xcrun", ["clang", "-dynamiclib", librarySource, "-Wl,-install_name,/opt/homebrew/lib/libfixture.dylib", "-o", library]);
  await execFileAsync("/usr/bin/xcrun", ["clang", mainSource, library, "-o", join(appPath, "Contents", "Resources", "native", "AutocompleteContextService")]);
  const result = await runVerifier(appPath);
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("unbundled dependency: /opt/homebrew/lib/libfixture.dylib");
});
