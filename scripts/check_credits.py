#!/usr/bin/env python3
"""Integrity check for assets/CREDITS.md (#951).

Parallel asset-landing PRs have twice concatenated two table rows onto one
line during a merge (no trailing newline between them) — a broken table that
feeds the in-game credits screen at runtime (M7-04), so it's player-visible.
This is deliberately narrow: it catches the exact defect class that has
recurred, not a general markdown-table linter, because the file's tables are
loosely (but legitimately) formatted — column counts vary row to row by
design (e.g. some rows fold a Source URL into the License cell instead of a
separate column).

Checks, each scoped to `|`-prefixed table rows only:
1. No row looks like two rows concatenated (a mid-line "| ... | X" pattern
   immediately followed by another "| Name |" that isn't the row's own
   trailing cell — signature: a cell ending in a bare "—" or "-" immediately
   followed by "||").
2. No duplicate `assets/`/`addons/`-rooted backtick path appears twice
   (copy-paste duplicate entries).
3. Every backtick-quoted `assets/`/`addons/`-rooted path referenced actually
   exists on disk (file, directory, or glob pattern with >=1 match).

Usage: python scripts/check_credits.py [path/to/CREDITS.md]
Exits non-zero with the offending line numbers on any failure.
"""

import glob
import os
import re
import sys

PATH_RE = re.compile(r"`((?:assets|addons)/[^`]+)`")
# The concatenation signature: a row's trailing "em dash or hyphen cell" cell
# immediately butted against the next row's opening pipe, with no space/
# newline between them — exactly what a dropped newline during a merge
# produces (`--| Next Row |...` collapses to `--||...`).
CONCAT_RE = re.compile(r"(?:—|-)\s*\|\|")


def check(path: str) -> list[str]:
    errors: list[str] = []
    seen_paths: dict[str, int] = {}
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(path)))

    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    for lineno, line in enumerate(lines, start=1):
        if not line.startswith("|"):
            continue
        if CONCAT_RE.search(line):
            errors.append(
                f"{path}:{lineno}: looks like two table rows concatenated onto one "
                "line (missing newline between them)"
            )
        for rel_path in PATH_RE.findall(line):
            if rel_path in seen_paths:
                errors.append(
                    f"{path}:{lineno}: duplicate path `{rel_path}` "
                    f"(first seen line {seen_paths[rel_path]})"
                )
            else:
                seen_paths[rel_path] = lineno
            full = os.path.join(repo_root, rel_path)
            if "*" in rel_path or "?" in rel_path:
                if not glob.glob(full):
                    errors.append(f"{path}:{lineno}: no files match glob `{rel_path}`")
            elif not os.path.exists(full.rstrip("/")):
                errors.append(f"{path}:{lineno}: referenced path does not exist: `{rel_path}`")

    return errors


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "assets/CREDITS.md"
    errors = check(path)
    if errors:
        for error in errors:
            print(f"::error::{error}")
        print(f"\n{len(errors)} CREDITS.md integrity problem(s) found.")
        return 1
    print(f"{path}: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
