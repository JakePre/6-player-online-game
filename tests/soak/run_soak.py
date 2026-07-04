#!/usr/bin/env python3
"""Soak harness (M1-05): dedicated server + N headless bot clients.

One bot creates the room, N-2 join it, and one runs the disconnect->rejoin
flow. All bots get artificial latency/loss so the pipeline is exercised under
bad network conditions. Exit code 0 = every bot passed.

Defaults to 6 bots (the CI configuration); --bots raises it up to the room
cap — 24 verifies the ADR 003 / M15-01 large-room path.

Usage:
    python tests/soak/run_soak.py --godot path/to/godot [--duration 15] [--bots 24]
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import threading
import time

PORT = 54545
DEFAULT_BOT_COUNT = 6  # 1 creator + 4 joiners + 1 rejoin-tester
FAKE_LAG_MS = 80
FAKE_LOSS = 0.05


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


def drain(proc: subprocess.Popen, sink: list[str]) -> None:
    def reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            sink.append(line.strip())

    threading.Thread(target=reader, daemon=True).start()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--duration", type=int, default=15)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument(
        "--bots",
        type=int,
        default=DEFAULT_BOT_COUNT,
        help="total bot clients: 1 creator + N-2 joiners + 1 rejoin-tester (min 3)",
    )
    args = parser.parse_args()
    if args.bots < 3:
        print("FAIL: --bots must be at least 3 (creator + joiner + rejoiner)")
        return 1

    lag_args = [f"--fake-lag={FAKE_LAG_MS}", f"--fake-loss={FAKE_LOSS}"]
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

        common = [f"--address=127.0.0.1", f"--port={args.port}", f"--duration={args.duration}"]
        creator_log: list[str] = []
        creator = start(
            godot_cmd(args.godot, ["--bot", "--create", "--name=Creator"] + common + lag_args)
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
        for i in range(args.bots - 2):
            name = f"Joiner{i + 1}"
            log: list[str] = []
            proc = start(
                godot_cmd(args.godot, ["--bot", f"--code={code}", f"--name={name}"] + common + lag_args)
            )
            drain(proc, log)
            procs.append(proc)
            bots.append((name, proc, log))
        rejoin_log: list[str] = []
        rejoiner = start(
            godot_cmd(
                args.godot,
                ["--bot", f"--code={code}", "--name=Rejoiner", "--rejoin-test"] + common + lag_args,
            )
        )
        drain(rejoiner, rejoin_log)
        procs.append(rejoiner)
        bots.append(("Rejoiner", rejoiner, rejoin_log))

        deadline = time.monotonic() + args.duration + 90
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

        # Surface the server's snapshot-cost telemetry (M15-01): the numbers
        # that justify (or demand) area-of-interest culling as rooms grow.
        for line in server_log:
            if "snapshot_cost" in line:
                print(line)

        if failed:
            print("SOAK FAIL")
            print("--- server log tail ---")
            print("\n".join(server_log[-30:]))
            return 1
        print("SOAK PASS")
        return 0
    finally:
        for proc in procs:
            if proc.poll() is None:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main())
