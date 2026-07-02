#!/usr/bin/env bash
# Launches the Party Rush client locally — no export needed, runs straight
# from source via the Godot editor binary. Run it once per window you want
# open (e.g. twice, to test a 2-player match against yourself).
#
# Once the main menu appears: Host a room, or Join using a room code. To
# point at a local dev server (scripts/dev-server.sh) instead of the
# default, set the server address to 127.0.0.1 via Settings > Network, or
# the main menu's Advanced fold-out for a one-off session.
#
# Usage:
#   scripts/dev-client.sh
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
exec "$GODOT_BIN" --path . "$@"
