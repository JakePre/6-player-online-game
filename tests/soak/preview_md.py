#!/usr/bin/env python3
"""Generate a browsable HTML preview page from per-game render frames.

Takes a directory of <game>.png frames (from render_game.py --contact-frame)
and produces an index.html that embeds each image, sorted alphabetically.

Usage:
    python tests/soak/preview_md.py --frames dir --out index.html

The output is designed to be deployed as a GitHub Pages site (via
upload-pages-artifact): the HTML and images sit side-by-side in the
same directory, so relative img references resolve.
"""
from __future__ import annotations

import argparse
from html import escape
from pathlib import Path


def build(frames_dir: Path, out_path: Path) -> list[str]:
    games = sorted(p.stem for p in frames_dir.glob("*.png"))
    if not games:
        raise SystemExit(f"no <game>.png frames in {frames_dir}")

    parts = [
        "<!DOCTYPE html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        "<title>Minigame Previews</title>",
        "<style>",
        "body { font-family: system-ui, sans-serif; max-width: 960px; margin: 0 auto; padding: 1em; }",
        "img { max-width: 100%; height: auto; border: 1px solid #ccc; border-radius: 4px; }",
        "h2 code { font-size: 1em; }",
        "footer { margin-top: 2em; font-size: 0.85em; color: #666; }",
        "</style>",
        "</head>",
        "<body>",
        "<h1>Minigame Previews</h1>",
        "<p>Auto-generated from in-game renders. Each image is a mid-round frame",
        "captured with practice bots playing the actual game.</p>",
        f"<p><strong>{len(games)} games</strong></p>",
    ]

    for game in games:
        safe = escape(game)
        parts.append(f'<h2><code>{safe}</code></h2>')
        parts.append(f'<p><img src="{escape(game)}.png" alt="{safe}"></p>')

    parts.append(f"<footer>Preview page &mdash; {len(games)} games</footer>")
    parts.extend(["</body>", "</html>"])

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
    return games


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate minigame preview HTML page")
    ap.add_argument("--frames", required=True, type=Path, help="directory of <game>.png frames")
    ap.add_argument("--out", default="index.html", type=Path, help="output HTML path")
    args = ap.parse_args()
    games = build(args.frames, args.out)
    print(f"preview page -> {args.out} ({len(games)} games)")


if __name__ == "__main__":
    main()