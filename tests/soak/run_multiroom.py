#!/usr/bin/env python3
"""Multi-room load soak (#710): one dedicated server hosting N concurrent
rooms of M bots each, to find where the single-threaded server tick can no
longer keep up with the 30 Hz per-room snapshot broadcast.

All prior load evidence was 1 room x N players (M15-01 snapshot_cost). The
public server runs many rooms at once on one tick loop, so the ceiling is a
function of ROOMS, not just players-per-room. This harness launches N creator
bots + (M-1) joiners per room against one --debug-rpcs server (compressed
timing so matches finish fast), then reads the server's own `tick_ms`
telemetry (NetManager._record_tick_time, #710) to chart p95/max broadcast-tick
cost against the SNAPSHOT_INTERVAL budget as rooms scale.

Usage:
    python tests/soak/run_multiroom.py --godot path/to/godot --rooms 10 [--players 6] [--rounds 12]
    # sweep several scales in one invocation:
    python tests/soak/run_multiroom.py --godot path/to/godot --sweep 2,5,10,20

Reads `[server] tick_ms rooms=.. members=.. p95=.. max=.. mean=.. budget=..`
lines and reports the worst p95 per scale + whether it stayed under budget.
Note: every bot is a headless Godot process, so ROOMS*PLAYERS processes run at
once — 40x6 needs a beefy host; a laptop tops out far lower. The server-side
cost is what's being measured; the clients are just load generators.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import threading
import time

PORT = 54547  # distinct from run_playtest's 54546 so both can run side by side
TICK_RE = re.compile(
    r"tick_ms rooms=(\d+) members=(\d+) p95=([\d.]+) max=([\d.]+) mean=([\d.]+) budget=([\d.]+)"
)


def godot_cmd(godot: str, extra: list[str]) -> list[str]:
    return [godot, "--headless", "--path", ".", "--"] + extra


def start(cmd: list[str]) -> subprocess.Popen:
    return subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
    )


def wait_for_line(proc: subprocess.Popen, prefix: str, timeout: float, sink: list[str]) -> str | None:
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


def drain(proc: subprocess.Popen, sink: list[str]) -> None:
    def reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            sink.append(line.strip())

    threading.Thread(target=reader, daemon=True).start()


def run_scale(godot: str, rooms: int, players: int, rounds: int, port: int) -> dict:
    """One soak at a given room count. Returns the peak tick_ms measurement."""
    common = [f"--address=127.0.0.1", f"--port={port}", f"--rounds={rounds}", f"--players={players}"]
    server_log: list[str] = []
    server = start(godot_cmd(godot, ["--server", f"--port={port}", "--debug-rpcs"]))
    procs: list[subprocess.Popen] = [server]
    try:
        if wait_for_line(server, "SERVER READY", 60, server_log) is None:
            print("  FAIL: server never became ready")
            return {"ok": False}
        drain(server, server_log)

        # N creators, each opening its own room; collect their codes.
        creators: list[tuple[subprocess.Popen, list[str]]] = []
        codes: list[str] = []
        for r in range(rooms):
            log: list[str] = []
            proc = start(godot_cmd(godot, ["--playtest", "--create", f"--name=Creator{r}"] + common))
            procs.append(proc)
            line = wait_for_line(proc, "ROOM_CODE=", 60, log)
            if line is None:
                print(f"  FAIL: creator {r} never produced a room code")
                return {"ok": False}
            drain(proc, log)
            creators.append((proc, log))
            codes.append(line.split("=", 1)[1])

        # (M-1) joiners per room.
        bots: list[tuple[str, subprocess.Popen, list[str]]] = [
            (f"Creator{r}", creators[r][0], creators[r][1]) for r in range(rooms)
        ]
        for r, code in enumerate(codes):
            for j in range(players - 1):
                log = []
                name = f"R{r}J{j}"
                proc = start(godot_cmd(godot, ["--playtest", f"--code={code}", f"--name={name}"] + common))
                drain(proc, log)
                procs.append(proc)
                bots.append((name, proc, log))

        # Compressed matches finish in seconds; give generous headroom for the
        # OS to schedule rooms*players headless processes.
        deadline = time.monotonic() + 120.0
        failed = 0
        for name, proc, log in bots:
            remaining = max(1.0, deadline - time.monotonic())
            try:
                if proc.wait(timeout=remaining) != 0:
                    failed += 1
            except subprocess.TimeoutExpired:
                print(f"  bot {name} timed out")
                failed += 1

        peak = pick_peak(server_log)
        status = "OK" if failed == 0 else f"{failed} bot(s) FAILED"
        if peak:
            print(
                f"  rooms={rooms} players={players}: {status} | peak tick_ms "
                f"p95={peak['p95']:.2f} max={peak['max']:.2f} (budget {peak['budget']:.2f}) "
                f"@ members={peak['members']}"
            )
        else:
            print(f"  rooms={rooms} players={players}: {status} | no tick_ms samples "
                  "(match too short to reach a 10 s print — raise --rounds)")
        return {"ok": failed == 0, "rooms": rooms, "players": players, "peak": peak}
    finally:
        for p in procs:
            if p.poll() is None:
                p.terminate()
        for p in procs:
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()


def pick_peak(server_log: list[str]) -> dict | None:
    """The tick_ms sample with the most members (the heaviest moment)."""
    best: dict | None = None
    for line in server_log:
        m = TICK_RE.search(line)
        if not m:
            continue
        sample = {
            "rooms": int(m.group(1)),
            "members": int(m.group(2)),
            "p95": float(m.group(3)),
            "max": float(m.group(4)),
            "mean": float(m.group(5)),
            "budget": float(m.group(6)),
        }
        if best is None or sample["members"] > best["members"]:
            best = sample
    return best


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--rooms", type=int, default=10)
    parser.add_argument("--players", type=int, default=6)
    parser.add_argument("--rounds", type=int, default=12, help="keep >=8 so a match spans a 10 s tick_ms print")
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--sweep", default=None, help="comma-separated room counts, e.g. 2,5,10,20")
    args = parser.parse_args()

    scales = [int(x) for x in args.sweep.split(",")] if args.sweep else [args.rooms]
    print(f"Multi-room load soak (#710): {scales} rooms x {args.players} players, "
          f"{args.rounds} rounds each\n")
    results = []
    for rooms in scales:
        results.append(run_scale(args.godot, rooms, args.players, args.rounds, args.port))

    print("\n## Summary — tick cost vs the 30 Hz broadcast budget")
    print("| rooms | members | p95 ms | max ms | budget ms | headroom |")
    print("|---|---|---|---|---|---|")
    any_over = False
    for r in results:
        peak = r.get("peak")
        if not peak:
            print(f"| {r.get('rooms','?')} | ? | (no samples) | | | |")
            continue
        headroom = peak["budget"] - peak["p95"]
        any_over = any_over or headroom < 0
        flag = "OVER" if headroom < 0 else f"{headroom:.1f}"
        print(f"| {peak['rooms']} | {peak['members']} | {peak['p95']:.2f} | {peak['max']:.2f} "
              f"| {peak['budget']:.2f} | {flag} |")
    all_ok = all(r.get("ok") for r in results)
    print(f"\nbots: {'all passed' if all_ok else 'SOME FAILED'}; "
          f"tick budget: {'exceeded at some scale' if any_over else 'held at all tested scales'}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
