"""
L1 baseline normalization.

Cross-individual absolute thresholds are meaningless (a chihuahua and a golden
retriever differ ~an octave in F0), so every feature is converted to a
PERCENTILE RANK against *that dog's own history* before it reaches
arousal/valence. Baselines are also kept SEPARATE PER CAPTURE DEVICE (phone vs
collar mic have different frequency responses that shift every feature).

Storage: SQLite. Chosen over JSONL because it gives atomic single-row INSERTs
(no half-written records), a cheap per-(dog_id, device) query for each feature's
distribution and the distinct-day count, and no full-file rewrite as history
grows. The BaselineStore Protocol keeps it swappable (JSONL/cloud later).

With zero history we return AffectEstimate(None, None, 0.0) — never a global
constant dressed up as a measurement. Below MIN_BASELINE_SAMPLES (or too few
distinct days) we set learning_period and apply a confidence penalty. valence is
expected to be weaker than arousal, so its confidence is capped separately.
"""
from __future__ import annotations

import os
import sqlite3
from typing import Protocol

import numpy as np

from schema import AffectEstimate, BurstFeatures

# Scalar features persisted per burst (the union needed by arousal, valence, and
# the L3 percentile conditions).
FEATURES = ["ibi_mean", "inv_ibi", "burst_duration", "rms_peak",
            "f0_mean", "f0_std", "hnr", "tonality", "bark_duration"]


def burst_scalars(bf: BurstFeatures) -> dict[str, float | None]:
    """Reduce a BurstFeatures to the burst-level scalars used for baselining."""
    def mean_notnone(vals):
        v = [x for x in vals if x is not None]
        return float(np.mean(v)) if v else None
    rms = [b.rms_peak for b in bf.barks]
    return {
        "ibi_mean": bf.ibi_mean,
        "inv_ibi": (1.0 / bf.ibi_mean) if (bf.ibi_mean and bf.ibi_mean > 0) else None,
        "burst_duration": bf.duration,
        "rms_peak": float(np.max(rms)) if rms else None,
        "f0_mean": mean_notnone([b.f0_mean for b in bf.barks]),
        "f0_std": mean_notnone([b.f0_std for b in bf.barks]),
        "hnr": mean_notnone([b.hnr for b in bf.barks]),
        "tonality": mean_notnone([b.tonality for b in bf.barks]),
        "bark_duration": mean_notnone([b.duration for b in bf.barks]),
    }


class BaselineStore(Protocol):
    def add(self, dog_id: str, device: str, day: str, scalars: dict) -> None: ...
    def history(self, dog_id: str, device: str) -> dict[str, np.ndarray]: ...
    def n_samples(self, dog_id: str, device: str) -> int: ...
    def n_days(self, dog_id: str, device: str) -> int: ...


class SQLiteBaselineStore:
    def __init__(self, path: str):
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        self.conn = sqlite3.connect(path)
        cols = ", ".join(f"{f} REAL" for f in FEATURES)
        self.conn.execute(
            f"CREATE TABLE IF NOT EXISTS baseline "
            f"(dog_id TEXT, device TEXT, day TEXT, {cols})")
        self.conn.commit()

    def add(self, dog_id: str, device: str, day: str, scalars: dict) -> None:
        cols = ["dog_id", "device", "day"] + FEATURES
        vals = [dog_id, device, day] + [scalars.get(f) for f in FEATURES]
        ph = ", ".join("?" * len(cols))
        self.conn.execute(f"INSERT INTO baseline ({', '.join(cols)}) VALUES ({ph})", vals)
        self.conn.commit()

    def history(self, dog_id: str, device: str) -> dict[str, np.ndarray]:
        out = {}
        for f in FEATURES:
            rows = self.conn.execute(
                f"SELECT {f} FROM baseline WHERE dog_id=? AND device=? AND {f} IS NOT NULL",
                (dog_id, device)).fetchall()
            out[f] = np.array([r[0] for r in rows], dtype=float)
        return out

    def n_samples(self, dog_id: str, device: str) -> int:
        return self.conn.execute(
            "SELECT COUNT(*) FROM baseline WHERE dog_id=? AND device=?",
            (dog_id, device)).fetchone()[0]

    def n_days(self, dog_id: str, device: str) -> int:
        return self.conn.execute(
            "SELECT COUNT(DISTINCT day) FROM baseline WHERE dog_id=? AND device=?",
            (dog_id, device)).fetchone()[0]


def _pct(hist: dict, name: str, value, invert: bool = False):
    """Percentile rank of `value` within this dog+device history of `name`."""
    if value is None:
        return None
    arr = hist.get(name)
    if arr is None or len(arr) == 0:
        return None
    r = float(np.mean(arr <= value))
    return (1.0 - r) if invert else r


def _wsum(comp: dict, weights: dict):
    """Weighted mean over available (non-None) components, renormalized."""
    pairs = [(weights[k], comp[k]) for k in comp
             if k in weights and comp[k] is not None]
    W = sum(w for w, _ in pairs)
    return sum(w * v for w, v in pairs) / W if W > 0 else None


def estimate_affect(bf: BurstFeatures, dog_id: str, device: str,
                    store: BaselineStore, bcfg: dict) -> AffectEstimate:
    """Percentile-normalized arousal/valence for one burst. Pure read — the
    caller adds the burst to the store afterwards (so we never rank against
    the current sample)."""
    scal = burst_scalars(bf)
    n = store.n_samples(dog_id, device)
    if n == 0:
        return AffectEstimate(None, None, 0.0, True, 0, {})

    hist = store.history(dog_id, device)
    days = store.n_days(dog_id, device)

    comp_arousal = {
        "inv_ibi": _pct(hist, "inv_ibi", scal["inv_ibi"]),
        "burst_duration": _pct(hist, "burst_duration", scal["burst_duration"]),
        "rms_peak": _pct(hist, "rms_peak", scal["rms_peak"]),
        "f0_std": _pct(hist, "f0_std", scal["f0_std"]),
    }
    comp_valence = {
        "hnr": _pct(hist, "hnr", scal["hnr"]),
        "tonality": _pct(hist, "tonality", scal["tonality"]),
        "neg_bark_duration": _pct(hist, "bark_duration", scal["bark_duration"], invert=True),
    }
    arousal = _wsum(comp_arousal, bcfg["arousal_weights"])
    valence = _wsum(comp_valence, bcfg["valence_weights"])

    learning = (n < bcfg["min_baseline_samples"]) or (days < bcfg["min_baseline_days"])
    conf = min(1.0, n / bcfg["min_baseline_samples"])
    if learning:
        conf *= bcfg["learning_confidence_penalty"]

    # components feed evidence strings and L3 conditions; keep only measured ones.
    components = {f"{k}_pct": v for k, v in {**comp_arousal, **comp_valence}.items()
                 if v is not None}
    for cond_key, feat in (("ibi_pct", "ibi_mean"), ("f0_pct", "f0_mean"),
                           ("hnr_pct", "hnr")):
        p = _pct(hist, feat, scal[feat])
        if p is not None:
            components[cond_key] = p
    if valence is not None:
        # valence is weak -> its own confidence is capped separately so it can't
        # inherit arousal's certainty (consumed by infer.py for valence rules).
        components["valence_confidence"] = min(conf, bcfg["valence_confidence_cap"])

    return AffectEstimate(arousal=arousal, valence=valence, confidence=conf,
                          learning_period=learning, baseline_n=n, components=components)
