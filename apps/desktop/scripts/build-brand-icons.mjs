import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const output = join(root, "build");
mkdirSync(output, { recursive: true });
// Icon Composer owns the layers and material. actool produces both the
// layered macOS resource and the system-rendered ICNS in the same build.
execFileSync("xcrun", [
  "actool", join(root, "resources/brand/AutocompleteEverywhere.icon"),
  "--compile", output, "--platform", "macosx",
  "--minimum-deployment-target", "14.0", "--app-icon", "AutocompleteEverywhere",
  "--output-partial-info-plist", join(output, "icon-info.plist"),
  "--output-format", "human-readable-text",
], { stdio: "inherit" });
