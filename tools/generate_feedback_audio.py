"""Generate original, short mechanical UI/combat cues without external samples."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
DEST = Path(__file__).resolve().parents[1] / "audio"
DURATIONS = {"place": 0.16, "connect": 0.32, "armor": 0.36, "reward": 0.65, "combo": 0.28}

for kind, duration in DURATIONS.items():
    rng = random.Random(kind)
    pcm = []
    for i in range(int(RATE * duration)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        if kind in ("place", "armor"):
            low = 125 if kind == "armor" else 260
            sample = (0.32 * math.sin(math.tau * low * t) * math.exp(-t * 25)
                      + noise * 0.18 * math.exp(-t * 80)
                      + 0.10 * math.sin(math.tau * 1133 * t) * math.exp(-t * 15))
        else:
            notes = [440, 554, 660] if kind == "connect" else [330, 440, 554, 660] if kind == "reward" else [554, 830]
            spacing = duration / (len(notes) + 1)
            sample = 0.0
            for index, hz in enumerate(notes):
                age = t - spacing * index
                if age >= 0:
                    sample += (math.sin(math.tau * hz * age)
                               + 0.22 * math.sin(math.tau * hz * 2.37 * age)) * math.exp(-age * 18) * 0.16
            sample += noise * 0.03 * math.exp(-t * 50)
        # Gentle end fade, with no DC offset or hard clipping.
        sample *= min(1.0, (duration - t) / 0.03)
        pcm.append(struct.pack("<h", round(max(-0.95, min(0.95, sample)) * 32767)))
    with wave.open(str(DEST / (kind + ".wav")), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(pcm))
