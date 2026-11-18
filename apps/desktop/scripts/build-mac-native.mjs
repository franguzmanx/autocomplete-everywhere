import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const native = fileURLToPath(new URL("../../../native/macos/", import.meta.url));
// The pinned static archive is the sole SQLCipher search path for native builds.
const pkgConfigPath = execFileSync("/bin/bash", [`${native}scripts/build-sqlcipher.sh`], {
  encoding: "utf8", stdio: ["ignore", "pipe", "inherit"],
}).trim();
const env = { ...process.env, PKG_CONFIG_PATH: pkgConfigPath };
for (const product of ["AutocompleteHelper", "AutocompleteContextService", "AutocompleteSettings"]) {
  const args = ["build", "--package-path", native, "-c", "release", "--product", product];
  if (product === "AutocompleteSettings") args.push("--build-system", "xcode");
  execFileSync("swift", args, { env, stdio: "inherit" });
}
const service = `${native}.build/release/AutocompleteContextService`;
const dependencies = execFileSync("/usr/bin/otool", ["-L", service], { encoding: "utf8" });
for (const line of dependencies.split("\n").slice(1).filter((line) => line.trim())) {
  const dependency = line.trim().split(" ")[0];
  if (!dependency.startsWith("/System/Library/") && !dependency.startsWith("/usr/lib/")) {
    throw new Error(`Context service contains an unbundled dependency: ${dependency}`);
  }
}
execFileSync(process.execPath, [fileURLToPath(new URL("./package-native-settings.mjs", import.meta.url))], { stdio: "inherit" });
