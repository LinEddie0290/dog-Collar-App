"""
Typed contracts for the semantic layers (L1/L2/L3). Dataclasses only, no logic.

These are the stable interface every downstream module depends on, and — per the
no-blocking-the-feedback-loop rule — AffectEstimate.components and
Hypothesis.evidence are plain JSON-serializable types because they later become
the stored training signal.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal


@dataclass
class BarkFeatures:
    """L1 acoustic descriptors for a single bark segment."""
    duration: float
    f0_mean: float | None          # None when unvoiced / segment too short for Praat
    f0_std: float | None
    f0_voiced_frac: float
    hnr: float | None
    hnr_method: Literal["praat", "spectral_fallback"]
    rms_peak: float
    attack_time: float
    spectral_centroid: float
    tonality: float                # continuous harmonicity in ~[0,1], NOT a
                                   # bark/whine/growl label. Additive to (does not
                                   # replace) L0's discrete `type`.


@dataclass
class BurstFeatures:
    """A run of barks separated by < burst_gap_s."""
    n_barks: int
    duration: float
    ibi_mean: float | None         # None when n_barks < 2 (never substitute 0)
    ibi_cv: float | None
    barks: list[BarkFeatures]


@dataclass
class AffectEstimate:
    """L1 arousal/valence as PERCENTILE RANKS against this individual's own
    baseline.

    NOTE — do not confuse with L0's `arousal_proxy` in the event dict. That is a
    raw-RMS heuristic on absolute loudness; THIS `arousal` is a per-individual,
    per-device percentile and is the only 'arousal' any downstream module may
    consume. They are different quantities and must never be crossed.
    """
    arousal: float | None          # [0,1], None when no baseline at all
    valence: float | None
    confidence: float              # [0,1]
    learning_period: bool
    baseline_n: int
    components: dict[str, float]   # per-feature percentile rank -> evidence


@dataclass
class Slot:
    value: Any | None
    confidence: float
    source: str                    # provider name, for provenance/debugging


@dataclass
class ContextSnapshot:
    env_events: Slot
    time_of_day: Slot
    baseline: Slot
    is_alone: Slot                 # v1: always Slot(None, 0.0, "unavailable")
    motion_state: Slot             # v1: always Slot(None, 0.0, "no_imu")
    recent_activity: Slot          # v1: always Slot(None, 0.0, "no_imu")

    def missing(self) -> list[str]:
        """Slot names whose value is None (unavailable in this run)."""
        return [name for name in ("env_events", "time_of_day", "baseline",
                                  "is_alone", "motion_state", "recent_activity")
                if getattr(self, name).value is None]


class Intent(str, Enum):
    ALERT_GUARD = "alert_guard"
    DEMAND_ATTENTION = "demand_attention"
    PLAY_EXCITEMENT = "play_excitement"
    DISTRESS_ISOLATION = "distress_isolation"
    DISCOMFORT_PAIN = "discomfort_pain"
    UNKNOWN = "unknown"


@dataclass
class Hypothesis:
    intent: Intent
    confidence: float
    evidence: list[str] = field(default_factory=list)  # each cites a measured value


@dataclass
class Inference:
    hypotheses: list[Hypothesis]   # sorted desc; never empty -> falls back to UNKNOWN
    degraded_slots: list[str]
    observation: str               # measured-only sentence, ALWAYS populated
