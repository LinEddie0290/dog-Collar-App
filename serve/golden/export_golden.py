"""Step 3: export golden reference vectors for the collar C log-mel implementation.

For each selected wav, writes under golden/<name>/ :
  input_pcm16.bin        int16 LE PCM @16k mono (collar's raw upload)
  ref_logmel.npy/.bin    ref_logmel.STREAM pre-top_db log-mel [T,64] float32 (row-major)
  frames_first3.{npy,bin}   first 3 windowed frames [3,512] float32
  power_first3.{npy,bin}    first 3 power spectra  [3,257] float32
  mel_first3.{npy,bin}      first 3 mel energies   [3,64]  float32  (pre-log)
  shapes.json            dtype/shape/order for every file
Plus golden/ced_mel_fb_64x257.bin (filterbank CONTRACT — C loads this, does NOT re-derive htk).

The C side computes its own log-mel, then uses golden/compare.py to check it against
ref (per-element error) AND against the classifier (encode_from_logmel cosine / top-1).
"""
from __future__ import annotations
import json, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SERVE = os.path.dirname(HERE)
sys.path.insert(0, SERVE)
import ref_logmel as RL

DATA = "/NVme2/aidi/collar-audio/data_ext"


def _load16k(p):
    import soundfile as sf
    x, sr = sf.read(p, dtype="float32"); x = x.mean(1) if x.ndim > 1 else x
    if sr != 16000:
        from scipy.signal import resample_poly; from math import gcd
        g = gcd(sr, 16000); x = resample_poly(x, 16000 // g, sr // g).astype("float32")
    return x


def _first_dog(cat):
    import csv
    for r in csv.DictReader(open(os.path.join(DATA, "ESC-50-master/meta/esc50.csv"))):
        if r["category"] == cat:
            return os.path.join(DATA, "ESC-50-master/audio", r["filename"])
    return None


def pick_clips():
    """silence, normal bark, clipped-loud bark, + snoring + cough (varied)."""
    sr = 16000
    out = []
    out.append(("silence", np.zeros(2 * sr, np.float32)))
    bark = _load16k(_first_dog("dog"))[: 2 * sr]
    bark = np.pad(bark, (0, max(0, 2 * sr - len(bark))))
    out.append(("bark_normal", bark.astype(np.float32)))
    out.append(("bark_clipped", np.clip(bark * 16.0, -1.0, 1.0).astype(np.float32)))
    import csv
    man = {r["class"]: os.path.join("/NVme2/aidi/collar-audio", r["path"])
           for r in csv.DictReader(open(os.path.join(DATA, "dog_health/manifest.csv")))}
    for cls in ("snoring", "cough"):
        if cls in man and os.path.isfile(man[cls]):
            x = _load16k(man[cls])[: 2 * sr]
            out.append((cls, np.pad(x, (0, max(0, 2 * sr - len(x)))).astype(np.float32)))
    return out


def _dump(d, name, arr):
    np.save(os.path.join(d, name + ".npy"), arr)
    arr.astype(np.float32).tofile(os.path.join(d, name + ".bin"))


def main():
    # filterbank contract (copy next to the golden set)
    fb = np.load(os.path.join(SERVE, "ced_mel_fb_257x64.npy")).astype(np.float32)
    fb.T.copy().tofile(os.path.join(HERE, "ced_mel_fb_64x257.bin"))
    for name, x in pick_clips():
        d = os.path.join(HERE, name); os.makedirs(d, exist_ok=True)
        (np.clip(x, -1, 1) * 32768.0).astype("<i2").tofile(os.path.join(d, "input_pcm16.bin"))
        dbg = RL.stream_debug(x, n_frames=3)
        _dump(d, "ref_logmel", dbg["logmel_pre_top_db"])          # [T,64]
        _dump(d, "frames_first3", dbg["windowed_frames"])          # [3,512]
        _dump(d, "power_first3", dbg["power_spectrum"])            # [3,257]
        _dump(d, "mel_first3", dbg["mel_energy"])                  # [3,64]
        json.dump({"input_pcm16.bin": {"dtype": "int16_le", "shape": [len(x)], "scale": "x_float*32768"},
                   "ref_logmel": {"dtype": "float32_le", "shape": list(dbg["logmel_pre_top_db"].shape),
                                  "order": "row-major [T,64], PRE-top_db (10*log10(max(mel,1e-10)))"},
                   "frames_first3": {"dtype": "float32_le", "shape": list(dbg["windowed_frames"].shape),
                                     "order": "[frame,512] after hann-periodic window, center reflect pad"},
                   "power_first3": {"dtype": "float32_le", "shape": list(dbg["power_spectrum"].shape),
                                    "order": "[frame,257] |rfft|^2"},
                   "mel_first3": {"dtype": "float32_le", "shape": list(dbg["mel_energy"].shape),
                                  "order": "[frame,64] power @ fb (pre-log)"},
                   "fb_contract": "../ced_mel_fb_64x257.bin [64,257] float32 row-major"},
                  open(os.path.join(d, "shapes.json"), "w"), indent=1)
        print(f"wrote golden/{name}/  T={dbg['logmel_pre_top_db'].shape[0]}", flush=True)
    print("fb contract: golden/ced_mel_fb_64x257.bin [64,257] float32")


if __name__ == "__main__":
    main()
