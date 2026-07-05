#!/usr/bin/env python3
"""Playtest harness (M7-03): dedicated server + N headless bots play a full
match to completion (not just a connection soak — see tests/soak/run_soak.py
for that). The server runs with --debug-rpcs so the match uses compressed
round timing and finishes in seconds. Exit code 0 = every bot passed.

Defaults to 6 bots (the CI/nightly config); --players raises it to verify the
ADR 003 per-game caps in a real match at 12 or 24 players — the playlist only
drafts games eligible at that head count, so a 12-bot run exercises the scaled
12-cap games end to end.

Usage:
    python tests/soak/run_playtest.py --godot path/to/godot [--rounds 12] [--players 12]
    python tests/soak/run_playtest.py --godot path/to/godot --telemetry-out out.json
    python tests/soak/run_playtest.py --godot path/to/godot --balance --players 4 \
        --telemetry-out balance-telemetry-4.json

--telemetry-out (#548) writes the creator bot's per-round balance telemetry
(game_id, player_count, placements, awards, duration_ms) as a JSON array, for
the M12-01 balance pass to consume once a few nights of runs accumulate.

--balance (#560) is the variant that makes that telemetry meaningful: rounds
run their REAL durations (~15-20 min for a 12-round match) while bots send
randomized gameplay inputs, so placements reflect the sims actually being
played instead of the compressed idle smoke run's all-tie noise.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time

TELEMETRY_PREFIX = "PLAYTEST_TELEMETRY "

PORT = 54546
DEFAULT_BOT_COUNT = 6


def godot_cmd(godot: str, extra: list[str]) -> list[str]:
    return [godot, "--headless", "--path", ".", "--"] + extra


def start(cmd: list[str]) -> subprocess.Popen:
    return subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
    )


def wait_for_line(proc: subprocess.Popen, prefix: str, timeout: float, sink: list[str]) -> str | None:
    """Read stdout until a line starts with `prefix`. Returns the line or None."""
    deadline = time.monotonic() + timeout
    result: list[str | None] = [None]

    def reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            sink.append(line)
            if line.startswith(prefix):
                result[0] = line
                return

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    thread.join(max(0.0, deadline - time.monotonic()))
    return result[0]


def write_telemetry(creator_log: list[str], out_path: str) -> None:
    """Pulls the creator's PLAYTEST_TELEMETRY line (#548) out of its log and
    writes the JSON array to `out_path`. Silently skips if the line never
    appeared (e.g. an older client build without the instrumentation)."""
    line = next((l for l in creator_log if l.startswith(TELEMETRY_PREFIX)), None)
    if line is None:
        print("no PLAYTEST_TELEMETRY line seen; skipping telemetry write")
        return
    payload = line[len(TELEMETRY_PREFIX) :]
    try:
        rounds = json.loads(payload)
    except json.JSONDecodeError as exc:
        print(f"could not parse PLAYTEST_TELEMETRY line: {exc}")
        return
    with open(out_path, "w") as f:
        json.dump(rounds, f)
    print(f"wrote {len(rounds)} round(s) of telemetry to {out_path}")


def drain(proc: subprocess.Popen, sink: list[str]) -> None:
    def reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            sink.append(line.strip())

    threading.Thread(target=reader, daemon=True).start()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--rounds", type=int, default=12)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument(
        "--mutators",
        action="store_true",
        help="M9-06 variant: host enables the full mutator pool; bots require >=1 mutated round",
    )
    parser.add_argument(
        "--players",
        type=int,
        default=DEFAULT_BOT_COUNT,
        help="total bots in the match (default 6 = the CI/nightly config; raise to verify "
        "the ADR 003 caps in a full match at 12/24)",
    )
    parser.add_argument(
        "--telemetry-out",
        default=None,
        help="write the creator bot's per-round balance telemetry (#548) as a JSON array "
        "to this path; skipped if the harness fails or no telemetry line is seen",
    )
    parser.add_argument(
        "--balance",
        action="store_true",
        help="#560 balance variant: real round durations + randomized bot inputs, so the "
        "telemetry carries actual balance signal (expect ~15-20 min per 12-round match)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=None,
        help="overall per-bot deadline in seconds (default 120, or 1800 with --balance)",
    )
    args = parser.parse_args()
    if args.players < 2:
        print("FAIL: --players must be at least 2 (a match needs a creator + one joiner)")
        return 1
    timeout = args.timeout if args.timeout is not None else (1800.0 if args.balance else 120.0)

    common = [
        f"--address=127.0.0.1",
        f"--port={args.port}",
        f"--rounds={args.rounds}",
        f"--players={args.players}",
        f"--phase-timeout={timeout}",
    ]
    if args.mutators:
        common.append("--mutators")
    if args.balance:
        common.append("--balance")
    server_log: list[str] = []
    server = start(godot_cmd(args.godot, ["--server", f"--port={args.port}", "--debug-rpcs"]))
    procs: list[subprocess.Popen] = [server]
    try:
        if wait_for_line(server, "SERVER READY", 60, server_log) is None:
            print("FAIL: server never became ready")
            print("\n".join(server_log[-20:]))
            return 1
        drain(server, server_log)
        print(f"server ready on port {args.port}")

        creator_log: list[str] = []
        creator = start(
            godot_cmd(args.godot, ["--playtest", "--create", "--name=Creator"] + common)
        )
        procs.append(creator)
        code_line = wait_for_line(creator, "ROOM_CODE=", 60, creator_log)
        if code_line is None:
            print("FAIL: creator bot never produced a room code")
            print("\n".join(creator_log[-20:]))
            return 1
        drain(creator, creator_log)
        code = code_line.split("=", 1)[1]
        print(f"room created: {code}")

        bots: list[tuple[str, subprocess.Popen, list[str]]] = [("Creator", creator, creator_log)]
        for i in range(args.players - 1):
            name = f"Joiner{i + 1}"
            log: list[str] = []
            proc = start(
                godot_cmd(args.godot, ["--playtest", f"--code={code}", f"--name={name}"] + common)
            )
            drain(proc, log)
            procs.append(proc)
            bots.append((name, proc, log))

        # Debug timing compresses a full match into a few seconds, but the CI
        # runner can be slow to schedule 7 headless Godot processes; give it
        # generous headroom. The --balance variant runs real durations and
        # gets a correspondingly larger budget.
        deadline = time.monotonic() + timeout
        failed = False
        for name, proc, log in bots:
            remaining = max(1.0, deadline - time.monotonic())
            try:
                exit_code = proc.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                print(f"FAIL: bot {name} timed out")
                failed = True
                continue
            verdict = next((l for l in log if l.startswith("BOT_RESULT")), "no BOT_RESULT line")
            print(f"{name}: exit={exit_code} {verdict}")
            if exit_code != 0:
                failed = True

        # Surface the server's snapshot-cost telemetry (M15-01): match payloads
        # measured here are the scaling baseline for larger rooms.
        for line in server_log:
            if "snapshot_cost" in line:
                print(line)

        if args.telemetry_out and not failed:
            write_telemetry(bots[0][2], args.telemetry_out)

        if failed:
            print("PLAYTEST FAIL")
            print("--- server log tail ---")
            print("\n".join(server_log[-30:]))
            return 1
        print("PLAYTEST PASS")
        return 0
    finally:
        for proc in procs:
            if proc.poll() is None:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main())
