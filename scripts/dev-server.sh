#!/usr/bin/env bash
# Launches the Party Rush dedicated server locally — headless, no Docker or
# export needed — so you can point a client at 127.0.0.1 and try the game.
# For production deployment see server/deploy/README.md instead.
#
# Usage:
#   scripts/dev-server.sh [server args...]
#
# Server args are forwarded as-is to src/server/server_host.gd, e.g.:
#   scripts/dev-server.sh --port=9000
#   scripts/dev-server.sh --fake-lag=80 --fake-loss=0.05   # simulate a bad connection
#
# Godot binary resolution: $GODOT env var, then `godot4`/`godot` on PATH,
# then the macOS app bundle default install location.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

find_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		echo "$GODOT"
	elif command -v godot4 >/dev/null 2>&1; then
		echo "godot4"
	elif command -v godot >/dev/null 2>&1; then
		echo "godot"
	elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
		echo "/Applications/Godot.app/Contents/MacOS/Godot"
	fi
}

GODOT_BIN="$(find_godot)"
if [[ -z "$GODOT_BIN" ]]; then
	echo "error: no Godot binary found. Install Godot 4.4.x, or set GODOT=/path/to/godot." >&2
	exit 1
fi

echo "using Godot binary: $GODOT_BIN"
echo "starting dedicated server (watch for the 'SERVER READY' line below)..."
exec "$GODOT_BIN" --headless --path . -- --server "$@"
