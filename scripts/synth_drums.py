#!/usr/bin/env python3
"""Deterministic 808/909-style drum-machine synthesizer for Shred Session (#798).

Replaces the crude procedural drum blips with a proper analog-drum-machine
voice — a pitched-sine kick, a tone+noise snare, a metallic hat, and a pitched
tom — as 44.1 kHz 16-bit mono WAVs. A fixed seed means re-running reproduces the
committed files byte-for-byte (same precedent as scripts/synth_sfx.py). The
output is CC0-original: no third-party samples, no attribution needed.

Usage: python scripts/synth_drums.py  (writes into assets/audio/shred_drums/)
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
SEED = 20260711  # #798 landing date; never change without regenerating credits
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "shred_drums"


def write_wav(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    with wave.open(str(OUT / name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        # Normalize to -1 dBFS so every drum hits at a consistent, safe level.
        gain = 0.89 / peak
        f.writeframes(
            b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples)
        )


def _n(seconds: float) -> int:
    return int(RATE * seconds)


def _expdecay(i: int, total: int, tau: float) -> float:
    """Exponential amplitude envelope, 1.0 → ~0 over the tail with time-constant tau."""
    return math.exp(-(i / RATE) / tau)


def kick() -> list[float]:
    """808 boom: a sine whose pitch drops fast from a click to a deep body."""
    total = _n(0.34)
    out = []
    phase = 0.0
    for i in range(total):
        t = i / RATE
        # Pitch sweeps 118 Hz → 46 Hz in the first ~40 ms, then holds.
        freq = 46.0 + 72.0 * math.exp(-t / 0.028)
        phase += 2.0 * math.pi * freq / RATE
        body = math.sin(phase)
        # A short click transient gives the beater attack.
        click = math.sin(2.0 * math.pi * 1400.0 * t) * math.exp(-t / 0.004) * 0.5
        out.append((body + click) * _expdecay(i, total, 0.11))
    return out


def snare(rng: random.Random) -> list[float]:
    """Two detuned tones for the shell + a noise burst for the wires."""
    total = _n(0.20)
    out = []
    for i in range(total):
        t = i / RATE
        tone = (
            math.sin(2.0 * math.pi * 178.0 * t) + 0.7 * math.sin(2.0 * math.pi * 331.0 * t)
        ) * math.exp(-t / 0.045)
        noise = rng.uniform(-1.0, 1.0) * math.exp(-t / 0.075)
        out.append(0.5 * tone + 0.7 * noise)
    return out


def hat(rng: random.Random) -> list[float]:
    """Metallic hat: bright square-ish partials + noise, snapped off fast."""
    total = _n(0.055)
    partials = [2100.0, 3300.0, 4700.0, 6400.0, 8200.0]
    out = []
    for i in range(total):
        t = i / RATE
        metal = sum(1.0 if math.sin(2.0 * math.pi * p * t) >= 0.0 else -1.0 for p in partials)
        metal /= len(partials)
        noise = rng.uniform(-1.0, 1.0)
        out.append((0.6 * metal + 0.4 * noise) * math.exp(-t / 0.012))
    return out


def tom() -> list[float]:
    """A mid tom: like the kick but tuned higher and shorter."""
    total = _n(0.26)
    out = []
    phase = 0.0
    for i in range(total):
        t = i / RATE
        freq = 96.0 + 96.0 * math.exp(-t / 0.05)
        phase += 2.0 * math.pi * freq / RATE
        out.append(math.sin(phase) * _expdecay(i, total, 0.09))
    return out


def main() -> None:
    rng = random.Random(SEED)
    write_wav("kick.wav", kick())
    write_wav("snare.wav", snare(rng))
    write_wav("hat.wav", hat(rng))
    write_wav("tom.wav", tom())
    print("wrote kick/snare/hat/tom.wav to", OUT)


if __name__ == "__main__":
    main()
