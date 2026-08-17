#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP="$ROOT/dist/Teams Meeting Status for Home Assistant.app"
CONTENTS="$APP/Contents"
cd "$ROOT"
swift build -c release
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp .build/release/TeamsMeetingStatus "$CONTENTS/MacOS/TeamsMeetingStatus"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>TeamsMeetingStatus</string>
<key>CFBundleIdentifier</key><string>dk.bachjessen.teamsmeetingstatus</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>TeamsMeetingStatus</string>
<key>CFBundleDisplayName</key><string>Teams Meeting Status for Home Assistant</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APP_VERSION#v}</string>
<key>CFBundleVersion</key><string>${GITHUB_RUN_NUMBER:-1}</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
plutil -lint "$CONTENTS/Info.plist"
if command -v codesign >/dev/null 2>&1; then codesign --force --deep --sign - "$APP"; fi
echo "Built $APP"
