"""Build the game's edited audio from the separately archived licensed sources.

Usage: python build_audio.py --sources <download folder>
Requires numpy, scipy, soundfile and imageio-ffmpeg. Never downloads or overwrites sources.
"""
import argparse
import hashlib
import json
import subprocess
import shutil
import tempfile
from pathlib import Path

import imageio_ffmpeg
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 44100
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
PROJECT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--sources", required=True, type=Path)
args = parser.parse_args()
SOURCE = args.sources
OUTPUT = PROJECT / "assets/audio"
RECORDS = []
RNG = np.random.default_rng(20261028)


def decode(path):
    raw = subprocess.check_output([FFMPEG, "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"])
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def filtered(data, low=70, high=7000):
    return sosfilt(butter(2, [low, high], btype="bandpass", fs=SR, output="sos"), data, axis=0).astype(np.float32)


def loop(data, seconds, fade=0.8, start=0):
    n, f, offset = int(seconds * SR), int(fade * SR), int(start * SR)
    x = data[offset:offset + n + f].copy()
    if len(x) < n + f:
        x = np.tile(x, (int(np.ceil((n + f) / len(x))), 1))[:n + f]
    t = np.linspace(0, 1, f)[:, None]
    y = x[:n].copy()
    y[:f] = x[n:n + f] * (1 - t) + x[:f] * t
    return y


def envelope(data, fade_in=0.008, fade_out=0.04):
    x = data.copy()
    a, b = min(int(fade_in * SR), len(x) // 2), min(int(fade_out * SR), len(x) // 2)
    if a:
        x[:a] *= np.linspace(0, 1, a)[:, None]
    if b:
        x[-b:] *= np.linspace(1, 0, b)[:, None]
    return x


def info(author, page, license="CC0-1.0", original=""):
    return {"author": author, "source_page": page, "license": license, "original_file": original}


def write(name, data, origin, processing, rms_db=None, peak_db=-8):
    data = data.astype(np.float32)
    data -= np.mean(data, axis=0)
    peak = float(np.max(np.abs(data)))
    gain = 10 ** (peak_db / 20) / max(peak, 1e-8)
    if rms_db is not None:
        rms = float(np.sqrt(np.mean(data ** 2)))
        gain = min(gain, 10 ** (rms_db / 20) / max(rms, 1e-8))
    data *= gain
    path = OUTPUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".ogg":
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / "source.wav"
            sf.write(wav, data, SR, subtype="PCM_24")
            subprocess.run([FFMPEG, "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5", str(path)], check=True)
    else:
        sf.write(path, data.mean(axis=1), SR, subtype="PCM_16")
    result = decode(path)
    record = {"file": name, **origin, "processing": processing, "seconds": round(len(result) / SR, 4), "peak_dbfs": round(20 * np.log10(max(float(np.abs(result).max()), 1e-9)), 2), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    if name.endswith(".ogg") and name != "music/ready.ogg":
        record["seam_jump"] = round(float(np.abs(result[-1] - result[0]).max()), 6)
    RECORDS.append(record)


def kenney(pack, filename):
    matches = list((SOURCE / pack).rglob(filename))
    assert len(matches) == 1, (pack, filename, matches)
    return decode(matches[0])


def foley(name, pack, filename, high=6500, seconds=None):
    data = filtered(kenney(pack, filename), high=high)
    if seconds:
        data = data[:int(seconds * SR)]
    slug = "rpg-audio" if pack == "50-rpg-sound-effects" else pack.removesuffix("-official")
    write("sfx/" + name + ".wav", envelope(data), info("Kenney", "https://kenney.nl/assets/" + slug, original=filename), "Band-pass, short edge fades, mono conversion, peak normalization")


def tone(notes, duration, spacing=0.12, decay=0.22):
    result = np.zeros((int(duration * SR), 2), np.float32)
    for i, midi in enumerate(notes):
        offset = int(i * spacing * SR)
        if offset >= len(result):
            break
        t = np.arange(len(result) - offset) / SR
        f = 440 * 2 ** ((midi - 69) / 12)
        sound = (np.sin(2 * np.pi * f * t) + 0.22 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 12)) * np.exp(-t / decay)
        sound *= np.minimum(t / 0.006, 1)
        result[offset:] += sound[:, None] * 0.15
    return envelope(result, 0.006, 0.08)


generated = info("Original procedural sound design for this project", "tools/audio/build_audio.py", "Project original; no third-party samples")
metadata = json.loads((SOURCE / "music_metadata.json").read_text(encoding="utf-8"))
music = [("Carefree", "island_morning", 96, 32, 10), ("Local Forecast - Elevator", "forecast_office", 82, 32, 8), ("Easy Lemon", "prepare_again", 82, 32, 8)]
for title, name, bpm, bars, start in music:
    meta = next(x for x in metadata if x["title"] == title)
    assert "voice" not in meta["instruments"].lower()
    data = filtered(decode(SOURCE / meta["filename"]), high=10500)
    data = loop(data, bars * 4 * 60 / bpm, 60 / bpm, start)
    write("music/" + name + ".ogg", data, info("Kevin MacLeod", "https://incompetech.com/music/royalty-free/index.html?isrc=" + meta["isrc"], "CC-BY-4.0", meta["filename"]), f"{bars}-bar edited loop; {start}s source offset; one-beat cyclic crossfade; equalization; constant gain", rms_db=-22, peak_db=-5)

natural = {
    "wind": info("Nox_Sound", "https://freesound.org/people/Nox_Sound/sounds/530908/", original="530908_9250976-hq.mp3"),
    "waves": info("SamsterBirdies", "https://freesound.org/people/SamsterBirdies/sounds/578524/", original="578524_5487341-hq.mp3"),
    "rain": info("deadrobotmusic", "https://freesound.org/people/deadrobotmusic/sounds/549909/", original="549909_11532701-hq.mp3"),
    "bird": info("organicmanpl", "https://freesound.org/people/organicmanpl/sounds/518749/", original="518749 HQ preview"),
}
wind, waves, rain = (decode(SOURCE / (k + ".mp3")) for k in ["wind", "waves", "rain"])
for name, source, origin, lo, hi in [
    ("island_wind", wind, "wind", 140, 5500),
    ("shore", waves, "waves", 100, 6000),
    ("rain", rain, "rain", 180, 6500),
    ("storm_wind", wind, "wind", 90, 2200),
    ("boat_water", waves, "waves", 180, 4200),
]:
    data = loop(filtered(source, lo, hi), 30, 1, 2)
    write("ambience/" + name + ".ogg", data, natural[origin], "HQ preview; 30s cyclic crossfade; band-pass; constant gain", rms_db=-27, peak_db=-10)
t = np.arange(30 * SR) / SR
noise = filtered(RNG.normal(0, 0.1, (len(t), 2)), 100, 1300)
hum = noise + (0.008 * np.sin(2 * np.pi * 120 * t) + 0.003 * np.sin(2 * np.pi * 240 * t))[:, None]
write("ambience/equipment.ogg", loop(hum, 29, 0.8), generated, "Filtered noise and quiet electrical harmonics, cyclic crossfade", rms_db=-31, peak_db=-14)

for material, prefix, count in [("soft", "grass", 4), ("wood", "wood", 3), ("hard", "concrete", 3)]:
    for i in range(count):
        foley(f"step_{material}_{i+1:02d}", "impact-sounds-official", f"footstep_{prefix}_{i:03d}.ogg", high=5000)
for i in range(3):
    foley(f"harvest_{i+1:02d}", "50-rpg-sound-effects", f"cloth{i+1}.ogg", high=6500, seconds=0.6)
    write(f"sfx/pickup_{i+1:02d}.wav", tone([76+i, 83+i], 0.3), generated, "Original two-note pickup chime")
for i in range(2):
    foley(f"land_{i+1:02d}", "impact-sounds-official", f"impactSoft_medium_{i:03d}.ogg", high=3500)
    foley(f"deposit_{i+1:02d}", "impact-sounds-official", f"impactWood_light_{i:03d}.ogg", high=3000)
for name, filename in [("door_open", "doorOpen_1.ogg"), ("door_close", "doorClose_1.ogg"), ("chest_open", "creak1.ogg"), ("chest_close", "bookClose.ogg"), ("throw", "clothBelt.ogg")]:
    foley(name, "50-rpg-sound-effects", filename, high=4000, seconds=0.65)
work = loop(filtered(kenney("50-rpg-sound-effects", "cloth4.ogg"), high=5000), 0.6, 0.08)
write("sfx/harvest_work.wav", work, info("Kenney", "https://kenney.nl/assets/rpg-audio", original="cloth4.ogg"), "Short cyclic cloth/leaf texture; band-pass; mono conversion", rms_db=-25, peak_db=-13)
for name, notes, duration in [("data_open", [72, 79], 0.45), ("data_done", [76, 79, 84], 0.65), ("data_all", [72, 76, 79, 84], 0.9), ("task", [79, 84], 0.4), ("warning", [67, 65], 0.9), ("happy", [76, 79, 84], 0.5), ("surprised", [84, 88], 0.3), ("angry", [55, 54], 0.35), ("awkward", [69, 65], 0.45)]:
    write("sfx/" + name + ".wav", tone(notes, duration), generated, "Original soft struck-tone cue; no vocal samples")
write("sfx/data_absorb.wav", loop(tone([84, 79, 88, 83, 86, 81], 1.3, 0.16, 0.12), 1.0, 0.15), generated, "Original sparse electronic particles; cyclic crossfade", rms_db=-25, peak_db=-12)
click = kenney("interface-sounds-official", "click_001.ogg")
keyboard = np.zeros((int(0.7 * SR), 2), np.float32)
for offset in [0, 0.12, 0.3, 0.46]:
    start = int(offset * SR)
    length = min(len(click), len(keyboard) - start)
    keyboard[start:start+length] += click[:length]
write("sfx/keyboard.wav", envelope(filtered(keyboard, high=4800)), info("Kenney", "https://kenney.nl/assets/interface-sounds", original="click_001.ogg"), "Four sparse clicks, filtered and mixed")
bird = filtered(decode(SOURCE / "bird.mp3"), 900, 7500)
for i, segment in enumerate(np.array_split(bird, 2)):
    energy = np.convolve(np.mean(segment[::441] ** 2, axis=1), np.ones(30), mode="valid")
    offset = max(0, int(np.argmax(energy) * 441) - int(0.3 * SR))
    write(f"sfx/bird_{i+1:02d}.wav", envelope(segment[offset:offset+int(2 * SR)], 0.05, 0.15), natural["bird"], "HQ preview; isolated 2s bird phrase, filtered; mono conversion", peak_db=-14)
ending = tone([72, 76, 79, 84, 79, 76, 84], 5.2, 0.32, 0.7)
ending += tone([48, 55, 60], 5.2, 0.05, 1.4) * 0.35
write("music/ready.ogg", ending, generated, "Original 5.2s major-key ending motif; non-looping", rms_db=-24, peak_db=-6)

# Only explicitly user-approved auditions override the baseline assets.
approved = json.loads((PROJECT / "tools/audio/approved_candidates.json").read_text(encoding="utf-8"))
for entry in approved:
    source = SOURCE.parent / "auditions_round2" / entry["candidate"]
    target = OUTPUT / entry["file"]
    shutil.copyfile(source, target)
    result, rate = sf.read(target, always_2d=True)
    record = {key: value for key, value in entry.items() if key != "candidate"}
    record.update({"original_file": entry["candidate"], "seconds": round(len(result) / rate, 5), "peak_dbfs": round(float(20 * np.log10(np.abs(result).max())), 2), "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    RECORDS = [row for row in RECORDS if row["file"] != record["file"]]
    RECORDS.append(record)

(OUTPUT / "manifest.json").write_text(json.dumps(RECORDS, ensure_ascii=False, indent=2), encoding="utf-8")
licenses = OUTPUT / "licenses"
licenses.mkdir(exist_ok=True)
for pack in ["impact-sounds-official", "interface-sounds-official", "50-rpg-sound-effects"]:
    texts = [p for p in (SOURCE / pack).rglob("*.txt") if "license" in p.name.lower()]
    for i, path in enumerate(texts):
        (licenses / f"{pack}-{i}.txt").write_bytes(path.read_bytes())
print(json.dumps({"files": len(RECORDS), "size_mb": round(sum((OUTPUT / r['file']).stat().st_size for r in RECORDS) / 1048576, 2), "max_peak_dbfs": max(r['peak_dbfs'] for r in RECORDS), "max_loop_seam_jump": max(r.get('seam_jump', 0) for r in RECORDS)}, ensure_ascii=False))
