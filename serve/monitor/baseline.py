"""Layer 1 baselines: per (dog_id, device, metric), from that dog's own valid days.

Design reused from the semantic layer (dog-Collar-App ml/bark_semantics/baseline.py):
per-individual AND per-device baselines (mics differ), an explicit learning
period, and None when there is no history (never a population constant dressed
up as a measurement). Different here: daily aggregates instead of per-burst
percentiles, robust location/scale (median, 1.4826 * MAD) and two baselines:
  rolling : the last `rolling_days` valid days before the day being judged
  frozen  : locked once calibration is complete (>= min_days valid days AND, for
            timbre metrics, >= min_bouts_timbre bouts carrying the feature;
            rhythm metrics need min_bouts_rhythm - offline/PERDOG_NORM_REPORT A3),
            then never moves; slow drift is judged against it
Scale floors stop a quiet dog (MAD = 0) from turning one bout into a huge z:
counts use max(1.4826 MAD, sqrt(max(median, 1)), 1) (Poisson-like), timbre
metrics use max(1.4826 MAD, rel_floor * |median|, abs_floor).
"""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass

import numpy as np

from .aggregate import TIMBRE, DayAggregate

COUNT_METRICS = ("n_bouts", "vocal_s", "n_bouts_alone")
RHYTHM_METRICS = ("latency_after_departure_s",)
DEFAULTS = {"rolling_days": 14, "min_days": 14, "min_bouts_timbre": 30, "min_bouts_rhythm": 100,
            "rel_floor": 0.02, "abs_floor": 1e-6, "min_day_bouts_timbre": 5}


def day_value(d, metric, cfg=DEFAULTS):
    """the day's value of `metric`; timbre medians of days with fewer than
    min_day_bouts_timbre bouts are unreliable (1-2 bouts give |z| > 3 on ~20 % of
    days in simulation) and count as missing for that metric."""
    if metric in TIMBRE and d.timbre_n.get(metric, 0) < cfg["min_day_bouts_timbre"]:
        return None
    return d.metric(metric)


@dataclass(frozen=True)
class BaselineStat:
    median: float
    scale: float
    n_days: int
    n_bouts: int

    def z(self, x):
        return None if x is None else (x - self.median) / self.scale


def _stat(values, metric, n_bouts, cfg):
    v = np.asarray([x for x in values if x is not None and np.isfinite(x)], float)
    if len(v) == 0:
        return None
    med = float(np.median(v)); mad = 1.4826 * float(np.median(np.abs(v - med)))
    if metric in COUNT_METRICS:
        scale = max(mad, float(np.sqrt(max(med, 1.0))), 1.0)
    else:
        scale = max(mad, cfg["rel_floor"] * abs(med), cfg["abs_floor"])
    return BaselineStat(med, scale, len(v), n_bouts)


def _bouts_for(days, metric):
    if metric in TIMBRE:
        return sum(d.timbre_n.get(metric, 0) for d in days)
    return sum(d.n_bouts for d in days)


def calibration_complete(days: list[DayAggregate], metric: str, cfg=DEFAULTS) -> bool:
    valid = [d for d in days if not d.missing]
    if len(valid) < cfg["min_days"]:
        return False
    if metric in TIMBRE and sum(day_value(d, metric, cfg) is not None for d in valid) < cfg["min_days"] // 2:
        return False                                  # need >= 7 usable timbre days
    if metric in TIMBRE:
        return _bouts_for(valid, metric) >= cfg["min_bouts_timbre"]
    if metric in RHYTHM_METRICS:
        return _bouts_for(valid, metric) >= cfg["min_bouts_rhythm"]
    return True


def rolling(days: list[DayAggregate], day: dt.date, metric: str, cfg=DEFAULTS) -> BaselineStat | None:
    """Baseline from the last rolling_days valid days strictly before `day`."""
    prev = [d for d in days if d.day < day and not d.missing]
    prev = sorted(prev, key=lambda d: d.day)[-cfg["rolling_days"]:]
    if not prev:
        return None
    return _stat([day_value(d, metric, cfg) for d in prev], metric, _bouts_for(prev, metric), cfg)


class FrozenBaseline:
    """Locks the first time calibration completes; afterwards `get` never changes."""

    def __init__(self, metric: str, cfg=DEFAULTS):
        self.metric, self.cfg = metric, cfg
        self.stat: BaselineStat | None = None
        self.locked_on: dt.date | None = None
        self.calib_days: list[DayAggregate] = []

    def update(self, history: list[DayAggregate]) -> bool:
        """history = valid and missing days seen so far (chronological). Returns True when it locks now."""
        if self.stat is not None:
            return False
        if calibration_complete(history, self.metric, self.cfg):
            valid = [d for d in history if not d.missing]
            self.stat = _stat([day_value(d, self.metric, self.cfg) for d in valid], self.metric, _bouts_for(valid, self.metric), self.cfg)
            if self.stat is None:
                return False
            self.locked_on = max(d.day for d in valid)
            self.calib_days = valid
            return True
        return False
