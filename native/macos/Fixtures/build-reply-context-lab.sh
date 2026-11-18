#!/bin/sh
set -eu
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
qa_dir=$(mktemp -d /tmp/autocompletion-reply-context.XXXXXX)
qa_app="$qa_dir/Autocomplete Everywhere Reply Context QA.app"
mkdir -p "$qa_app/Contents/MacOS"
swiftc -target "$(uname -m)-apple-macos14.0" -parse-as-library "$fixture_dir/ReplyContextLab.swift" -o "$qa_app/Contents/MacOS/ReplyContextLab"
cat > "$qa_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.autocompletion.qa.replycontext</string>
<key>CFBundleName</key><string>Autocomplete Everywhere Reply Context QA</string>
<key>CFBundleExecutable</key><string>ReplyContextLab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf '%s\n' "$qa_app"
