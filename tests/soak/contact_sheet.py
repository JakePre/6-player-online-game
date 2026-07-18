"""Tile per-game render frames into one labeled contact sheet (#933).

The nightly sweep renders every catalog game and drops, per game, a mid-round
frame `<game>.png` and a one-line meta `<game>.meta` ("<elapsed> <duration>",
or "unknown <duration>"). This montages them into a single grid PNG — the whole
roster reviewable at a glance — and red-flags any game whose bot round ended
under `--flag-frac` of its full duration (the sumo 2-second-round regression,
#927, would have tripped it). Writes a markdown summary for the job summary.

    python tests/soak/contact_sheet.py --frames dir --out contact-sheet.png \
        [--flag-frac 0.4] [--summary summary.md] [--cols 6]
"""
import argparse
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CELL_W = 300          # each game's frame is scaled to this width
LABEL_H = 24
PAD = 6
BG = (26, 26, 30)
OK_BAR = (44, 46, 54)
FLAG_BAR = (150, 40, 40)


def _font():
    for name in ("DejaVuSans-Bold.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, 13)
        except OSError:
            continue
    return ImageFont.load_default()


def _read_meta(path: Path):
    """(elapsed|None, duration) from a '<elapsed> <duration>' meta line."""
    if not path.exists():
        return None, None
    parts = path.read_text().split()
    if len(parts) < 2:
        return None, None
    dur = float(parts[1])
    elapsed = None if parts[0] == "unknown" else float(parts[0])
    return elapsed, dur


def build(frames_dir: Path, out_png: Path, flag_frac: float, cols: int):
    games = sorted(p.stem for p in frames_dir.glob("*.png"))
    if not games:
        raise SystemExit(f"no <game>.png frames in {frames_dir}")
    font = _font()
    flagged = []
    cells = []
    for game in games:
        img = Image.open(frames_dir / f"{game}.png").convert("RGB")
        scale = CELL_W / img.width
        img = img.resize((CELL_W, int(img.height * scale)), Image.LANCZOS)
        elapsed, dur = _read_meta(frames_dir / f"{game}.meta")
        is_flag = elapsed is not None and dur and elapsed < flag_frac * dur
        if is_flag:
            flagged.append((game, elapsed, dur))
        if elapsed is None:
            label = f"{game}  (full {dur:.0f}s)" if dur else game
        else:
            label = f"{game}  {elapsed:.0f}/{dur:.0f}s"
            if is_flag:
                label = "! " + label
        cells.append((img, label, is_flag))

    cell_h = max(c[0].height for c in cells) + LABEL_H
    rows = (len(cells) + cols - 1) // cols
    sheet = Image.new(
        "RGB",
        (cols * (CELL_W + PAD) + PAD, rows * (cell_h + PAD) + PAD),
        BG,
    )
    draw = ImageDraw.Draw(sheet)
    for i, (img, label, is_flag) in enumerate(cells):
        cx = PAD + (i % cols) * (CELL_W + PAD)
        cy = PAD + (i // cols) * (cell_h + PAD)
        draw.rectangle([cx, cy, cx + CELL_W, cy + LABEL_H], fill=FLAG_BAR if is_flag else OK_BAR)
        draw.text((cx + 5, cy + 5), label, fill=(240, 240, 240), font=font)
        sheet.paste(img, (cx, cy + LABEL_H))
    out_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_png)
    return games, flagged


def summary_md(games, flagged, flag_frac):
    lines = [f"### Nightly contact sheet — {len(games)} games",
             "",
             f"Fast-round flag: bot round ended under {flag_frac:.0%} of its duration.",
             ""]
    if flagged:
        lines.append(f"** {len(flagged)} fast-round flag(s):**")
        for game, elapsed, dur in sorted(flagged, key=lambda f: f[1] / f[2]):
            lines.append(f"- `{game}` — {elapsed:.1f}s of {dur:.0f}s ({elapsed / dur:.0%})")
    else:
        lines.append("No fast-round flags. ✅")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--flag-frac", type=float, default=0.4)
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--summary", type=Path, default=None)
    args = ap.parse_args()
    games, flagged = build(args.frames, args.out, args.flag_frac, args.cols)
    md = summary_md(games, flagged, args.flag_frac)
    print(md)
    if args.summary:
        args.summary.write_text(md, encoding="utf-8")
    print(f"\ncontact sheet -> {args.out} ({len(games)} games, {len(flagged)} flagged)")


if __name__ == "__main__":
    main()
