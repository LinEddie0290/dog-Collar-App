"""Layer 1: daily (and per-context) aggregation of vocal events.

Per (dog_id, device, local day):
  n_bouts, vocal_s                     all bouts / vocal seconds of the day
  n_bouts_alone, alone_h               bouts during 'alone' context, hours alone
  latency_after_departure_s            first bout after each 'alone' start (median over
                                       the day's departures; None if no bout while alone)
  hour_hist[24]                        bouts by local hour of onset
  timbre medians                       f0_mean, hnr, spectral_centroid (median over the
                                       day's bouts that carry the feature; secondary)
  coverage_h                           hours the collar was recording; a day with
                                       coverage below `min_coverage_h` is MISSING (not a
                                       zero day) and skipped downstream
Only events with wearer_score >= wearer_min (or None) are counted (layer 0 gate).
"""
from __future__ import annotations

import datetime as dt
from collections import defaultdict
from dataclasses import dataclass, field

import numpy as np

from .events import ContextInterval, Event, day_bounds, local_day, local_hour, split_by_day

TIMBRE = ("f0_mean", "hnr", "spectral_centroid")


@dataclass
class DayAggregate:
    dog_id: str
    device: str
    day: dt.date
    coverage_h: float
    n_bouts: int = 0
    vocal_s: float = 0.0
    n_bouts_alone: int = 0
    alone_h: float = 0.0
    latency_after_departure_s: float | None = None
    hour_hist: list = field(default_factory=lambda: [0] * 24)
    timbre: dict = field(default_factory=dict)
    timbre_n: dict = field(default_factory=dict)
    missing: bool = False

    def metric(self, name):
        if name in ("n_bouts", "vocal_s", "n_bouts_alone", "alone_h", "latency_after_departure_s"):
            return getattr(self, name)
        return self.timbre.get(name)


def aggregate_days(events: list[Event], coverage: dict[dt.date, float], contexts: list[ContextInterval] = (),
                   dog_id: str | None = None, device: str = "collar", utc_offset_h: float = 0.0,
                   min_coverage_h: float = 12.0, wearer_min: float = 0.5) -> dict[dt.date, DayAggregate]:
    """coverage: local day -> hours of recording (days absent from it count as 0 h)."""
    ev = [e for e in events if (dog_id is None or e.dog_id == dog_id) and e.device == device
          and (e.wearer_score is None or e.wearer_score >= wearer_min)]
    ctx = [c for c in contexts if dog_id is None or c.dog_id == dog_id]
    days = set(coverage) | {local_day(e.t_start, utc_offset_h) for e in ev}
    out = {}
    for d in sorted(days):
        cov = float(coverage.get(d, 0.0))
        out[d] = DayAggregate(dog_id or (ev[0].dog_id if ev else ""), device, d, cov, missing=cov < min_coverage_h)
    timbre_vals = defaultdict(lambda: defaultdict(list))
    alone = [c for c in ctx if c.tag == "alone"]
    for e in ev:
        d = local_day(e.t_start, utc_offset_h)
        a = out[d]
        a.n_bouts += 1
        a.hour_hist[local_hour(e.t_start, utc_offset_h)] += 1
        for dd, s in split_by_day(e.t_start, e.t_end, utc_offset_h).items():
            if dd not in out:
                out[dd] = DayAggregate(a.dog_id, device, dd, float(coverage.get(dd, 0.0)),
                                       missing=float(coverage.get(dd, 0.0)) < min_coverage_h)
            out[dd].vocal_s += s
        if "alone" in e.context or any(c.t_start <= e.t_start < c.t_end for c in alone):
            a.n_bouts_alone += 1
        for name in TIMBRE:
            v = e.feature(name)
            if v is not None and np.isfinite(v):
                timbre_vals[d][name].append(float(v))
    for c in alone:
        for d, a in out.items():
            b0, b1 = day_bounds(d, utc_offset_h)
            a.alone_h += max(0.0, min(c.t_end, b1) - max(c.t_start, b0)) / 3600
    lat = defaultdict(list)
    for c in alone:
        first = [e.t_start - c.t_start for e in ev if c.t_start <= e.t_start < c.t_end]
        if first:
            lat[local_day(c.t_start, utc_offset_h)].append(min(first))
    for d, a in out.items():
        a.latency_after_departure_s = float(np.median(lat[d])) if lat.get(d) else None
        for name, v in timbre_vals[d].items():
            a.timbre[name] = float(np.median(v)); a.timbre_n[name] = len(v)
    return out


def by_hour_block(day: DayAggregate, blocks=((0, 6, "night"), (6, 12, "morning"), (12, 18, "afternoon"), (18, 24, "evening"))):
    return {name: int(sum(day.hour_hist[h] for h in range(a, b))) for a, b, name in blocks}
