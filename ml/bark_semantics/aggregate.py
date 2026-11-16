"""
Frame -> event aggregation for YAMNet dog-vocalization detection.

Pure logic, no TensorFlow, no audio I/O — so it is unit-testable on synthetic
frame sequences (see tests/). detect.py feeds it real YAMNet output; the tests
feed it hand-built arrays.

YAMNet is multi-label sigmoid, so we keep two independent tiers (see
docs/class_map.md):
  * gate_score  — "is this a dog at all"  (from parent/umbrella classes)
  * type_scores — the competing event type (bark/yip/howl/growling/whimper),
                  with Bow-wow(73) folded into bark.

Frame timing convention (matches the task's example event):
  start_s = start_frame * hop_s
  end_s   = end_frame_exclusive * hop_s
  n_frames = end_frame_exclusive - start_frame
  duration_s = n_frames * hop_s
"""
from __future__ import annotations

import numpy as np

# ---------------------------------------------------------------------------
# Per-frame feature extraction from the raw 521-dim YAMNet scores
# ---------------------------------------------------------------------------


def compute_gate(scores: np.ndarray, gate_cfg: dict, combine: str) -> np.ndarray:
    """scores: [F, 521] -> gate_score [F].

    combine:
      dog_only         -> Dog(69) alone
      max_dog_canidae  -> max(Dog, Canidae)
      max_all          -> max over all gate classes (incl. broad parents)
    """
    dog = scores[:, gate_cfg["dog"]]
    if combine == "dog_only":
        return dog
    if combine == "max_dog_canidae":
        return np.maximum(dog, scores[:, gate_cfg["canidae"]])
    if combine == "max_all":
        idx = [gate_cfg[k] for k in ("dog", "canidae", "domestic_animals", "animal")]
        return scores[:, idx].max(axis=1)
    raise ValueError(f"unknown gate_combine: {combine}")


def compute_type_arrays(scores: np.ndarray, type_cfg: dict) -> dict[str, np.ndarray]:
    """scores: [F,521] -> {label: [F]} where a label maps to max over its class
    indices (e.g. bark = max(Bark, Bow-wow))."""
    out = {}
    for label, idxs in type_cfg.items():
        out[label] = scores[:, list(idxs)].max(axis=1)
    return out


# ---------------------------------------------------------------------------
# Smoothing
# ---------------------------------------------------------------------------


def smooth(x: np.ndarray, window: int, method: str) -> np.ndarray:
    """1-D smoothing with edge-shrinking windows (no fabricated padding)."""
    x = np.asarray(x, dtype=float)
    if window is None or window <= 1:
        return x.copy()
    n = len(x)
    half = window // 2
    out = np.empty(n, dtype=float)
    for i in range(n):
        lo = max(0, i - half)
        hi = min(n, i + half + 1)
        seg = x[lo:hi]
        out[i] = np.median(seg) if method == "median" else np.mean(seg)
    return out


# ---------------------------------------------------------------------------
# Runs -> merged -> filtered events
# ---------------------------------------------------------------------------


def _runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """Contiguous True runs as [start, end_exclusive)."""
    runs = []
    start = None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        elif not v and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, len(mask)))
    return runs


def _merge(runs, merge_gap_frames):
    if not runs:
        return []
    merged = [list(runs[0])]
    for s, e in runs[1:]:
        gap = s - merged[-1][1]  # non-dog frames between runs
        if gap <= merge_gap_frames:
            merged[-1][1] = e
        else:
            merged.append([s, e])
    return [tuple(m) for m in merged]


def _arousal_proxy(rms_db_seg: np.ndarray, low: float, high: float) -> float:
    """HEURISTIC (not a model): 95th-pct RMS in dB, linearly normalized between
    [low,high] and clamped to [0,1]. dB is already the log mapping."""
    p95 = float(np.percentile(rms_db_seg, 95))
    a = (p95 - low) / (high - low) if high != low else 0.0
    return float(min(1.0, max(0.0, a))), p95


def frames_to_events(
    gate: np.ndarray,
    type_arrays: dict[str, np.ndarray],
    rms_db: np.ndarray,
    cfg: dict,
    hop_s: float,
) -> list[dict]:
    """Turn per-frame arrays into a list of event dicts (see module docstring
    for the schema). All parameters come from cfg (config.yaml)."""
    det = cfg["detection"]
    aro = cfg["arousal"]
    gate = np.asarray(gate, dtype=float)
    rms_db = np.asarray(rms_db, dtype=float)

    sm = smooth(gate, det["smoothing_window_frames"], det["smoothing_method"])
    mask = sm > det["dog_score_threshold"]

    merge_gap_frames = int(round(det["merge_gap_s"] / hop_s))
    runs = _merge(_runs(mask), merge_gap_frames)

    min_frames = det["min_event_duration_s"] / hop_s
    labels = list(type_arrays.keys())
    events = []
    for s, e in runs:
        n = e - s
        if n < min_frames - 1e-9:
            continue
        # type distribution over the event's frames (mean per label)
        means = {lab: float(type_arrays[lab][s:e].mean()) for lab in labels}
        if det["type_vote"] == "mean_score":
            winner = max(means, key=means.get)
        elif det["type_vote"] == "majority":
            per_frame = np.argmax(
                np.stack([type_arrays[lab][s:e] for lab in labels], axis=1), axis=1
            )
            counts = np.bincount(per_frame, minlength=len(labels))
            winner = labels[int(np.argmax(counts))]
        else:
            raise ValueError(f"unknown type_vote: {det['type_vote']}")

        arousal, rms95 = _arousal_proxy(rms_db[s:e], aro["rms_db_low"], aro["rms_db_high"])
        events.append({
            "start_s": round(s * hop_s, 2),
            "end_s": round(e * hop_s, 2),
            "duration_s": round(n * hop_s, 2),
            "type": winner,
            "gate_score": round(float(sm[s:e].mean()), 3),
            "type_scores": {k: round(v, 3) for k, v in means.items()},
            "confidence": round(means[winner], 3),
            "n_frames": int(n),
            "arousal_proxy": round(arousal, 3),  # heuristic, not a model
            "rms_db": round(rms95, 1),
        })
    return events
