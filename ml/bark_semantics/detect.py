#!/usr/bin/env python3
"""
detect.py — audio file in, dog-vocalization event JSON out.

Pipeline:  audio -> 16 kHz mono -> YAMNet (521-dim/frame) -> gate/type/rms per
frame -> aggregate.frames_to_events -> event list (JSON).

Everything tunable lives in config.yaml. The HUMAN Pant(40) score is logged
per-frame to a diagnostic sidecar ONLY (never in events, never influences
detection) — amendment 2.

Usage:
  HTTPS_PROXY=http://127.0.0.1:7890 python3 detect.py clip.wav \
      --config config.yaml --out events.json
"""
import argparse
import json
import math
import os

import numpy as np
import yaml

TARGET_SR = 16000


def load_audio_16k_mono(path: str) -> np.ndarray:
    import soundfile as sf
    from scipy.signal import resample_poly
    wav, sr = sf.read(path, dtype="float32", always_2d=True)
    wav = wav.mean(axis=1)  # mono
    if sr != TARGET_SR:
        from math import gcd
        g = gcd(sr, TARGET_SR)
        wav = resample_poly(wav, TARGET_SR // g, sr // g).astype("float32")
    return wav


def frame_rms_db(wav: np.ndarray, n_frames: int, hop_s: float, win_s: float) -> np.ndarray:
    """Per-frame RMS in dB, framed to match YAMNet's window/hop."""
    hop = int(round(hop_s * TARGET_SR))
    win = int(round(win_s * TARGET_SR))
    out = np.empty(n_frames, dtype=float)
    eps = 1e-10
    for f in range(n_frames):
        seg = wav[f * hop: f * hop + win]
        rms = math.sqrt(float(np.mean(seg ** 2))) if len(seg) else 0.0
        out[f] = 20.0 * math.log10(rms + eps)
    return out


def load_yamnet(cfg):
    import tensorflow_hub as hub
    return hub.load(cfg["model"]["tfhub_url"])


def detect(wav: np.ndarray, yam, cfg) -> tuple[list[dict], list[dict], "np.ndarray | None"]:
    """Returns (events, pant_log, scores). `scores` is the full [F,521] YAMNet
    matrix when model.retain_scores is on (default) so the semantic layer can
    reuse it with NO second inference pass; None when off. Retaining scores does
    NOT change events — asserted by tests/test_l0_retain_regression.py."""
    import aggregate as agg
    scores, _, _ = yam(wav)
    scores = np.asarray(scores)  # [F, 521]
    n = scores.shape[0]

    cls = cfg["classes"]
    gate = agg.compute_gate(scores, cls["gate"], cls["gate_combine"])
    type_arrays = agg.compute_type_arrays(scores, cls["type"])
    rms_db = frame_rms_db(wav, n, cfg["model"]["hop_s"], cfg["model"]["window_s"])

    events = agg.frames_to_events(gate, type_arrays, rms_db, cfg, cfg["model"]["hop_s"])

    # Diagnostic-only: HUMAN Pant(40) raw score per frame. Never in events.
    pant_idx = cls["pant_diagnostic_index"]
    hop_s = cfg["model"]["hop_s"]
    pant_log = [{"frame": f, "t_s": round(f * hop_s, 2),
                 "pant_score": round(float(scores[f, pant_idx]), 4)}
                for f in range(n)]
    retain = cfg["model"].get("retain_scores", True)
    return events, pant_log, (scores if retain else None)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("audio")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--out", default=None, help="write events JSON here (default stdout)")
    ap.add_argument("--pant-log", default=None,
                    help="write per-frame Pant(40) diagnostic JSONL here (optional)")
    args = ap.parse_args()

    cfg = yaml.safe_load(open(args.config))
    wav = load_audio_16k_mono(args.audio)
    yam = load_yamnet(cfg)
    events, pant_log, _ = detect(wav, yam, cfg)

    payload = json.dumps(events, indent=2, ensure_ascii=False)
    if args.out:
        with open(args.out, "w") as f:
            f.write(payload)
        print(f"wrote {len(events)} events -> {args.out}")
    else:
        print(payload)

    if args.pant_log:
        with open(args.pant_log, "w") as f:
            for row in pant_log:
                f.write(json.dumps(row) + "\n")
        print(f"wrote {len(pant_log)} diagnostic Pant rows -> {args.pant_log}")


if __name__ == "__main__":
    main()
