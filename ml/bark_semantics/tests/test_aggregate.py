"""Aggregation logic tests on synthetic frame sequences — no audio, no TF.

Runs under pytest, or standalone: `python3 tests/test_aggregate.py`.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import aggregate as agg  # noqa: E402

HOP = 0.48


def make_cfg(**det_over):
    det = {
        "dog_score_threshold": 0.3,
        "smoothing_window_frames": 1,
        "smoothing_method": "median",
        "min_event_duration_s": 0.96,   # >= 2 frames
        "merge_gap_s": 0.48,            # <= 1 frame merges
        "type_vote": "mean_score",
    }
    det.update(det_over)
    return {"detection": det, "arousal": {"rms_db_low": -45.0, "rms_db_high": -15.0}}


def _types(**arrays):
    return {k: np.asarray(v, dtype=float) for k, v in arrays.items()}


def _flat_types(gate):
    # single-type helper: all frames "bark", constant score
    return _types(bark=[0.7] * len(gate), howl=[0.0] * len(gate))


# ---- feature extraction ----

def test_bowwow_folds_into_bark():
    s = np.zeros((1, 521))
    s[0, 70] = 0.2   # Bark
    s[0, 73] = 0.6   # Bow-wow
    t = agg.compute_type_arrays(s, {"bark": [70, 73], "howl": [72]})
    assert abs(t["bark"][0] - 0.6) < 1e-9, "bark = max(Bark, Bow-wow)"


def test_gate_combine_modes():
    s = np.zeros((1, 521))
    s[0, 69], s[0, 117], s[0, 68], s[0, 67] = 0.4, 0.7, 0.9, 0.1
    g = {"dog": 69, "canidae": 117, "domestic_animals": 68, "animal": 67}
    assert abs(agg.compute_gate(s, g, "dog_only")[0] - 0.4) < 1e-9
    assert abs(agg.compute_gate(s, g, "max_dog_canidae")[0] - 0.7) < 1e-9
    assert abs(agg.compute_gate(s, g, "max_all")[0] - 0.9) < 1e-9


# ---- smoothing ----

def test_median_smoothing_kills_single_frame_spike():
    out = agg.smooth([0, 0, 0.9, 0, 0], 3, "median")
    assert max(out) == 0.0, "median window-3 removes an isolated spike"


def test_moving_average_smoothing():
    out = agg.smooth([0, 0, 0.9, 0, 0], 3, "moving_average")
    assert abs(out[2] - 0.3) < 1e-9


# ---- event building ----

def test_min_duration_drops_blips():
    gate = np.array([0, 0.9, 0, 0, 0.9, 0.9, 0])  # 1-frame blip, then 2-frame event
    rms = np.full(len(gate), -30.0)
    ev = agg.frames_to_events(gate, _flat_types(gate), rms, make_cfg(), HOP)
    assert len(ev) == 1
    assert ev[0]["n_frames"] == 2


def test_merge_gap_joins_runs():
    gate = np.array([0.9, 0.9, 0, 0.9, 0.9])  # gap of 1 non-dog frame
    rms = np.full(len(gate), -30.0)
    joined = agg.frames_to_events(gate, _flat_types(gate), rms, make_cfg(merge_gap_s=0.48), HOP)
    split = agg.frames_to_events(gate, _flat_types(gate), rms, make_cfg(merge_gap_s=0.0), HOP)
    assert len(joined) == 1 and joined[0]["n_frames"] == 5
    assert len(split) == 2


def test_timing_convention():
    gate = np.zeros(45)
    gate[26:40] = 0.9  # frames 26..39 -> 14 frames
    rms = np.full(len(gate), -30.0)
    ev = agg.frames_to_events(gate, _flat_types(gate), rms, make_cfg(), HOP)[0]
    assert ev["start_s"] == round(26 * HOP, 2)      # 12.48
    assert ev["end_s"] == round(40 * HOP, 2)        # 19.20
    assert ev["duration_s"] == round(14 * HOP, 2)   # 6.72
    assert ev["n_frames"] == 14


def test_type_vote_mean_score():
    gate = np.full(3, 0.9)
    t = _types(bark=[0.1, 0.1, 0.1], howl=[0.8, 0.8, 0.8])
    ev = agg.frames_to_events(gate, t, np.full(3, -30.0), make_cfg(), HOP)[0]
    assert ev["type"] == "howl"
    assert ev["confidence"] == 0.8
    assert set(ev["type_scores"]) == {"bark", "howl"}


def test_type_vote_majority():
    gate = np.full(4, 0.9)
    # bark wins 3 frames on argmax even though howl has one big spike
    t = _types(bark=[0.6, 0.6, 0.6, 0.0], howl=[0.5, 0.5, 0.5, 0.99])
    ev = agg.frames_to_events(gate, t, np.full(4, -30.0), make_cfg(type_vote="majority"), HOP)[0]
    assert ev["type"] == "bark"


def test_arousal_proxy_normalization_and_clamp():
    gate = np.full(3, 0.9)
    t = _flat_types(gate)
    mid = agg.frames_to_events(gate, t, np.full(3, -30.0), make_cfg(), HOP)[0]
    lo = agg.frames_to_events(gate, t, np.full(3, -60.0), make_cfg(), HOP)[0]
    hi = agg.frames_to_events(gate, t, np.full(3, 0.0), make_cfg(), HOP)[0]
    assert abs(mid["arousal_proxy"] - 0.5) < 1e-6   # (-30 - -45)/30
    assert lo["arousal_proxy"] == 0.0               # clamped
    assert hi["arousal_proxy"] == 1.0               # clamped


def test_event_schema_fields():
    gate = np.full(3, 0.9)
    ev = agg.frames_to_events(gate, _flat_types(gate), np.full(3, -22.4), make_cfg(), HOP)[0]
    for k in ("start_s", "end_s", "duration_s", "type", "gate_score",
              "type_scores", "confidence", "n_frames", "arousal_proxy", "rms_db"):
        assert k in ev, f"missing field {k}"


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print("ok:", fn.__name__)
    print(f"\nALL {len(fns)} AGGREGATION TESTS PASSED ✅")
