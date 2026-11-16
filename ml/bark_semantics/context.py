"""
L2 — pluggable context. Only the audio-derivable providers are implemented.

EnvEventProvider reuses L0's RETAINED 521-class YAMNet scores (no second
inference pass) to spot doorbell/knock/door/speech/footsteps/vehicle/phone
around a burst.

HARD LIMITATION (enforced below, not just documented): YAMNet cannot tell the
subject dog from another dog, so the `Dog` class is NOT a usable "other_dog"
context signal. It is not in the class map and any attempt to add it raises.

is_alone / motion_state / recent_activity are permanently-None slots with an
explicit source. They are provided via the same provider-dict as everything
else, so wiring a collar later means ADDING A PROVIDER to the dict — no change
to build_context_snapshot's signature, schema.py, or infer.py.
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta
from typing import Protocol

import numpy as np

from schema import ContextSnapshot, Slot


class ContextProvider(Protocol):
    slot_name: str
    def get(self, t: float, window: tuple[float, float] | None = None) -> Slot: ...


class EnvEventProvider:
    slot_name = "env_events"

    def __init__(self, scores: np.ndarray | None, class_names: list[str],
                 ccfg: dict, hop_s: float):
        self.scores = scores
        self.hop = hop_s
        self.threshold = ccfg["env_score_threshold"]
        self.window = tuple(ccfg["env_window_s"])
        name2idx = {n: i for i, n in enumerate(class_names)}
        # Enforce the subject-vs-other-dog limitation at construction time.
        for cat, names in ccfg["env_class_map"].items():
            if "Dog" in names:
                raise ValueError(
                    "'Dog' must not be mapped as context — YAMNet cannot separate "
                    "the subject dog from another dog.")
        self.cat_idx = {cat: [name2idx[n] for n in names if n in name2idx]
                        for cat, names in ccfg["env_class_map"].items()}

    def get(self, t: float, window=None) -> Slot:
        if self.scores is None:
            return Slot(None, 0.0, "unavailable")  # scores not retained -> MISSING
        w = window or self.window
        F = self.scores.shape[0]
        lo = max(0, int(math.floor((t + w[0]) / self.hop)))
        hi = min(F - 1, int(math.ceil((t + w[1]) / self.hop)))
        events = []
        for cat, idxs in self.cat_idx.items():
            if not idxs or hi < lo:
                continue
            frame_scores = self.scores[lo:hi + 1][:, idxs].max(axis=1)
            best = int(np.argmax(frame_scores))
            score = float(frame_scores[best])
            if score >= self.threshold:
                events.append({"category": cat, "score": round(score, 3),
                               "t_offset": round((lo + best) * self.hop - t, 2)})
        events.sort(key=lambda e: -e["score"])
        # value=[] means "looked, found nothing" (available); None means unavailable.
        return Slot(events, 1.0, "yamnet_scores")


class TimeProvider:
    slot_name = "time_of_day"

    def __init__(self, recording_start: datetime | None, ccfg: dict):
        self.rs = recording_start
        self.phases = ccfg["day_phases"]

    def _phase(self, h: int) -> str:
        for name, (a, b) in self.phases.items():
            inside = (a <= h or h < b) if a > b else (a <= h < b)
            if inside:
                return name
        return "unknown"

    def get(self, t: float, window=None) -> Slot:
        if self.rs is None:
            return Slot(None, 0.0, "no_clock")
        wall = self.rs + timedelta(seconds=t)
        return Slot({"hour": wall.hour, "day_phase": self._phase(wall.hour),
                     "iso": wall.isoformat()}, 1.0, "clock")


class BaselineProvider:
    """Exposes baseline availability + learning flag (derived from L1 affect)."""
    slot_name = "baseline"

    def __init__(self, affect):
        self.affect = affect

    def get(self, t: float, window=None) -> Slot:
        a = self.affect
        return Slot({"available": a.baseline_n > 0,
                     "learning_period": a.learning_period,
                     "baseline_n": a.baseline_n}, a.confidence, "baseline")


# Permanent-None slots for the not-yet-wired signals (explicit sources).
def _none_slot(source: str) -> Slot:
    return Slot(None, 0.0, source)


def build_context_snapshot(onset_t: float, providers: dict, affect) -> ContextSnapshot:
    """Assemble a ContextSnapshot. `providers` is a dict keyed by slot_name;
    any slot without a provider falls back to its permanent-None slot. Adding a
    collar later = add a 'motion_state'/'is_alone'/'recent_activity' provider to
    this dict — nothing else changes."""
    defaults = {
        "is_alone": _none_slot("unavailable"),
        "motion_state": _none_slot("no_imu"),
        "recent_activity": _none_slot("no_imu"),
    }

    def slot(name, default):
        p = providers.get(name)
        return p.get(onset_t) if p is not None else default

    return ContextSnapshot(
        env_events=slot("env_events", _none_slot("unavailable")),
        time_of_day=slot("time_of_day", _none_slot("no_clock")),
        baseline=slot("baseline", BaselineProvider(affect).get(onset_t)),
        is_alone=slot("is_alone", defaults["is_alone"]),
        motion_state=slot("motion_state", defaults["motion_state"]),
        recent_activity=slot("recent_activity", defaults["recent_activity"]),
    )
