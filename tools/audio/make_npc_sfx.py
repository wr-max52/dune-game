"""Synthesize the troopers' voice and alarm sounds (original, no third-party audio).

Barks are text on screen; this is what you hear under them: helmet-radio chatter.
A pitched pulse train is shaped by moving vowel formants in a syllable rhythm, with
short noise consonants between syllables, then band-passed and clipped like a cheap
comm channel, with a squelch click at each end. No words, no speech engine: the
line on screen says what was said.

  radio_calm_N.wav   level, mid pitch ("Papers.", "Move along.")
  radio_shout_N.wav  higher, louder, harder clipped ("Halt!", "Contact!")
  klaxon_loop.wav    the town alarm: saw-wave beep beep beep, pause (issue #80)

Run: python3 tools/audio/make_npc_sfx.py   (needs numpy and scipy)
Writes 16-bit mono WAVs to assets/audio/npc/.
"""
import os
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "npc")
rng = np.random.default_rng(15)

# Rough formant pairs (Hz) for a handful of vowels.
VOWELS = [(730, 1090), (530, 1840), (270, 2290), (570, 840), (440, 1020), (660, 1720), (300, 870)]


def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, round(len(data) / SR, 2), "s")


def bandpass(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def resonate(x, f, bw):
    # Two-pole resonator at f with bandwidth bw (one formant).
    r = np.exp(-np.pi * bw / SR)
    th = 2 * np.pi * f / SR
    b = [1 - r]
    a = [1, -2 * r * np.cos(th), r * r]
    return lfilter(b, a, x)


def squelch(dur=0.05, level=0.6):
    n = int(SR * dur)
    t = np.arange(n) / SR
    click = np.zeros(n)
    click[:40] = np.linspace(1, -1, 40)
    hiss = rng.normal(0, 1, n) * np.exp(-t * 60)
    return (click + 0.6 * bandpass(hiss, 1500, 6000)) * level


def chatter(dur, f0, shout=False):
    n = int(SR * dur)
    t = np.arange(n) / SR
    # Intonation: a slow wander, rising at the end of a shout.
    pitch = f0 * (1 + 0.06 * np.sin(2 * np.pi * rng.uniform(0.6, 1.4) * t + rng.uniform(0, 6)))
    if shout:
        pitch *= 1 + 0.15 * (t / dur)
    pitch *= 1 + 0.01 * rng.normal(0, 1, n).cumsum() / np.sqrt(np.arange(1, n + 1))
    phase = np.cumsum(pitch / SR)
    pulses = (np.diff(np.floor(phase), prepend=0) > 0).astype(float)
    source = lfilter([1], [1, -0.97], pulses)          # glottal-ish tilt
    # Syllables: 5-7 a second, each its own vowel, with gaps for consonants.
    rate = rng.uniform(5.0, 7.0) * (1.15 if shout else 1.0)
    syl = int(dur * rate) + 1
    edges = np.sort(rng.uniform(0, dur, syl - 1)) if syl > 1 else np.array([])
    edges = np.concatenate([[0.0], edges, [dur]])
    voiced = np.zeros(n)
    f1 = np.zeros(n)
    f2 = np.zeros(n)
    consonant = np.zeros(n)
    for k in range(len(edges) - 1):
        a, b = int(edges[k] * SR), int(edges[k + 1] * SR)
        if b - a < 200:
            continue
        v = VOWELS[rng.integers(len(VOWELS))]
        f1[a:b] = v[0]
        f2[a:b] = v[1]
        seg = np.arange(b - a) / (b - a)
        env = np.sin(np.pi * np.clip(seg * 1.1, 0, 1)) ** 0.6
        voiced[a:b] = env
        c = min(int(0.035 * SR), b - a)
        if rng.random() < 0.7:
            consonant[a:a + c] = np.exp(-np.arange(c) / (c / 4))
    # Formants change per syllable; filter in short blocks with the block's formants.
    out = np.zeros(n)
    block = 512
    for s in range(0, n, block):
        e = min(n, s + block)
        x = source[s:e]
        ff1 = f1[s] if f1[s] > 0 else 500
        ff2 = f2[s] if f2[s] > 0 else 1500
        out[s:e] = resonate(x, ff1, 90) + 0.6 * resonate(x, ff2, 120) + 0.2 * resonate(x, 2600, 200)
    out *= voiced
    out += bandpass(rng.normal(0, 1, n), 2500, 7000) * consonant * 0.35
    # The comm channel: narrow band, clipped, with a bed of static.
    out = bandpass(out, 350, 3200, 3)
    out = out / (np.max(np.abs(out)) + 1e-9)
    drive = 3.5 if shout else 1.8
    out = np.tanh(out * drive) / np.tanh(drive)
    out += bandpass(rng.normal(0, 1, n), 800, 5000) * (0.05 if shout else 0.035)
    return np.concatenate([squelch(), out, squelch(0.07, 0.8)])


def klaxon():
    # Issue #80: a saw-wave "beep beep beep ... pause", not a wail. Three short
    # beeps and a rest, an exact cycle so it loops cleanly. Soft attack and release
    # on each beep (no clicks) and a gentle low-pass so the saw is bright, not harsh.
    beep, gap, rest, f0 = 0.15, 0.09, 0.62, 880.0
    cycle = 3 * beep + 2 * gap + rest
    t = np.arange(int(SR * cycle)) / SR
    saw = 2.0 * ((t * f0) % 1.0) - 1.0
    env = np.zeros_like(t)
    edge = int(0.006 * SR)
    for k in range(3):
        a = int((k * (beep + gap)) * SR)
        b = a + int(beep * SR)
        env[a:b] = 1.0
        env[a:a + edge] *= np.linspace(0, 1, edge)
        env[b - edge:b] *= np.linspace(1, 0, edge)
    x = bandpass(saw, 200, 3500, 2) * env
    return x


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, (d, f0) in enumerate([(0.9, 118), (1.3, 124), (1.7, 112), (1.1, 130)]):
        save("radio_calm_%d.wav" % (i + 1), chatter(d, f0), 0.7)
    for i, (d, f0) in enumerate([(0.6, 150), (0.8, 160), (1.0, 145), (0.7, 170)]):
        save("radio_shout_%d.wav" % (i + 1), chatter(d, f0, True), 0.85)
    save("klaxon_loop.wav", klaxon(), 0.7)


if __name__ == "__main__":
    main()
