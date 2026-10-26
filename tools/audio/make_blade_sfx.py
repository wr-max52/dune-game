"""Synthesize the energy blade's sound effects (original, no third-party audio).

Run: python3 tools/audio/make_blade_sfx.py   (needs numpy)
Writes 16-bit mono WAVs to assets/audio/blade/.
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "blade")
rng = np.random.default_rng(7)


def hum_core(t, base=92.0):
    # Two detuned saws through a soft clip: the steady electric drone.
    s = np.zeros_like(t)
    for f, a in ((base, 0.5), (base * 1.007, 0.4), (base * 2.01, 0.2), (base * 3.0, 0.08)):
        ph = (t * f) % 1.0
        s += a * (2.0 * ph - 1.0)
    s += 0.05 * np.sin(2 * np.pi * 50 * t)
    return np.tanh(1.6 * s)


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, len(data) / SR, "s")


def hum_loop():
    # An exact number of base cycles so the loop is seamless.
    dur = 2.0
    t = np.arange(int(SR * dur)) / SR
    wobble = 1.0 + 0.004 * np.sin(2 * np.pi * 0.5 * t)
    x = hum_core(t * wobble)
    x = lowpass(x, 0.18)
    # Fade the seam with a short crossfade against the start.
    n = 2048
    x[-n:] = x[-n:] * np.linspace(1, 0, n) + x[:n] * np.linspace(0, 1, n)
    save("hum_loop.wav", x, 0.55)


def ignite(rev=False):
    dur = 0.55
    t = np.arange(int(SR * dur)) / SR
    sweep = np.where(t < 0.25, 30 + (92 - 30) * (t / 0.25) ** 0.6, 92.0)
    phase = np.cumsum(sweep) / SR
    x = hum_core(phase / 1.0 * 1.0, base=1.0)
    crack = rng.standard_normal(len(t)) * np.exp(-t * 28) * 0.9
    x = lowpass(x + crack, 0.25)
    env = np.minimum(1.0, t / 0.03) * np.where(t > 0.4, np.exp(-(t - 0.4) * 9), 1.0)
    x = x * env
    if rev:
        x = x[::-1]
    save("off.wav" if rev else "on.wav", x)


def swing():
    dur = 0.38
    t = np.arange(int(SR * dur)) / SR
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    # Doppler: the hum pitches up then down as the blade passes.
    pitch = 92 * (1.0 + 0.45 * np.sin(np.pi * t / dur))
    phase = np.cumsum(pitch) / SR
    x = hum_core(phase, base=1.0)
    air = lowpass(rng.standard_normal(len(t)), 0.08) * 2.5
    save("swing.wav", (x * 0.8 + air) * env)


def clash():
    dur = 0.45
    t = np.arange(int(SR * dur)) / SR
    noise = rng.standard_normal(len(t))
    ring = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((1310, 0.5), (2170, 0.35), (3490, 0.2)))
    x = noise * np.exp(-t * 40) + ring * np.exp(-t * 9)
    save("clash.wav", np.tanh(1.5 * x))


def deflect():
    dur = 0.32
    t = np.arange(int(SR * dur)) / SR
    f = 2400 * np.exp(-t * 6) + 500
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10)
    x += rng.standard_normal(len(t)) * np.exp(-t * 60) * 0.6
    save("deflect.wav", x)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    hum_loop()
    ignite(False)
    ignite(True)
    swing()
    clash()
    deflect()
