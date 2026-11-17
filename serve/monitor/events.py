"""Event record for layers 0-2 and day assignment.

A vocal event (bout) as produced by the streaming detector (layer 0/2 output):
dog_id, device, t_start / t_end (UNIX seconds, UTC), type, wearer_score (layer 0,
None = not computed), context tags (e.g. {"alone", "visitor", "thunder"}, may be
empty) and optional per-bout acoustic medians (f0_mean, hnr, spectral_centroid).

Days are LOCAL calendar days (fixed UTC offset per dog, configurable). A bout is
counted on the day it STARTS; its duration is split across days by overlap, so a
bout crossing midnight adds to both days' vocal time but to one day's count.
"""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Event:
    dog_id: str
    t_start: float
    t_end: float
    type: str = "dog"
    wearer_score: float | None = None
    context: frozenset = field(default_factory=frozenset)
    device: str = "collar"
    features: tuple = ()          # ((name, value), ...) hashable, e.g. (("f0_mean", 510.0),)

    def __post_init__(self):
        if self.t_end < self.t_start:
            raise ValueError(f"t_end {self.t_end} < t_start {self.t_start}")

    @property
    def duration(self) -> float:
        return self.t_end - self.t_start

    def feature(self, name):
        return dict(self.features).get(name)


@dataclass(frozen=True)
class ContextInterval:
    """A context period, e.g. the owner away (tag 'alone') from t_start to t_end."""
    dog_id: str
    tag: str
    t_start: float
    t_end: float


def local_day(t: float, utc_offset_h: float = 0.0) -> dt.date:
    return (dt.datetime.fromtimestamp(t, dt.timezone.utc) + dt.timedelta(hours=utc_offset_h)).date()


def local_hour(t: float, utc_offset_h: float = 0.0) -> int:
    return (dt.datetime.fromtimestamp(t, dt.timezone.utc) + dt.timedelta(hours=utc_offset_h)).hour


def day_bounds(day: dt.date, utc_offset_h: float = 0.0) -> tuple[float, float]:
    start = dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc) - dt.timedelta(hours=utc_offset_h)
    return start.timestamp(), (start + dt.timedelta(days=1)).timestamp()


def split_by_day(t0: float, t1: float, utc_offset_h: float = 0.0) -> dict[dt.date, float]:
    """seconds of [t0, t1) falling on each local day."""
    out = {}
    d = local_day(t0, utc_offset_h)
    while True:
        a, b = day_bounds(d, utc_offset_h)
        s = min(t1, b) - max(t0, a)
        if s > 0:
            out[d] = s
        if t1 <= b:
            break
        d = d + dt.timedelta(days=1)
    return out or {local_day(t0, utc_offset_h): 0.0}      # zero-length event
