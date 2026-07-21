#!/usr/bin/env python3
"""Generate a browsable Markdown preview page from per-game render frames.

Takes a directory of <game>.png frames (from render_game.py --contact-frame)
and produces an index.md that embeds each image, sorted alphabetically.

Usage:
    python tests/soak/preview_md.py --frames dir --out index.md

The output is designed to be deployed as a GitHub Pages site (via
upload-pages-artifact): the markdown and images sit side-by-side in the
same directory, so relative img references resolve.
"""
from __future__ import annotations

import argparse
from pathlib import Path


def build(frames_dir: Path, out_path: Path) -> list[str]:
    games = sorted(p.stem for p in frames_dir.glob("*.png"))
    if not games:
        raise SystemExit(f"no <game>.png frames in {frames_dir}")

    lines = [
        "# Minigame Previews",
        "",
        "Auto-generated from in-game renders. Each image is a mid-round frame",
        "captured with practice bots playing the actual game.",
        "",
        f"**{len(games)} games**",
        "",
    ]

    for game in games:
        lines.append(f"## `{game}`")
        lines.append("")
        lines.append(f"![{game}]({game}.png)")
        lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    return games


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate minigame preview Markdown page")
    ap.add_argument("--frames", required=True, type=Path, help="directory of <game>.png frames")
    ap.add_argument("--out", default="index.md", type=Path, help="output Markdown path")
    args = ap.parse_args()
    games = build(args.frames, args.out)
    print(f"preview page -> {args.out} ({len(games)} games)")


if __name__ == "__main__":
    main()