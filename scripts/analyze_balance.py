#!/usr/bin/env python3
"""Aggregate + analyze nightly balance telemetry for M12-01 (#730).

Input: one or more balance-telemetry JSON files (the nightly artifacts —
`balance-telemetry-{2,4,6}.json`, each an array of per-round records emitted
by tests/soak/playtest_bot.gd: game_id, player_count, round, placements,
awards, duration_ms). Pass any number of files from any number of nights;
rounds pool per (game, player_count) cell.

Output: a markdown report per cell — sample size, duration profile vs the
game's meta duration (scripts/game_durations.json, regenerate when metas
change), tie structure, slot-position win bias, and award economy — plus
`review:` flag lines where a heuristic trips.

The flags are REVIEW PROMPTS, not verdicts: docs/BALANCE_GUIDE.md maps which
signatures are intentional design (the #174/#175 revert precedent) and which
are bot artifacts (#715) before anything gets "fixed". Tuning decisions
require the guide's owner-checkpoint procedure.

Usage:
    python scripts/analyze_balance.py telemetry1.json [telemetry2.json ...]
    python scripts/analyze_balance.py --min-n 5 artifacts/*.json
"""

import argparse
import json
import statistics
from collections import defaultdict
from pathlib import Path

# Heuristic thresholds — documented review prompts, deliberately coarse.
TIMEOUT_NEAR = 0.90  # a round at >=90% of meta duration ran to the timeout
FLAG_TIMEOUT_RATE = 0.8  # win condition (almost) never reached early
FLAG_FAST_MEDIAN = 0.25  # median under 25% of meta: rounds end suspiciously fast
FLAG_FULL_TIE = 0.5  # over half the rounds a full tie
FLAG_SLOT_BIAS = 0.35  # one seat exceeding uniform win share by this much
MIN_N_BIAS = 10  # slot bias needs a real sample before it means anything


def load_rounds(paths: list[str]) -> list[dict]:
    rounds: list[dict] = []
    for p in paths:
        data = json.loads(Path(p).read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise SystemExit(f"{p}: expected a JSON array of round records")
        rounds.extend(data)
    return rounds


def winners_of(placements: list) -> list[int]:
    return [int(s) for s in placements[0]] if placements else []


def analyze_cell(rounds: list[dict], meta_duration: float | None) -> dict:
    n = len(rounds)
    durations = [r["duration_ms"] / 1000.0 for r in rounds]
    players = max(int(r["player_count"]) for r in rounds)
    full_ties = sum(
        1 for r in rounds if len(r["placements"]) == 1 and len(r["placements"][0]) >= players
    )
    first_ties = sum(1 for r in rounds if r["placements"] and len(r["placements"][0]) > 1)
    win_counts: dict[int, int] = defaultdict(int)
    for r in rounds:
        for slot in winners_of(r["placements"]):
            win_counts[slot] += 1
    total_wins = sum(win_counts.values())
    awards_per_round = [sum(int(v) for v in r.get("awards", {}).values()) for r in rounds]
    out = {
        "n": n,
        "duration_median": statistics.median(durations),
        "duration_p90": sorted(durations)[max(0, int(n * 0.9) - 1)],
        "full_tie_rate": full_ties / n,
        "first_tie_rate": first_ties / n,
        "awards_mean": statistics.mean(awards_per_round) if awards_per_round else 0.0,
        "flags": [],
    }
    if meta_duration:
        timeout_rate = sum(1 for d in durations if d >= meta_duration * TIMEOUT_NEAR) / n
        out["timeout_rate"] = timeout_rate
        if timeout_rate >= FLAG_TIMEOUT_RATE:
            out["flags"].append(
                f"timeout_rate {timeout_rate:.0%} — win condition rarely reached before the cap"
            )
        if out["duration_median"] <= meta_duration * FLAG_FAST_MEDIAN:
            out["flags"].append(
                f"median {out['duration_median']:.0f}s vs {meta_duration:.0f}s meta — "
                "rounds end suspiciously fast"
            )
    if out["full_tie_rate"] >= FLAG_FULL_TIE:
        out["flags"].append(f"full ties {out['full_tie_rate']:.0%} of rounds")
    if n >= MIN_N_BIAS and total_wins:
        uniform = 1.0 / players
        for slot, wins in sorted(win_counts.items()):
            share = wins / total_wins
            if share - uniform >= FLAG_SLOT_BIAS:
                out["flags"].append(
                    f"slot {slot} wins {share:.0%} (uniform {uniform:.0%}) — spawn/seat bias?"
                )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", help="balance-telemetry JSON artifacts")
    parser.add_argument("--min-n", type=int, default=1, help="hide cells with fewer rounds")
    args = parser.parse_args()

    durations_path = Path(__file__).with_name("game_durations.json")
    meta_durations: dict[str, float] = (
        json.loads(durations_path.read_text()) if durations_path.exists() else {}
    )

    cells: dict[tuple[str, int], list[dict]] = defaultdict(list)
    finales: list[dict] = []
    for r in load_rounds(args.files):
        # Finale records (#706) carry KO-source data instead of round timing —
        # they answer the #584 weapons question, not per-game balance.
        if r.get("finale", False) or "duration_ms" not in r:
            finales.append(r)
            continue
        cells[(r["game_id"], int(r["player_count"]))].append(r)

    print(f"# Balance telemetry report — {sum(len(v) for v in cells.values())} rounds, "
          f"{len(cells)} (game, players) cells\n")
    print("| game | players | n | med s | p90 s | timeout | full-tie | 1st-tie | coins/rd |")
    print("|---|---|---|---|---|---|---|---|---|")
    flagged: list[tuple[str, int, list[str]]] = []
    for (game, players), rounds in sorted(cells.items()):
        if len(rounds) < args.min_n:
            continue
        a = analyze_cell(rounds, meta_durations.get(game))
        timeout = f"{a['timeout_rate']:.0%}" if "timeout_rate" in a else "?"
        print(
            f"| {game} | {players} | {a['n']} | {a['duration_median']:.0f} "
            f"| {a['duration_p90']:.0f} | {timeout} | {a['full_tie_rate']:.0%} "
            f"| {a['first_tie_rate']:.0%} | {a['awards_mean']:.1f} |"
        )
        if a["flags"]:
            flagged.append((game, players, a["flags"]))
    print()
    if flagged:
        print("## Review prompts (check docs/BALANCE_GUIDE.md before 'fixing' anything)\n")
        for game, players, flags in flagged:
            for f in flags:
                print(f"- review: {game} @{players}p — {f}")
    else:
        print("No heuristic flags tripped at these sample sizes.")
    if finales:
        ko_totals: dict[str, int] = defaultdict(int)
        axe_totals = 0
        for f in finales:
            for cause, count in f.get("ko_causes", {}).items():
                ko_totals[str(cause)] += int(count)
            axe_totals += sum(int(v) for v in f.get("axe_kills", {}).values())
        print(f"\n## Finale KO sources (#706 -> the #584 weapons question) — "
              f"{len(finales)} finales")
        print(f"- ko_causes: {dict(sorted(ko_totals.items())) or 'none recorded'}")
        print(f"- axe kills total: {axe_totals}")
    thin = sum(1 for v in cells.values() if len(v) < MIN_N_BIAS)
    print(f"\n_{thin}/{len(cells)} cells still under n={MIN_N_BIAS}; "
          "per-game conclusions need more nights (see #730 throughput note)._")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
