#!/bin/bash
# Builds "Claude Profiler.app": the SwiftUI menu bar shell plus the session
# collector compiled into a Node single executable, so the app needs no Node
# on the machine it runs on.
#
#   macos/scripts/bundle.sh            → macos/build/Claude Profiler.app
#   SIGN_IDENTITY="Developer ID Application: …" macos/scripts/bundle.sh
#                                      → signed for distribution (hardened runtime)
#
# Needs Node >= 25.5 (for `node --build-sea`), pnpm and the Swift toolchain
# (the Command Line Tools are enough). Without SIGN_IDENTITY the app is signed ad
# hoc: it runs on this machine; on another one Gatekeeper asks once.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$MACOS_DIR/.." && pwd)"
BUILD_DIR="$MACOS_DIR/build"
APP="$BUILD_DIR/Claude Profiler.app"
VERSION="$(node -p "require('$REPO_DIR/package.json').version")"

node_major="$(node -p 'process.versions.node.split(".")[0]')"
node_minor="$(node -p 'process.versions.node.split(".")[1]')"
if (( node_major < 25 || (node_major == 25 && node_minor < 5) )); then
  echo "error: node --build-sea needs Node >= 25.5 (found $(node --version))" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/sea"

echo "› bundling the collector"
(cd "$REPO_DIR" && pnpm exec esbuild src/live/main.ts \
  --bundle --platform=node --format=cjs --target=node22 \
  --log-level=warning --log-override:empty-import-meta=silent \
  --define:PROFILER_VERSION="\"$VERSION\"" \
  --outfile="$BUILD_DIR/sea/live.cjs")

cat > "$BUILD_DIR/sea/sea-config.json" <<EOF
{
  "main": "$BUILD_DIR/sea/live.cjs",
  "output": "$BUILD_DIR/sea/cprof-live",
  "disableExperimentalSEAWarning": true
}
EOF
echo "› building the collector executable"
node --build-sea "$BUILD_DIR/sea/sea-config.json" >/dev/null

echo "› building the Swift app"
swift build --package-path "$MACOS_DIR" -c release
BIN_DIR="$(swift build --package-path "$MACOS_DIR" -c release --show-bin-path)"

echo "› assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeProfilerBar" "$APP/Contents/MacOS/ClaudeProfilerBar"
cp "$BUILD_DIR/sea/cprof-live" "$APP/Contents/Resources/cprof-live"
cp "$MACOS_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$MACOS_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Profiler</string>
  <key>CFBundleDisplayName</key><string>Claude Profiler</string>
  <key>CFBundleIdentifier</key><string>io.github.softjey.claude-profiler</string>
  <key>CFBundleExecutable</key><string>ClaudeProfilerBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Inside out: the embedded executable first, then the bundle that seals it.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "› signing as $SIGN_IDENTITY"
  # Hardened runtime and a secure timestamp are what notarization requires.
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" \
    --entitlements "$MACOS_DIR/scripts/collector.entitlements" "$APP/Contents/Resources/cprof-live"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
  echo "› signing (ad hoc)"
  codesign --force --sign - "$APP/Contents/Resources/cprof-live"
  codesign --force --sign - "$APP"
fi

rm -rf "$BUILD_DIR/sea"
echo "✓ $APP"
