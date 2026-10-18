#!/bin/bash
# Renders the README screenshots into docs/screenshots from the demo fixture
# in macos/fixtures/demo — a recorded session on a throwaway project plus a
# made-up menu snapshot — so no real session ever ends up in a screenshot.
#
#   macos/scripts/screenshots.sh
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$MACOS_DIR/.." && pwd)"
FIXTURE="$MACOS_DIR/fixtures/demo"
OUT="$REPO_DIR/docs/screenshots"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift build --package-path "$MACOS_DIR" >/dev/null
BIN="$(swift build --package-path "$MACOS_DIR" --show-bin-path)/ClaudeProfilerBar"

# The snapshot template keeps every time as seconds before now, so "4m ago"
# reads the same whenever the screenshots are rendered.
node - "$FIXTURE" "$WORK" <<'EOF'
const fs = require("node:fs");
const path = require("node:path");
const [fixture, work] = process.argv.slice(2);
const id = fs.readFileSync(path.join(fixture, "session-id"), "utf8").trim();
const now = Date.now();
const at = (s) => (typeof s === "number" && s <= 0 ? now + s * 1000 : s);
const snapshot = JSON.parse(fs.readFileSync(path.join(fixture, "snapshot.template.json"), "utf8").replaceAll("DEMO_SESSION_ID", id));
snapshot.at = now;
for (const s of snapshot.sessions) {
  s.startedAt = at(s.startedAt);
  s.lastActivityAt = at(s.lastActivityAt);
  if (s.activity) s.activity.since = at(s.activity.since);
}
fs.writeFileSync(path.join(work, "snapshot.json"), JSON.stringify(snapshot));
fs.copyFileSync(path.join(fixture, "profile.json"), path.join(work, `${id}.profile.json`));
EOF

mkdir -p "$OUT"
shot() {
  local name="$1"; shift
  "$BIN" --render-png "$OUT/$name.png" --fixture "$WORK" "$@"
  echo "› $name.png"
}

shot menu
shot menu-dark --dark
for tab in overview tools model timeline context hooks subagents; do
  shot "detail-$tab" --tab "$tab"
done
shot detail-overview-dark --tab overview --dark
