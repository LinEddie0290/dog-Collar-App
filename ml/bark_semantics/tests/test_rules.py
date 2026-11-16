"""Rules-layer tests on synthetic event lists — no audio, no TF, no numpy.

Runs under pytest, or standalone: `python3 tests/test_rules.py`.
"""
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rules  # noqa: E402


def ev(start, dur, t):
    return {"start_s": start, "end_s": start + dur, "duration_s": dur, "type": t}


def test_sustained_howl_triggers():
    r = {"min_total_s": 10.0, "window_s": 60.0}
    evs = [ev(0, 4, "howl"), ev(5, 4, "howl"), ev(10, 4, "howl")]  # 12 s of howl in 60 s
    out = rules.sustained_howl(evs, r)
    assert len(out) == 1 and out[0]["total_howl_s"] >= 10.0


def test_sustained_howl_no_trigger_when_below():
    r = {"min_total_s": 10.0, "window_s": 60.0}
    evs = [ev(0, 3, "howl"), ev(30, 3, "howl")]  # only 6 s
    assert rules.sustained_howl(evs, r) == []


def test_sustained_whine_fraction():
    r = {"min_fraction": 0.30, "window_s": 300.0}
    # 100 s of whimper inside a 300 s window -> 0.33 > 0.30
    evs = [ev(0, 50, "whimper"), ev(60, 50, "whimper")]
    out = rules.sustained_whine(evs, r)
    assert len(out) == 1 and out[0]["whine_fraction"] > 0.30


def test_dense_barking_counts_per_minute():
    r = {"min_events_per_min": 8}
    evs = [ev(i * 5, 1, "bark") for i in range(10)]  # 10 barks within ~45 s
    out = rules.dense_barking(evs, r)
    assert len(out) == 1 and out[0]["bark_count"] == 10


def test_dense_barking_no_trigger():
    r = {"min_events_per_min": 8}
    evs = [ev(i * 30, 1, "bark") for i in range(5)]  # spread out, <=2 per minute
    assert rules.dense_barking(evs, r) == []


def test_night_vocalization_hits():
    r = {"start_hour": 22, "end_hour": 6}
    evs = [ev(0, 2, "bark"), ev(3600, 2, "howl")]  # 23:30 and 00:30
    out = rules.night_vocalization(evs, r, datetime(2026, 9, 10, 23, 30, 0))
    assert len(out) == 1 and len(out[0]["events"]) == 2


def test_night_vocalization_daytime_no_trigger():
    r = {"start_hour": 22, "end_hour": 6}
    evs = [ev(0, 2, "bark")]  # 14:00
    out = rules.night_vocalization(evs, r, datetime(2026, 9, 10, 14, 0, 0))
    assert out == []


def test_night_vocalization_skipped_without_clock():
    r = {"start_hour": 22, "end_hour": 6}
    out = rules.night_vocalization([ev(0, 2, "bark")], r, None)
    assert len(out) == 1 and out[0].get("skipped") is True


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print("ok:", fn.__name__)
    print(f"\nALL {len(fns)} RULES TESTS PASSED ✅")
