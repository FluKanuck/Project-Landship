"""
Generate every sound in the wedge.

  * Crew callouts: Piper neural TTS (offline, open voices) through a radio chain in sox.
  * Crew chatter: the same voices, muffled and quiet, for the murmur in the pits.
  * Bridge ambience and UI sounds: synthesised here with numpy.

    pip install piper-tts numpy ; apt install sox ffmpeg
    python3 tools/audio/generate_audio.py --voices /opt/voices

Output: assets/audio/*.ogg and assets/audio/lines.json (text for the comms log).
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 22050

VOICES = {
    "sensors": "en_GB-alan-medium",
    "flight": "en_GB-jenny_dioco-medium",
    "comms": "en_GB-northern_english_male-medium",
    "helm": "en_GB-cori-medium",
    "xo": "en_US-ryan-medium",
    "crew_a": "en_US-amy-medium",
}
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]


def bearing_words(b):
    return " ".join(DIGITS[int(c)] for c in "%03d" % b)


def callouts():
    lines = {}
    for b in range(0, 360, 10):
        lines[f"contact_{b:03d}"] = ("sensors", f"Contact. Bearing {bearing_words(b)}.")
        lines[f"multi_{b:03d}"] = ("sensors", f"Multiple contacts. Bearing {bearing_words(b)}.")
    lines.update({
        "contact_lost_a": ("sensors", "Contact lost."),
        "contact_lost_b": ("sensors", "Lost him. Marking last known."),
        "contact_class": ("sensors", "Contact classified. Light raider. Hover drive."),
        "node_found": ("sensors", "Sensors. Alien structure in sight. Looks like a recharge node."),
        "burst": ("sensors", "Data burst received. Updating the plot."),
        "xo_boot": ("xo", "Commander on the bridge."),
        "xo_ready": ("xo", "All stations report ready. Swift one and two are fuelled on deck."),
        "xo_tc": ("xo", "Dropping time compression."),
        "xo_alert_on": ("xo", "Action stations. Action stations."),
        "xo_alert_off": ("xo", "Stand down from action stations."),
        "xo_hint_launch": ("xo", "Commander, plot a route on the tactical screen, then launch a Swift."),
        "xo_hint_time": ("xo", "Long legs out there. Time compression is on the helm panel."),
        "xo_objective": ("xo", "Intelligence says the raiders run from a base somewhere in this sector. Find it."),
        "xo_objective_done": ("xo", "That's their nest. Good work, commander. Keep eyes on it."),
        "cannot_launch": ("flight", "Negative. That bird is not ready."),
        "rebuild": ("flight", "Fabrication has started a replacement Swift."),
        "rebuilt": ("flight", "Replacement Swift is on deck."),
        "locked": ("comms", "No link, commander. We can't send her new orders."),
        "helm_0": ("helm", "Helm, all stop."),
        "helm_1": ("helm", "Helm, silent crawl."),
        "helm_2": ("helm", "Helm, ahead cruise."),
        "helm_3": ("helm", "Helm, ahead flank."),
        "helm_course": ("helm", "Course laid in."),
        "helm_done": ("helm", "Helm. Course complete. All stop."),
        "helm_limit": ("helm", "Helm. Survey limit ahead. All stop."),
        "helm_restart": ("helm", "Breaking her out of the sand. That cost us some fuel."),
    })
    for n, w in ((1, "one"), (2, "two")):
        lines.update({
            f"launch_{n}": ("flight", f"Swift {w}, launching."),
            f"station_{n}": ("flight", f"Swift {w}, on station."),
            f"loiter_{n}": ("flight", f"Swift {w}, loitering."),
            f"scan_{n}": ("flight", f"Swift {w}, scanning."),
            f"rtb_{n}": ("flight", f"Swift {w}, returning to carrier."),
            f"bingo_{n}": ("flight", f"Swift {w}, bingo fuel. Coming home."),
            f"recovered_{n}": ("flight", f"Swift {w} recovered. Refuelling."),
            f"ready_{n}": ("flight", f"Swift {w}, ready on deck."),
            f"fire_{n}": ("flight", f"Swift {w} is taking fire!"),
            f"breaking_{n}": ("flight", f"Swift {w}, breaking off!"),
            f"damage_{n}": ("flight", f"Swift {w} is hit. Still flying."),
            f"lost_{n}": ("flight", f"We've lost Swift {w}."),
            f"weak_{n}": ("comms", f"Swift {w}, signal getting weak."),
            f"linklost_{n}": ("comms", f"Link lost with Swift {w}. She's flying on her last orders."),
            f"linkback_{n}": ("comms", f"Link restored with Swift {w}."),
        })
    return lines


CHATTER = [
    "Coolant pressure is nominal.", "Track six, temperature steady.", "Copy that.", "Checking.",
    "Fabricator is idle.", "Rotating the plot.", "Updating the grid.", "Filter two reset.",
    "Roger, standing by.", "Dust count is rising.", "Logging it.", "Sector clear.",
    "Say again?", "Confirm, frequency two.", "Hull sensors green.", "Power bus stable.",
    "Running the check now.", "Got it.", "Negative, still nothing.", "Wind's picking up from the west.",
    "Hangar reports ready.", "Sand in the intakes again.", "Marking it on the board.", "Stand by one.",
]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(" ".join(cmd), r.stderr, file=sys.stderr)
        raise SystemExit(1)


def tts(text, voice, path, voices_dir, length=1.0):
    model = os.path.join(voices_dir, voice + ".onnx")
    p = subprocess.run([sys.executable, "-m", "piper", "-m", model, "-f", path, "--length-scale", str(length)],
                       input=text, capture_output=True, text=True)
    if p.returncode != 0:
        print(p.stderr, file=sys.stderr)
        raise SystemExit(1)


def to_ogg(wav, name, q=3):
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-ac", "1", "-ar", str(SR), "-c:a", "libvorbis", "-q:a", str(q),
         os.path.join(OUT, name + ".ogg")])


def radio(src, dst, tmp):
    noise = os.path.join(tmp, "n.wav")
    run(["sox", "-n", "-r", str(SR), "-c", "1", noise, "synth", "0.07", "whitenoise", "vol", "0.08"])
    body = os.path.join(tmp, "b.wav")
    run(["sox", src, "-r", str(SR), "-c", "1", body, "highpass", "320", "lowpass", "3300", "overdrive", "8",
         "compand", "0.01,0.15", "-60,-60,-30,-14,-10,-8,0,-5", "gain", "-3", "pad", "0.03", "0.05"])
    run(["sox", noise, body, noise, dst])


def murmur(src, dst):
    run(["sox", src, "-r", str(SR), "-c", "1", dst, "lowpass", "1500", "reverb", "40", "50", "60",
         "gain", "-10", "pad", "0", "0.4"])


# ------------------------------------------------------------------ synthesis

def write_wav(path, data):
    data = np.clip(data, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype(np.int16).tobytes())


def loopable(sig, fade=0.5):
    n = int(fade * SR)
    out = sig[n:].copy()
    out[-n:] = out[-n:] * np.linspace(1, 0, n) + sig[:n] * np.linspace(0, 1, n)
    return out


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def env(n, a=0.005, r=0.1):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / max(r, 1e-4))
    return e


def synth_all(tmp):
    rng = np.random.default_rng(3)
    T = lambda s: np.arange(int(s * SR)) / SR  # noqa: E731

    # bridge hum: two low tones, slow beating, plus filtered rumble
    t = T(10.5)
    hum = 0.22 * np.sin(2 * np.pi * 47 * t) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.21 * t))
    hum += 0.12 * np.sin(2 * np.pi * 94.3 * t) + 0.05 * np.sin(2 * np.pi * 141 * t + 1)
    br = np.cumsum(rng.normal(0, 1, len(t)))
    br = br - np.convolve(br, np.ones(400) / 400, mode="same")
    hum += 0.012 * br / (np.abs(br).max() + 1e-9) * 6
    write_wav(os.path.join(tmp, "hum.wav"), loopable(hum * 0.8))
    to_ogg(os.path.join(tmp, "hum.wav"), "amb_hum")

    # air handling
    t = T(8.5)
    wn = rng.normal(0, 1, len(t))
    air = lowpass(wn, 1400) - lowpass(wn, 250)
    air *= 0.5 * (0.85 + 0.15 * np.sin(2 * np.pi * 0.13 * t))
    write_wav(os.path.join(tmp, "air.wav"), loopable(air / (np.abs(air).max() + 1e-9) * 0.3))
    to_ogg(os.path.join(tmp, "air.wav"), "amb_air")

    # tracks: deep rhythmic rumble of the landship moving
    t = T(9.8)
    rum = lowpass(rng.normal(0, 1, len(t)), 90)
    rum = rum / (np.abs(rum).max() + 1e-9)
    clank = np.zeros_like(t)
    for k in np.arange(0.0, 9.8, 0.7):
        i = int(k * SR)
        n = int(0.25 * SR)
        seg = lowpass(rng.normal(0, 1, n), 260) * env(n, 0.002, 0.06)
        clank[i:i + n] += seg[: len(clank[i:i + n])] * 3
    trk = rum * 0.6 + clank * 0.5 + 0.2 * np.sin(2 * np.pi * 31 * t)
    write_wav(os.path.join(tmp, "trk.wav"), loopable(trk / (np.abs(trk).max() + 1e-9) * 0.6))
    to_ogg(os.path.join(tmp, "trk.wav"), "amb_tracks")

    # UI: beep, ok, error
    def tone(freqs, dur, shape="sine", r=0.08):
        n = int(dur * SR)
        tt = np.arange(n) / SR
        out = np.zeros(n)
        seg = n // len(freqs)
        for i, f in enumerate(freqs):
            s = slice(i * seg, (i + 1) * seg if i < len(freqs) - 1 else n)
            ph = 2 * np.pi * f * tt[s]
            out[s] = np.sin(ph) if shape == "sine" else np.sign(np.sin(ph)) * 0.6
        return out * env(n, 0.003, r)

    write_wav(os.path.join(tmp, "b.wav"), tone([1250], 0.07) * 0.5)
    to_ogg(os.path.join(tmp, "b.wav"), "ui_beep")
    write_wav(os.path.join(tmp, "b.wav"), tone([880, 1320], 0.16, r=0.2) * 0.45)
    to_ogg(os.path.join(tmp, "b.wav"), "ui_ok")
    write_wav(os.path.join(tmp, "b.wav"), tone([520, 330], 0.22, "square", r=0.25) * 0.35)
    to_ogg(os.path.join(tmp, "b.wav"), "ui_err")

    # chunky mechanical button
    n = int(0.18 * SR)
    clk = lowpass(rng.normal(0, 1, n), 2500) * env(n, 0.001, 0.02) * 0.8
    clk += np.sin(2 * np.pi * 110 * np.arange(n) / SR) * env(n, 0.002, 0.05) * 0.6
    write_wav(os.path.join(tmp, "b.wav"), clk)
    to_ogg(os.path.join(tmp, "b.wav"), "ui_button")

    # contact ping
    n = int(1.6 * SR)
    tt = np.arange(n) / SR
    ping = (np.sin(2 * np.pi * 980 * tt) + 0.4 * np.sin(2 * np.pi * 1960 * tt)) * np.exp(-tt * 4.0)
    ping += 0.35 * np.roll(ping, int(0.28 * SR)) + 0.15 * np.roll(ping, int(0.56 * SR))
    write_wav(os.path.join(tmp, "b.wav"), ping * 0.35)
    to_ogg(os.path.join(tmp, "b.wav"), "sfx_contact")

    # klaxon
    n = int(1.8 * SR)
    tt = np.arange(n) / SR
    f = np.where((tt % 0.45) < 0.225, 520, 690)
    ph = 2 * np.pi * np.cumsum(f) / SR
    kl = lowpass((2 * ((ph / (2 * np.pi)) % 1) - 1), 1800) * 0.6
    kl *= np.minimum(1, tt / 0.02) * np.minimum(1, (1.8 - tt) / 0.1)
    write_wav(os.path.join(tmp, "b.wav"), kl)
    to_ogg(os.path.join(tmp, "b.wav"), "sfx_klaxon")

    # time compression drop: falling sweep
    n = int(0.9 * SR)
    tt = np.arange(n) / SR
    f = 900 * np.exp(-tt * 2.2) + 120
    sw = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.01, 0.5) * 0.4
    write_wav(os.path.join(tmp, "b.wav"), sw)
    to_ogg(os.path.join(tmp, "b.wav"), "sfx_tc_drop")

    # rising sweep for speeding up
    f = 200 + 700 * (tt / tt[-1]) ** 2
    sw = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.05, 0.4) * 0.25
    write_wav(os.path.join(tmp, "b.wav"), sw)
    to_ogg(os.path.join(tmp, "b.wav"), "sfx_tc_up")

    # static (no signal)
    t = T(3.2)
    st = rng.normal(0, 1, len(t))
    st = lowpass(st, 5000) * 0.25 * (0.8 + 0.2 * np.sin(2 * np.pi * 13 * t))
    write_wav(os.path.join(tmp, "b.wav"), loopable(st))
    to_ogg(os.path.join(tmp, "b.wav"), "sfx_static")

    # console blips for ambience
    for i in range(4):
        fs = rng.choice([700, 900, 1100, 1500, 1800], size=rng.integers(1, 4))
        write_wav(os.path.join(tmp, "b.wav"), tone(list(fs), 0.05 * len(fs), r=0.03) * 0.25)
        to_ogg(os.path.join(tmp, "b.wav"), f"amb_blip_{i}")

    # gunfire, far away (heard over the drone link)
    n = int(0.5 * SR)
    g = np.zeros(n)
    for k in range(4):
        i = int(k * 0.09 * SR)
        m = int(0.08 * SR)
        g[i:i + m] += lowpass(rng.normal(0, 1, m), 1500) * env(m, 0.001, 0.02)
    write_wav(os.path.join(tmp, "b.wav"), g * 0.6)
    to_ogg(os.path.join(tmp, "b.wav"), "sfx_burst")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--voices", default="/opt/voices")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    meta = {"lines": {}, "chatter": []}
    with tempfile.TemporaryDirectory() as tmp:
        if a.only in ("", "synth"):
            synth_all(tmp)
        if a.only in ("", "voice"):
            for key, (role, text) in callouts().items():
                raw = os.path.join(tmp, "raw.wav")
                tts(text, VOICES[role], raw, a.voices, length=0.92)
                proc = os.path.join(tmp, "proc.wav")
                radio(raw, proc, tmp)
                to_ogg(proc, "vo_" + key)
                meta["lines"][key] = {"role": role, "text": text}
            roles = list(VOICES.keys())
            for i, text in enumerate(CHATTER):
                role = roles[i % len(roles)]
                raw = os.path.join(tmp, "raw.wav")
                tts(text, VOICES[role], raw, a.voices, length=1.05)
                proc = os.path.join(tmp, "m.wav")
                murmur(raw, proc)
                to_ogg(proc, f"chat_{i:02d}", q=1)
                meta["chatter"].append(text)
            with open(os.path.join(OUT, "lines.json"), "w") as f:
                json.dump(meta, f, indent=1)
    print("audio done:", len(os.listdir(OUT)), "files")


if __name__ == "__main__":
    main()
