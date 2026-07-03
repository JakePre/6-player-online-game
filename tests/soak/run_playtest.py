#!/usr/bin/env python3
"""Playtest harness (M7-03): dedicated server + 6 headless bots play a full
match to completion (not just a connection soak — see tests/soak/run_soak.py
for that). The server runs with --debug-rpcs so the match uses compressed
round timing and finishes in seconds. Exit code 0 = every bot passed.

Usage:
    python tests/soak/run_playtest.py --godot path/to/godot [--rounds 12]
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import threading
import time

PORT = 54546
BOT_COUNT = 6


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
    parser.add_argument("--rounds", type=int, default=12)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument(
        "--mutators",
        action="store_true",
        help="M9-06 variant: host enables the full mutator pool; bots require >=1 mutated round",
    )
    args = parser.parse_args()

    common = [f"--address=127.0.0.1", f"--port={args.port}", f"--rounds={args.rounds}", f"--players={BOT_COUNT}"]
    if args.mutators:
        common.append("--mutators")
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
        for i in range(BOT_COUNT - 1):
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
        # generous headroom.
        deadline = time.monotonic() + 120
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
