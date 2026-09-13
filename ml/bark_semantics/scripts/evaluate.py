#!/usr/bin/env python3
"""
Step 4 — measure detection quality on ESC-50 and sweep the config thresholds.

Granularity (stated honestly): ESC-50 is 5 s single-label clips, so this is a
CLIP-LEVEL dog-vs-not-dog measurement — a clip counts as a positive detection
if detect produces >= 1 dog event. ESC-50 has NO vocalization-type labels, so
NO type confusion matrix / Yip / Whimper P-R can be computed from it; that is
reported plainly and deferred to a type-labelled set.

Two phases:
  1) precompute per-clip YAMNet frame features once (cached to .npz-ish pickle),
  2) sweep (gate_combine x threshold x min_event_duration) cheaply over cache.

Run:
  HTTPS_PROXY=... SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
      python3 scripts/evaluate.py
"""
import csv
import os
import pickle
import sys

import numpy as np
import yaml

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import aggregate as agg  # noqa: E402

ESC = os.path.join(HERE, "data", "ESC-50-master")
META = os.path.join(ESC, "meta", "esc50.csv")
AUDIO = os.path.join(ESC, "audio")
CACHE = os.path.join(HERE, "data", "esc50_features.pkl")
CFG = yaml.safe_load(open(os.path.join(HERE, "config.yaml")))
HOP = CFG["model"]["hop_s"]


def precompute():
    if os.path.exists(CACHE):
        return pickle.load(open(CACHE, "rb"))
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
    import tensorflow_hub as hub
    import soundfile as sf
    from scipy.signal import resample_poly
    from math import gcd
    yam = hub.load(CFG["model"]["tfhub_url"])

    rows = list(csv.DictReader(open(META)))
    feats = []
    for i, r in enumerate(rows):
        wav, sr = sf.read(os.path.join(AUDIO, r["filename"]), dtype="float32")
        if wav.ndim > 1:
            wav = wav.mean(axis=1)
        if sr != 16000:
            g = gcd(sr, 16000)
            wav = resample_poly(wav, 16000 // g, sr // g).astype("float32")
        scores = np.asarray(yam(wav)[0])  # [F,521]
        F = scores.shape[0]
        hop = int(round(HOP * 16000))
        win = int(round(CFG["model"]["window_s"] * 16000))
        rms = np.array([
            20 * np.log10(np.sqrt(np.mean(wav[f * hop:f * hop + win] ** 2)) + 1e-10)
            for f in range(F)])
        feats.append({
            "category": r["category"],
            "is_dog": r["category"] == "dog",
            "gate": {"dog": scores[:, 69], "canidae": scores[:, 117],
                     "domestic_animals": scores[:, 68], "animal": scores[:, 67]},
            "type": {"bark": np.maximum(scores[:, 70], scores[:, 73]),
                     "yip": scores[:, 71], "howl": scores[:, 72],
                     "growling": scores[:, 74], "whimper": scores[:, 75]},
            "rms": rms,
        })
        if (i + 1) % 200 == 0:
            print(f"  precomputed {i + 1}/{len(rows)}")
    pickle.dump(feats, open(CACHE, "wb"))
    return feats


def gate_from(f, combine):
    g = f["gate"]
    if combine == "dog_only":
        return g["dog"]
    if combine == "max_dog_canidae":
        return np.maximum(g["dog"], g["canidae"])
    if combine == "max_all":
        return np.max(np.stack([g["dog"], g["canidae"], g["domestic_animals"], g["animal"]]), axis=0)
    raise ValueError(combine)


def eval_config(feats, combine, det_over):
    det = dict(CFG["detection"])
    det.update(det_over)
    cfg = {"detection": det, "arousal": CFG["arousal"]}
    tp = fp = fn = tn = 0
    fp_categories = {}
    for f in feats:
        gate = gate_from(f, combine)
        events = agg.frames_to_events(gate, f["type"], f["rms"], cfg, HOP)
        pred = len(events) > 0
        if f["is_dog"] and pred:
            tp += 1
        elif f["is_dog"] and not pred:
            fn += 1
        elif not f["is_dog"] and pred:
            fp += 1
            fp_categories[f["category"]] = fp_categories.get(f["category"], 0) + 1
        else:
            tn += 1
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    return {"combine": combine, **det_over, "tp": tp, "fp": fp, "fn": fn, "tn": tn,
            "precision": round(prec, 3), "recall": round(rec, 3), "f1": round(f1, 3),
            "fp_categories": dict(sorted(fp_categories.items(), key=lambda x: -x[1]))}


def main():
    feats = precompute()
    n_dog = sum(f["is_dog"] for f in feats)
    print(f"\nESC-50: {len(feats)} clips, {n_dog} dog / {len(feats) - n_dog} non-dog\n")

    print("=== SWEEP: gate_combine x dog_score_threshold (min_dur=0.96) ===")
    results = []
    for combine in ("dog_only", "max_dog_canidae", "max_all"):
        for thr in (0.1, 0.2, 0.3, 0.4, 0.5, 0.6):
            r = eval_config(feats, combine, {"dog_score_threshold": thr})
            results.append(r)
            print(f"  {combine:16s} thr={thr:.2f}  P={r['precision']:.3f} "
                  f"R={r['recall']:.3f} F1={r['f1']:.3f}  (tp{r['tp']} fp{r['fp']} fn{r['fn']})")

    best = max(results, key=lambda r: r["f1"])
    print(f"\nBEST by F1: {best['combine']} thr={best['dog_score_threshold']} "
          f"-> P={best['precision']} R={best['recall']} F1={best['f1']}")
    print("top false-positive categories:", best["fp_categories"])

    # amendment 4: does canidae help the gate? compare at best threshold
    thr = best["dog_score_threshold"]
    print(f"\n=== amendment 4: canidae contribution (thr={thr}) ===")
    for combine in ("dog_only", "max_dog_canidae", "max_all"):
        r = eval_config(feats, combine, {"dog_score_threshold": thr})
        print(f"  {combine:16s} P={r['precision']} R={r['recall']} F1={r['f1']}")

    import json
    json.dump(results, open(os.path.join(HERE, "data", "sweep_results.json"), "w"), indent=2)
    print("\nwrote data/sweep_results.json")


if __name__ == "__main__":
    main()
