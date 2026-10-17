#!/bin/bash
# Packs "Claude Profiler.app" into a disk image: the app next to a shortcut to
# Applications, so installing it is dragging one onto the other.
#
#   macos/scripts/make-dmg.sh <path to the .app> <output.dmg>
#
# With SIGN_IDENTITY set the image is signed with it, which a notarized image
# needs; without, it is left unsigned.
set -euo pipefail

app="${1:?usage: $0 <Claude Profiler.app> <output.dmg>}"
out="${2:?usage: $0 <Claude Profiler.app> <output.dmg>}"
[[ -d "$app" ]] || { echo "error: $app is not an app bundle" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
# ditto, not cp: it keeps the bundle's symlinks, signature and stapled ticket.
ditto "$app" "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"

rm -f "$out"
hdiutil create -quiet -volname "Claude Profiler" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$out"
fi
echo "✓ $out"
