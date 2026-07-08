#!/usr/bin/env python3
"""Deterministic SFX synthesizer for Party Rush (M20-01, #711).

Generates the cues no CC0 pack provides — a water splash and a bomb
explosion — as 44.1 kHz 16-bit mono WAVs, from a fixed seed so re-running
always reproduces the committed files byte-for-byte (same precedent as the
Shred Session drums, but with the generator committed this time).

Usage: python scripts/synth_sfx.py  (writes into assets/audio/party_rush_synth/)
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
SEED = 20260707  # M20-01 landing date; never change without regenerating credits
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "party_rush_synth"


def write_wav(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(abs(s) for s in samples) or 1.0
    with wave.open(str(OUT / name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", int(32000 * s / peak)) for s in samples
            )
        )


def splash() -> list[float]:
    """Water entry: a short bright noise burst that darkens and decays, with a
    low 'bloop' underneath — reads as a splash at arcade scale."""
    rng = random.Random(SEED)
    dur = 0.55
    n = int(RATE * dur)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        # Noise through a closing low-pass: bright hiss -> dull wash.
        cutoff = 0.85 * math.exp(-6.0 * t) + 0.04
        lp += cutoff * (rng.uniform(-1, 1) - lp)
        env = math.exp(-7.0 * t)
        # The bloop: a sine dropping 320 -> 90 Hz over the first 180 ms.
        bloop = 0.0
        if t < 0.18:
            freq = 320.0 - (230.0 * (t / 0.18))
            bloop = 0.6 * math.sin(TAU * freq * t) * math.exp(-12.0 * t)
        out.append(0.9 * lp * env + bloop)
    return out


def explosion() -> list[float]:
    """Bomb blast: a sub-bass thump plus a heavy noise body with a slow
    low-pass decay — big but short enough for 30 Hz gameplay spam."""
    rng = random.Random(SEED + 1)
    dur = 0.9
    n = int(RATE * dur)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        # Noise body, darkening fast.
        cutoff = 0.5 * math.exp(-3.5 * t) + 0.02
        lp += cutoff * (rng.uniform(-1, 1) - lp)
        body = lp * math.exp(-4.0 * t)
        # Sub thump: 110 -> 38 Hz pitch drop, strongest at the front.
        freq = 110.0 * math.exp(-8.0 * t) + 38.0
        thump = 0.8 * math.sin(TAU * freq * t) * math.exp(-9.0 * t)
        out.append(1.1 * body + thump)
    return out


TAU = 2 * math.pi

if __name__ == "__main__":
    write_wav("splash.wav", splash())
    write_wav("explosion.wav", explosion())
    print(f"wrote splash.wav + explosion.wav to {OUT}")
