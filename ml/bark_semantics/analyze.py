#!/usr/bin/env python3
"""
End-to-end semantic pipeline: audio -> L0 detect (retaining YAMNet scores) ->
L1 features + per-individual affect -> L2 context -> L3 inference. Emits one
Inference per bark burst.

Usage:
  HTTPS_PROXY=... SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    python3 analyze.py clip.wav --dog-id rex --device phone_mic \
      --recording-start 2026-09-10T23:30:00 --out out.json
"""
import argparse
import csv
import json
import os

import yaml

import detect as L0
import features as L1
from baseline import SQLiteBaselineStore, burst_scalars, estimate_affect
from context import BaselineProvider, EnvEventProvider, TimeProvider, build_context_snapshot
from datetime import datetime
from infer import infer

HERE = os.path.dirname(os.path.abspath(__file__))


def load_class_names(path=None) -> list[str]:
    path = path or os.path.join(HERE, "docs", "yamnet_class_map.csv")
    return [r["display_name"] for r in csv.DictReader(open(path))]


def inference_to_dict(inf) -> dict:
    return {
        "observation": inf.observation,
        "degraded_slots": inf.degraded_slots,
        "hypotheses": [{"intent": h.intent.value, "confidence": h.confidence,
                        "evidence": h.evidence} for h in inf.hypotheses],
    }


def run(audio: str, cfg: dict, dog_id: str, device: str,
        recording_start: datetime | None, learn: bool = True, yam=None) -> list[dict]:
    wav = L0.load_audio_16k_mono(audio)
    yam = yam if yam is not None else L0.load_yamnet(cfg)
    events, _, scores = L0.detect(wav, yam, cfg)
    sr = L0.TARGET_SR

    l1cfg = cfg["semantics"]["l1"]
    bcfg = cfg["semantics"]["baseline"]
    ccfg = cfg["semantics"]["context"]
    names = load_class_names()
    store = SQLiteBaselineStore(bcfg["db_path"])
    env_provider = EnvEventProvider(scores, names, ccfg, cfg["model"]["hop_s"])
    time_provider = TimeProvider(recording_start, ccfg)

    results = []
    for group in L1.segment_bursts(events, l1cfg["burst_gap_s"]):
        onset = group[0]["start_s"]
        bf = L1.compute_burst_features(wav, sr, group, l1cfg)
        affect = estimate_affect(bf, dog_id, device, store, bcfg)  # ranks vs PRIOR history
        providers = {"env_events": env_provider, "time_of_day": time_provider,
                     "baseline": BaselineProvider(affect)}
        snap = build_context_snapshot(onset, providers, affect)
        inf = infer(affect, bf, snap, cfg)
        results.append({"onset_s": round(onset, 2), **inference_to_dict(inf)})
        if learn:
            day = ((recording_start.date().isoformat()) if recording_start else "unknown")
            store.add(dog_id, device, day, burst_scalars(bf))
    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("audio")
    ap.add_argument("--config", default=os.path.join(HERE, "config.yaml"))
    ap.add_argument("--dog-id", required=True)
    ap.add_argument("--device", default="phone_mic")
    ap.add_argument("--recording-start", default=None, help="ISO datetime of t=0")
    ap.add_argument("--no-learn", action="store_true", help="don't add to baseline")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    cfg = yaml.safe_load(open(args.config))
    rs = datetime.fromisoformat(args.recording_start) if args.recording_start else None
    results = run(args.audio, cfg, args.dog_id, args.device, rs, learn=not args.no_learn)

    payload = json.dumps(results, indent=2, ensure_ascii=False)
    if args.out:
        open(args.out, "w").write(payload)
        print(f"wrote {len(results)} burst inference(s) -> {args.out}")
    else:
        print(payload)


if __name__ == "__main__":
    main()
