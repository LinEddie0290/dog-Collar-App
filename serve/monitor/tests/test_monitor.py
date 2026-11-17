"""Unit tests for monitor/ (layer 1): no history, learning period, missing days,
events across midnight, detector calibration, owner sentences."""
import datetime as dt

import numpy as np
import pytest

from monitor import aggregate as A, baseline as B, detect as D, events as E, report as R
from monitor.monitor import DogMonitor

T0 = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc).timestamp()   # 2026-01-01 00:00 UTC
H = 3600.0


def ev(t, dur=2.0, **kw):
    return E.Event("d1", t, t + dur, **kw)


def day(i):
    return dt.date(2026, 1, 1) + dt.timedelta(days=i)


def series(counts, missing=()):
    """one DayAggregate per day with `counts[i]` bouts at 15:00 local (UTC+0)."""
    evs, cov = [], {}
    for i, n in enumerate(counts):
        cov[day(i)] = 0.0 if i in missing else 24.0
        if i not in missing:
            evs += [ev(T0 + i * 86400 + 15 * H + 60 * j, features=(("f0_mean", 500.0 + j),)) for j in range(n)]
    return A.aggregate_days(evs, cov, dog_id="d1")


# ---------------------------------------------------------------- events ---
def test_event_across_midnight_counts_once_splits_duration():
    e = ev(T0 + 23 * H + 59 * 60, dur=180.0)                       # 23:59 -> 00:02
    agg = A.aggregate_days([e], {day(0): 24, day(1): 24}, dog_id="d1")
    assert agg[day(0)].n_bouts == 1 and agg[day(1)].n_bouts == 0
    assert agg[day(0)].vocal_s == pytest.approx(60.0) and agg[day(1)].vocal_s == pytest.approx(120.0)
    assert agg[day(0)].hour_hist[23] == 1


def test_local_offset_moves_day_and_hour():
    e = ev(T0 + 22 * H)                                            # 22:00 UTC = 06:00 next day at UTC+8
    agg = A.aggregate_days([e], {day(1): 24}, dog_id="d1", utc_offset_h=8)
    assert agg[day(1)].n_bouts == 1 and agg[day(1)].hour_hist[6] == 1


def test_bad_event_rejected():
    with pytest.raises(ValueError):
        E.Event("d1", 10.0, 5.0)


def test_wearer_gate_and_alone_context():
    evs = [ev(T0 + 10 * H, wearer_score=0.9), ev(T0 + 11 * H, wearer_score=0.1),
           ev(T0 + 13 * H + 600, wearer_score=0.9)]
    ctx = [E.ContextInterval("d1", "alone", T0 + 13 * H, T0 + 15 * H)]
    a = A.aggregate_days(evs, {day(0): 24}, ctx, dog_id="d1")[day(0)]
    assert a.n_bouts == 2 and a.n_bouts_alone == 1
    assert a.latency_after_departure_s == pytest.approx(600.0) and a.alone_h == pytest.approx(2.0)


# -------------------------------------------------------------- baseline ---
def test_no_history_returns_none():
    assert B.rolling([], day(0), "n_bouts") is None
    fb = B.FrozenBaseline("n_bouts")
    assert fb.update([]) is False and fb.stat is None


def test_missing_days_are_not_zero_days():
    agg = series([5] * 20, missing={3, 4, 5})
    days = sorted(agg.values(), key=lambda d: d.day)
    assert days[3].missing and days[3].n_bouts == 0
    st = B.rolling(days, day(20), "n_bouts")
    assert st.median == 5 and st.n_days == 14                     # missing days excluded, not counted as 0
    # a partly recorded day (collar off most of the day) is missing even if it has bouts
    part = A.aggregate_days([ev(T0 + 15 * H)], {day(0): 3.0}, dog_id="d1")[day(0)]
    assert part.missing and part.n_bouts == 1
    assert B.rolling([part], day(1), "n_bouts") is None


def test_frozen_locks_once_and_respects_timbre_minimum():
    days = sorted(series([1] * 14 + [5] * 10).values(), key=lambda d: d.day)
    fc, ft = B.FrozenBaseline("n_bouts"), B.FrozenBaseline("f0_mean")
    locked = [(fc.update(days[:i + 1]), ft.update(days[:i + 1])) for i in range(len(days))]
    assert [i for i, (c, _) in enumerate(locked) if c] == [13]   # 14 valid days
    i_t = [i for i, (_, t) in enumerate(locked) if t]
    assert len(i_t) == 1 and days[i_t[0]].day >= day(13)
    assert sum(d.timbre_n["f0_mean"] for d in ft.calib_days) >= 30   # A3: timbre needs >= 30 bouts
    before = fc.stat
    fc.update(days)
    assert fc.stat is before                                      # frozen never moves


def test_count_scale_floor():
    st = B._stat([0, 0, 0, 0], "n_bouts", 0, B.DEFAULTS)
    assert st.scale >= 1.0


# ---------------------------------------------------------------- detect ---
@pytest.mark.parametrize("kind", ["cusum", "ewma"])
def test_detector_skips_missing_and_alarms_on_shift(kind):
    det = D.make(kind, 4.0 if kind == "cusum" else 3.0)
    assert det.update(None) is None and det.update(float("nan")) is None
    alarms = [det.update(0.0) for _ in range(20)] + [det.update(3.0) for _ in range(10)]
    assert not any(alarms[:20]) and "up" in alarms[20:]


@pytest.mark.parametrize("kind", ["cusum", "ewma"])
def test_vectorized_alarm_count_equals_scalar_detector(kind):
    sims = np.random.default_rng(2).standard_normal((40, 60)) * 1.5
    thr = 3.0 if kind == "cusum" else 2.5
    scalar = []
    for s in sims:
        det = D.make(kind, thr)
        scalar.append(sum(det.update(v) is not None for v in s))
    assert D.count_alarms(kind, thr, sims).tolist() == scalar


@pytest.mark.parametrize("kind", ["cusum", "ewma"])
def test_calibration_meets_budget(kind):
    z = np.random.default_rng(1).standard_normal(28)
    thr, fa = D.calibrate(z, kind, target_per_month=0.5, n_boot=300)
    assert fa <= 0.5
    thr2, _ = D.calibrate(z, kind, target_per_month=2.0, n_boot=300)
    assert thr2 <= thr                                            # looser budget -> lower threshold


# --------------------------------------------------------------- monitor ---
def test_monitor_learning_then_monitoring_and_alarm():
    rng = np.random.default_rng(0)
    counts = list(rng.poisson(5, 30)) + [15] * 10
    agg = series(counts, missing={20})
    m = DogMonitor("d1", metrics=("n_bouts",))
    out = [m.step(agg[d]) for d in sorted(agg)]
    st = [o["n_bouts"]["status"] for o in out]
    assert st[0] == "no_history" and st[1] == "learning"
    assert st[20] == "missing"
    first_mon = st.index("monitoring")
    assert first_mon == 14                                        # locked after 14 valid days
    assert all("alarm" not in o["n_bouts"] for o in out[:first_mon])   # learning: no judgement
    alarms = [i for i, o in enumerate(out) if o["n_bouts"].get("alarm") == "up"]
    assert alarms and min(alarms) >= 30 and min(alarms) <= 33


def test_monitor_rejects_out_of_order_days():
    agg = series([3, 3])
    m = DogMonitor("d1", metrics=("n_bouts",))
    m.step(agg[day(1)])
    with pytest.raises(ValueError):
        m.step(agg[day(0)])


# ---------------------------------------------------------------- report ---
def test_sentences_are_observational_templates():
    agg = series([3])
    d0 = agg[day(0)]
    learning = R.daily_sentence(d0, {"n_bouts": {"status": "learning", "n_days": 3}})
    assert "只记录" in learning and "3 串" in learning and "下午" in learning
    stat = B.BaselineStat(3.0, 1.7, 14, 40)
    normal = R.daily_sentence(d0, {"n_bouts": {"status": "monitoring", "alarm": None, "frozen": stat}})
    assert normal == "今天正常，叫了 3 串，都在下午。"
    up = R.daily_sentence(d0, {"n_bouts": {"status": "monitoring", "alarm": "up", "frozen": stat}})
    assert "多" in up
    miss = R.daily_sentence(A.DayAggregate("d1", "collar", day(0), 0.0, missing=True), {"n_bouts": {"status": "missing"}})
    assert "不完整" in miss
    trend = R.alone_trend_sentence(B.BaselineStat(9.0, 2, 14, 100), B.BaselineStat(3.0, 1, 14, 40), "up")
    assert trend == "离家后的叫声两周内约涨了 3 倍。"
    assert R.alone_trend_sentence(B.BaselineStat(9.0, 2, 14, 100), B.BaselineStat(3.0, 1, 14, 40), None) is None
    for s in (learning, normal, up, miss, trend):
        assert not any(w in s for w in R.FORBIDDEN)
