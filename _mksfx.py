#!/usr/bin/env python3
"""Throwaway: synthesise the game's sound effects. Not part of the build.

FlowMusic2API is a music generator and ignores `duration`, so it cannot make a
200ms die-clack. These are cheaper anyway -- a few KB each, no licence, and the
timing is exact rather than whatever a 3-minute render happened to contain.

  python3 _mksfx.py     # writes audio/*.wav; then ffmpeg to .ogg (see below)

Stdlib only. Then convert, because Godot imports ogg/mp3 and a raw wav is ~6x
larger for no gain here:
  for f in audio/*.wav; do ffmpeg -v error -y -i "$f" -c:a libvorbis -q:a 2 \\
      -ar 44100 -ac 1 "${f%.wav}.ogg"; done
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audio")


def env(attack, decay, t):
    """Exponential decay with a short attack, so nothing starts with a click."""
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-t / decay)


def write(name, samples, peak=0.85):
    m = max(1e-9, max(abs(s) for s in samples))
    scale = peak / m
    # Fade the last 6ms. Every note here is a damped sine, so the file ends
    # still ringing -- win/lose were stopping at -27dB, which is a soft tick
    # at the cut on any speaker with a little bottom end.
    tail = int(0.006 * RATE)
    for i in range(tail):
        samples[-tail + i] *= 1.0 - i / tail
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32000)) for s in samples))
    print("%-10s %5.2fs %6d B" % (name, len(samples) / RATE, os.path.getsize(path)))


def struck(dur, decay, f0, f1, noise, rng, ring=0.0, ring_decay=0.0):
    """A struck surface: a noise transient plus a ring whose pitch drops as it
    decays. That drop is most of what makes it read as an impact rather than a
    beep -- a fixed-pitch sine is a beep no matter how loud it is."""
    n = int(dur * RATE)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        f = f0 + (f1 - f0) * (t / dur)
        ph += 2 * math.pi * f / RATE
        s = noise * rng.uniform(-1, 1) * math.exp(-t / decay)
        if ring:
            s += ring * math.sin(ph) * math.exp(-t / ring_decay)
        out.append(s)
    return out


def tone(dur, freqs, decay, rng, detune=0.0):
    """One or more partials sharing an envelope -- a struck bar, not a beep.
    Amplitudes fall as 1/k so the fundamental dominates and it stays pitched."""
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for k, f in enumerate(freqs):
            v = f * (1.0 + detune * rng.uniform(-1, 1))
            s += math.sin(2 * math.pi * v * t) / (k + 1.6)
        out.append(s * env(0.004, decay, t))
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for l in layers:
        for i, s in enumerate(l):
            out[i] += s
    return out


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def silence(dur):
    return [0.0] * int(dur * RATE)


rng = random.Random(20260929)
os.makedirs(OUT, exist_ok=True)

# Dice hitting the tray. Several impacts at decreasing volume: a handful of
# dice lands as a scatter of clacks, not one hit.
roll = []
for k in range(7):
    at = int((0.02 + 0.055 * k + rng.uniform(0, 0.03)) * RATE)
    while len(roll) < at:
        roll.append(0.0)
    hit = struck(0.09, 0.010, rng.uniform(900, 2400), rng.uniform(500, 1100),
                 0.55, rng, ring=0.45, ring_decay=0.018)
    roll.extend(h * (0.9 ** k) for h in hit)
roll.extend(silence(0.05))
write("roll", roll)

# Queueing a die: one short wooden tick, right at the surface, no tail.
write("tap", struck(0.07, 0.007, 1500, 800, 0.7, rng, ring=0.35, ring_decay=0.010))

# A hit landing on you. Low, with a body thud under the transient.
write("hurt", mix(
    struck(0.26, 0.055, 220, 70, 0.40, rng, ring=0.55, ring_decay=0.050),
    [s * 0.5 for s in tone(0.30, [55, 82], 0.070, rng)],
))

# A hit landing on the enemy. Brighter and shorter than being hit, so the two
# are tellable apart with your eyes shut.
write("strike", mix(
    struck(0.20, 0.035, 1600, 420, 0.60, rng, ring=0.50, ring_decay=0.030),
    [s * 0.35 for s in tone(0.22, [330, 495], 0.045, rng)],
))

# Block: a rising fifth. The one upward gesture in the set. The decay has to
# outrun the 0.34s note -- at 0.13 it was still ringing when the file stopped.
write("block", mix(
    tone(0.34, [392, 587], 0.075, rng, detune=0.004),
    struck(0.10, 0.012, 2400, 1100, 0.30, rng),
))

# Winning the fight: a rising major triad, struck like a bar.
write("win", seq(
    tone(0.45, [523, 784, 1046], 0.20, rng),
    tone(0.45, [659, 988, 1318], 0.20, rng),
    tone(0.75, [784, 1175, 1568], 0.22, rng),
))

# Losing the run: the same shape inverted, so it reads as the other outcome
# rather than as an unrelated sound.
write("lose", seq(
    tone(0.50, [392, 523], 0.24, rng),
    tone(0.50, [330, 440], 0.24, rng),
    tone(0.90, [262, 330, 392], 0.26, rng),
))

print("\nconvert with:")
print('  for f in audio/*.wav; do ffmpeg -v error -y -i "$f" '
      '-c:a libvorbis -q:a 2 -ar 44100 -ac 1 "${f%.wav}.ogg"; done')
