import { copyFile, cp, mkdir, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
const bundle=fileURLToPath(new URL("../native-ui/AutocompleteEverywhere.app/",import.meta.url));
await rm(bundle,{recursive:true,force:true});
await mkdir(bundle+"Contents/MacOS",{recursive:true});
await copyFile(fileURLToPath(new URL("../../../native/macos/.build/apple/Products/Release/AutocompleteSettings",import.meta.url)),bundle+"Contents/MacOS/AutocompleteEverywhere");
await mkdir(bundle+"Contents/Resources",{recursive:true});
await cp(fileURLToPath(new URL("../../../native/macos/.build/apple/Products/Release/KeyboardShortcuts_KeyboardShortcuts.bundle",import.meta.url)),bundle+"Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle",{recursive:true});
await copyFile(fileURLToPath(new URL("../build/AutocompleteEverywhere.icns",import.meta.url)),bundle+"Contents/Resources/AutocompleteEverywhere.icns");
await copyFile(fileURLToPath(new URL("../build/Assets.car",import.meta.url)),bundle+"Contents/Resources/Assets.car");
await writeFile(bundle+"Contents/Info.plist",`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.autocompletion.settings</string>
<key>CFBundleName</key><string>Autocomplete Everywhere</string>
<key>CFBundleDisplayName</key><string>Autocomplete Everywhere</string>
<key>CFBundleExecutable</key><string>AutocompleteEverywhere</string>
<key>CFBundleIconFile</key><string>AutocompleteEverywhere</string>
<key>CFBundleIconName</key><string>AutocompleteEverywhere</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>`);
