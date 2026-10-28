"""Synthesize the hit-feedback thuds (issue #65, package C). Original, no third-party audio.

  hit_thud.wav   a short dull thump: you landed damage
  hit_kill.wav   a lower, heavier thump with a bit of crack on top: that one went down

Each is a sine that drops in pitch (the body of the thump) plus a few ms of low-passed
noise (the impact), both on a fast exponential decay. Deterministic: seeded noise.
Standard library only, so it runs on a bare python3.

Run: python3 tools/audio/make_hit_sfx.py
Writes 16-bit mono WAVs to assets/audio/hud/.
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "hud")


def thump(dur, f_start, f_end, decay, click, click_cut, seed):
    rng = random.Random(seed)
    n = int(SR * dur)
    a = math.exp(-2 * math.pi * click_cut / SR)   # one-pole low-pass: a tap, not a hiss
    acc, phase, out = 0.0, 0.0, []
    for i in range(n):
        t = i / SR
        # Pitch glides down from f_start to f_end; phase is the running sum of frequency.
        phase += (f_end + (f_start - f_end) * math.exp(-t * 40.0)) / SR
        body = math.sin(2 * math.pi * phase) * math.exp(-t * decay)
        acc = (1 - a) * rng.gauss(0, 1) + a * acc
        out.append(body + acc * math.exp(-t * 120.0) * click)
    return out


def save(name, x, gain):
    peak = max(abs(v) for v in x) + 1e-9
    k = int(SR * 0.005)                           # last 5 ms fade so it ends on silence
    for i in range(k):
        x[-1 - i] *= i / k
    data = b"".join(struct.pack("<h", int(v / peak * gain * 32767)) for v in x)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", name, round(len(x) / SR, 2), "s")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("hit_thud.wav", thump(0.14, 260, 110, 30.0, 1.6, 3000, 651), 0.7)
    save("hit_kill.wav", thump(0.28, 170, 62, 15.0, 2.2, 1800, 652), 0.9)
