import { execFileSync } from "node:child_process";
import { constants } from "node:fs";
import { access, stat } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const expectedBundleIdentifier = "com.autocompleteeverywhere.desktop";
const defaultAppPath = fileURLToPath(
  new URL("../dist/mac-arm64/AutocompleteEverywhere.app", import.meta.url),
);

async function requireDirectory(path, description) {
  try {
    if (!(await stat(path)).isDirectory()) {
      throw new Error("not a directory");
    }
  } catch {
    throw new Error(`${description} not found: ${path}`);
  }
}

async function requireExecutable(path, description) {
  try {
    if (!(await stat(path)).isFile()) {
      throw new Error("not a file");
    }
    await access(path, constants.X_OK);
  } catch {
    throw new Error(`${description} not found or not executable: ${path}`);
  }
}

function run(command, args, failureMessage) {
  try {
    return execFileSync(command, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    const stderr = error?.stderr?.toString().trim();
    throw new Error(stderr ? `${failureMessage}: ${stderr}` : failureMessage);
  }
}

async function verifyPackage(appPath) {
  await requireDirectory(appPath, "Packaged app");

  const helperPath = join(
    appPath,
    "Contents",
    "Resources",
    "native",
    "AutocompleteHelper",
  );
  await requireExecutable(helperPath, "AutocompleteHelper");

  const contextService = join(appPath, "Contents", "Resources", "native", "AutocompleteContextService");
  await requireExecutable(contextService, "AutocompleteContextService");
  await access(join(appPath, "Contents", "Resources", "native", "SQLCipher-LICENSE"), constants.R_OK);
  const dependencies = run("/usr/bin/otool", ["-L", contextService], "Cannot inspect context service linkage");
  for (const line of dependencies.split("\n").slice(1).filter((line) => line.trim())) {
    const dependency = line.trim().split(" ")[0];
    if (!dependency.startsWith("/System/Library/") && !dependency.startsWith("/usr/lib/")) {
      throw new Error(`Context service contains an unbundled dependency: ${dependency}`);
    }
  }
  run("/usr/bin/codesign", ["--verify", "--strict", "--verbose=2", contextService], "AutocompleteContextService signature is invalid");

  const nativeUI = join(appPath, "Contents", "Resources", "native", "AutocompleteEverywhere.app");
  await requireExecutable(join(nativeUI, "Contents", "MacOS", "AutocompleteEverywhere"), "Native settings");
  await requireDirectory(join(nativeUI, "Contents", "Resources", "KeyboardShortcuts_KeyboardShortcuts.bundle"), "Native shortcut resources");
  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", nativeUI], "Native settings signature is invalid");
  const infoPath = join(appPath, "Contents", "Info.plist");
  for (const bundle of [appPath, nativeUI]) {
    await access(join(bundle, "Contents", "Resources", "Assets.car"), constants.R_OK);
    const iconName = run("/usr/bin/plutil", ["-extract", "CFBundleIconName", "raw", "-o", "-",
      join(bundle, "Contents", "Info.plist")], "Cannot read native icon name");
    if (iconName !== "AutocompleteEverywhere") throw new Error(`Missing AutocompleteEverywhere native icon in ${bundle}`);
  }
  const bundleIdentifier = run(
    "/usr/bin/plutil",
    ["-extract", "CFBundleIdentifier", "raw", "-o", "-", infoPath],
    `Cannot read bundle identifier from ${infoPath}`,
  );
  if (bundleIdentifier !== expectedBundleIdentifier) {
    throw new Error(
      `Unexpected bundle identifier "${bundleIdentifier}"; expected "${expectedBundleIdentifier}"`,
    );
  }

  run(
    "/usr/bin/codesign",
    ["--verify", "--strict", "--verbose=2", helperPath],
    "AutocompleteHelper signature is invalid",
  );
  run(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", "--verbose=2", appPath],
    "AutocompleteEverywhere.app signature is invalid",
  );
}

const appPath = process.argv[2] ?? defaultAppPath;

try {
  await verifyPackage(appPath);
  process.stdout.write(`macOS package integrity verified: ${appPath}\n`);
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`package:mac:qa: ${message}\n`);
  process.exitCode = 1;
}
