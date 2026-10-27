"""Synthesize the rest of the game's sound effects (issue #16). Original, no third-party audio.

Standard library only (no numpy), so it runs on a bare python3. Every sound is a
few lines of oscillators, noise and envelopes; loops are built from whole cycles
and cross-faded end into start, so they repeat without a click.

  coin_gain.wav     two bright pings: credits came in
  coin_spend.wav    one lower clink: credits went out
  jet_loop.wav      the jetpack's roar (loop)
  ship_engine.wav   a ship's engine drone (loop; pitch follows the throttle)
  ship_laser.wav    a ship gun's bolt
  ship_missile.wav  a missile leaving the rail
  ship_hit.wav      a hit on a hull or shield
  ship_boom.wav     a ship blowing up
  droid_beep_N.wav  the sparring remote's chirps (droid talk)
  droid_hum.wav     the sparring remote's hover hum (loop)

Run: python3 tools/audio/make_game_sfx.py
Writes 16-bit mono WAVs to assets/audio/sfx/. Mapping in content/look/sound.json.
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")
rng = random.Random(16)
TAU = 2 * math.pi


def save(name, x, gain=0.8):
    peak = max(abs(v) for v in x) or 1.0
    data = struct.pack("<%dh" % len(x), *(int(v / peak * gain * 32767) for v in x))
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", name, round(len(x) / SR, 2), "s")


def n_of(secs):
    return int(SR * secs)


def noise(n):
    return [rng.uniform(-1, 1) for _ in range(n)]


def lowpass(x, hz):
    # One-pole low-pass.
    a = 1 - math.exp(-TAU * hz / SR)
    y, out = 0.0, []
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def highpass(x, hz):
    lo = lowpass(x, hz)
    return [a - b for a, b in zip(x, lo)]


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def scale(x, g):
    return [v * g for v in x]


def env(n, attack, decay_rate):
    # Linear attack, exponential decay.
    a = max(1, n_of(attack))
    return [min(1.0, i / a) * math.exp(-decay_rate * i / SR) for i in range(n)]


def apply(x, e):
    return [a * b for a, b in zip(x, e)]


def loop_seam(x, fade_secs=0.25):
    # Fade the tail into the head so the loop has no seam; drop the tail.
    f = n_of(fade_secs)
    head, body, tail = x[:f], x[f:-f], x[-f:]
    seam = [tail[i] * (1 - i / f) + head[i] * (i / f) for i in range(f)]
    return body + seam


def ping(freq, secs, decay):
    # A struck metal disc: inharmonic partials, the high ones die first.
    n = n_of(secs)
    out = [0.0] * n
    for ratio, amp, d in [(1.0, 1.0, 1.0), (2.76, 0.5, 1.8), (5.4, 0.25, 3.0), (8.9, 0.12, 4.5)]:
        f = freq * ratio
        for i in range(n):
            out[i] += amp * math.sin(TAU * f * i / SR) * math.exp(-decay * d * i / SR)
    return apply(out, env(n, 0.002, 0.0))


def coin_gain():
    a = ping(1318.5, 0.35, 9.0)
    b = [0.0] * n_of(0.08) + ping(1975.5, 0.45, 7.0)
    save("coin_gain.wav", mix(a, b), 0.7)


def coin_spend():
    a = ping(987.8, 0.4, 10.0)
    b = [0.0] * n_of(0.06) + scale(ping(740.0, 0.4, 11.0), 0.7)
    save("coin_spend.wav", mix(a, b), 0.6)


def jet_loop():
    n = n_of(2.5)
    roar = lowpass(lowpass(noise(n), 900), 1400)
    hiss = scale(highpass(lowpass(noise(n), 5000), 2000), 0.35)
    # A slow flutter in the flame.
    flutter = [0.85 + 0.15 * math.sin(TAU * 6.0 * i / SR) for i in range(n)]
    rumble = [0.5 * math.sin(TAU * 48.0 * i / SR) for i in range(n)]
    save("jet_loop.wav", loop_seam(mix(apply(mix(roar, hiss), flutter), rumble)), 0.7)


def ship_engine():
    secs = 3.0
    n = n_of(secs)
    out = [0.0] * n
    # Two detuned saws (whole cycles in 3 s) beat slowly; a fifth above for body.
    for f, amp in [(55.0, 1.0), (55.0 + 1 / secs, 0.9), (82.5 + 1 / secs, 0.4)]:
        for i in range(n):
            ph = (f * i / SR) % 1.0
            out[i] += amp * (2 * ph - 1)
    out = lowpass(lowpass(out, 420), 600)
    whine = [0.12 * math.sin(TAU * 880.0 * i / SR) for i in range(n)]
    air = scale(lowpass(noise(n), 700), 0.6)
    save("ship_engine.wav", loop_seam(mix(out, whine, air), 0.4), 0.7)


def ship_laser():
    n = n_of(0.22)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = 300 + 1700 * math.exp(-t * 22)
        ph += f / SR
        sq = 1.0 if (ph % 1.0) < 0.5 else -1.0
        out.append(0.6 * sq + 0.4 * math.sin(TAU * ph))
    out = lowpass(out, 5000)
    save("ship_laser.wav", apply(out, env(n, 0.002, 16.0)), 0.6)


def ship_missile():
    n = n_of(0.9)
    out = []
    raw = noise(n)
    y = 0.0
    for i, v in enumerate(raw):
        t = i / SR
        a = 1 - math.exp(-TAU * (600 + 3000 * t) / SR)   # the band opens as it goes
        y += a * (v - y)
        out.append(y)
    thump = [math.sin(TAU * 70 * i / SR) * math.exp(-i / SR * 18) for i in range(n)]
    save("ship_missile.wav", apply(mix(out, thump), env(n, 0.01, 3.5)), 0.7)


def ship_hit():
    n = n_of(0.3)
    crack = apply(highpass(noise(n), 800), env(n, 0.001, 30.0))
    thud = [math.sin(TAU * (90 - 40 * i / n) * i / SR) * math.exp(-i / SR * 14) for i in range(n)]
    save("ship_hit.wav", mix(scale(crack, 0.6), thud), 0.7)


def ship_boom():
    n = n_of(1.8)
    body = apply(lowpass(lowpass(noise(n), 500), 700), env(n, 0.005, 2.6))
    ph, sub = 0.0, []
    for i in range(n):
        ph += (75 * math.exp(-i / SR * 2.0) + 28) / SR
        sub.append(math.sin(TAU * ph) * math.exp(-i / SR * 2.2))
    crack = apply(highpass(noise(n), 1500), env(n, 0.001, 18.0))
    save("ship_boom.wav", mix(body, sub, scale(crack, 0.4)), 0.8)


def droid_beep(idx):
    # A phrase of 3-6 chirps: short tones that glide, like a little machine talking.
    out = []
    for _ in range(rng.randint(3, 6)):
        dur = rng.uniform(0.04, 0.13)
        n = n_of(dur)
        f0, f1 = rng.uniform(900, 2600), rng.uniform(900, 2600)
        ph, seg = 0.0, []
        for i in range(n):
            ph += (f0 + (f1 - f0) * i / n) / SR
            seg.append(math.sin(TAU * ph) + 0.25 * math.sin(TAU * ph * 2))
        e = [min(1.0, i / 60, (n - i) / 60) for i in range(n)]
        out += apply(seg, e) + [0.0] * n_of(rng.uniform(0.01, 0.05))
    save("droid_beep_%d.wav" % idx, out, 0.55)


def droid_hum():
    secs = 2.0
    n = n_of(secs)
    out = []
    for i in range(n):
        t = i / SR
        wob = 1 + 0.3 * math.sin(TAU * 1.5 * t)          # whole cycles in 2 s
        out.append(wob * (math.sin(TAU * 120 * t) + 0.35 * math.sin(TAU * 240 * t) + 0.1 * math.sin(TAU * 361 * t)))
    save("droid_hum.wav", out, 0.5)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    coin_gain()
    coin_spend()
    jet_loop()
    ship_engine()
    ship_laser()
    ship_missile()
    ship_hit()
    ship_boom()
    for k in range(1, 5):
        droid_beep(k)
    droid_hum()
