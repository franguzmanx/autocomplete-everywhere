#!/bin/zsh
set -euo pipefail
SCENE_DIR="${0:A:h}"
SCENE_APP="$SCENE_DIR/build/Autocomplete Everywhere Scene Lab.app"
mkdir -p "$SCENE_APP/Contents/MacOS"
xcrun swiftc -parse-as-library -framework AppKit "$SCENE_DIR/main.swift" -o "$SCENE_APP/Contents/MacOS/SceneLab"
cat > "$SCENE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.autocompletion.SceneLab</string>
<key>CFBundleName</key><string>Autocomplete Everywhere Scene Lab</string>
<key>CFBundleExecutable</key><string>SceneLab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$SCENE_APP"
print -r -- "$SCENE_APP"
