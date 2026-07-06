#!/usr/bin/env python3
"""Render harness (#626): record a short video of one minigame being played by
practice bots, for human audit of changes without rallying playtesters.

Architecture: a `--debug-rpcs` server + ONE windowed "camera" client launched
via `--debug-minigame` with `--debug-bots=N` (server-owned #577 bots actually
play; the camera's own rig idles at spawn) and `--debug-duration=S` (a tight
clip instead of a full round).

Two capture modes:
  x11grab  (Linux/CI)  ffmpeg records the X display in WALL time while the
                       client runs normally — honest pacing even if software
                       rendering drops frames. Run under xvfb-run on CI.
  movie    (anywhere)  Godot Movie Maker mode (--write-movie). Works on any
                       OS with no ffmpeg/X, but records in ENGINE time: the
                       video plays the match slowed/sped by the render-speed
                       ratio (200-300% of realtime on a fast GPU, slower than
                       realtime under CI software rendering). Fine for local
                       previews; labelled, not the audit mechanism.

Usage:
    python tests/soak/render_game.py --godot path/to/godot --game coin_scramble
    python tests/soak/render_game.py --godot path/to/godot --game sumo_smash \
        --bots 5 --duration 30 --capture movie --out renders/
Exit code 0 = a video file exists at the printed path.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time

PORT = 54549
RESOLUTION = "1280x720"
FPS = 30
# Boot + connect + bot joins + intro card ahead of the round, results after.
LEAD_IN_SEC = 12.0
LEAD_OUT_SEC = 15.0


def start(cmd: list[str], env: dict | None = None) -> subprocess.Popen:
    return subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )


def wait_for_line(proc: subprocess.Popen, prefix: str, timeout: float, sink: list[str]) -> bool:
    deadline = time.monotonic() + timeout
    import threading

    found = [False]

    def reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            sink.append(line)
            if line.startswith(prefix):
                found[0] = True
                return

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    thread.join(max(0.0, deadline - time.monotonic()))
    return found[0]


def drain(proc: subprocess.Popen, sink: list[str]) -> None:
    import threading

    def reader() -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            sink.append(line.strip())

    threading.Thread(target=reader, daemon=True).start()


def convert_to_mp4(src: str, dst: str) -> bool:
    """Best-effort mjpeg-avi -> h264-mp4; keeps the avi if ffmpeg is missing."""
    if shutil.which("ffmpeg") is None:
        print(f"ffmpeg not found; keeping {src}")
        return False
    result = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-c:v", "libx264", "-pix_fmt", "yuv420p", dst],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"ffmpeg convert failed: {result.stderr.strip()[:400]}")
        return False
    os.remove(src)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--game", required=True, help="minigame id (e.g. coin_scramble)")
    parser.add_argument("--bots", type=int, default=5, help="practice bots playing (default 5)")
    parser.add_argument(
        "--duration", type=float, default=30.0, help="round duration override in seconds"
    )
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--out", default="renders", help="output directory")
    parser.add_argument(
        "--capture",
        choices=["auto", "x11grab", "movie"],
        default="auto",
        help="auto = x11grab when a Linux DISPLAY exists, else movie",
    )
    parser.add_argument(
        "--software-gl",
        action="store_true",
        help="force Mesa software GL (CI runners without a GPU)",
    )
    args = parser.parse_args()

    if args.capture == "auto":
        args.capture = (
            "x11grab"
            if sys.platform.startswith("linux") and os.environ.get("DISPLAY")
            else "movie"
        )
    os.makedirs(args.out, exist_ok=True)
    final_path = os.path.join(args.out, f"{args.game}.mp4")
    budget = LEAD_IN_SEC + args.duration + LEAD_OUT_SEC

    server_log: list[str] = []
    server = start(
        [args.godot, "--headless", "--path", ".", "--", "--server", f"--port={args.port}", "--debug-rpcs"]
    )
    procs: list[subprocess.Popen] = [server]
    try:
        if not wait_for_line(server, "SERVER READY", 60, server_log):
            print("FAIL: server never became ready")
            print("\n".join(server_log[-20:]))
            return 1
        drain(server, server_log)

        client_cmd = [args.godot, "--path", ".", "--resolution", RESOLUTION]
        env = os.environ.copy()
        if args.software_gl:
            # CI runners: Mesa llvmpipe GL + no audio device.
            client_cmd += ["--rendering-method", "gl_compatibility", "--audio-driver", "Dummy"]
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        movie_path = os.path.join(args.out, f"{args.game}.avi")
        if args.capture == "movie":
            client_cmd += [
                "--write-movie",
                movie_path,
                "--fixed-fps",
                str(FPS),
                "--quit-after",
                str(int(budget * FPS)),
            ]
        client_cmd += [
            "--",
            f"--debug-minigame={args.game}",
            f"--debug-bots={args.bots}",
            f"--debug-duration={args.duration}",
            f"--port={args.port}",
        ]

        recorder: subprocess.Popen | None = None
        if args.capture == "x11grab":
            recorder = start(
                [
                    "ffmpeg", "-y", "-loglevel", "error",
                    "-f", "x11grab", "-video_size", RESOLUTION, "-framerate", str(FPS),
                    "-i", env.get("DISPLAY", ":0"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", final_path,
                ]
            )
            procs.append(recorder)

        client_log: list[str] = []
        client = start(client_cmd, env=env)
        procs.append(client)
        if not wait_for_line(client, "[debug-launcher] round started", 60, client_log):
            print(f"FAIL: round never started for {args.game}")
            print("\n".join(client_log[-20:] + ["--- server ---"] + server_log[-10:]))
            return 1
        drain(client, client_log)
        print(f"round started: {args.game} — recording ~{budget:.0f}s")

        try:
            client.wait(timeout=budget + 60)
        except subprocess.TimeoutExpired:
            client.kill()

        if recorder is not None:
            recorder.terminate()  # SIGTERM finalizes the mp4 cleanly
            try:
                recorder.wait(timeout=30)
            except subprocess.TimeoutExpired:
                recorder.kill()
        elif os.path.exists(movie_path):
            if convert_to_mp4(movie_path, final_path):
                pass
            else:
                final_path = movie_path
            print(
                "note: movie mode records in engine time — pacing is approximate "
                "(see render_game.py docstring)"
            )

        if not os.path.exists(final_path) or os.path.getsize(final_path) == 0:
            print(f"FAIL: no video at {final_path}")
            return 1
        print(f"RENDER OK {final_path} ({os.path.getsize(final_path) // 1024} KiB)")
        return 0
    finally:
        for proc in procs:
            if proc.poll() is None:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main())
