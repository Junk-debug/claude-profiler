#!/bin/bash
# Redraws macos/Resources/AppIcon.icns from make-icon.swift. Only needed when
# the icon changes; the .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."
set_dir="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$set_dir"
mkdir -p Resources
iconutil -c icns "$set_dir" -o Resources/AppIcon.icns
echo "✓ macos/Resources/AppIcon.icns"
