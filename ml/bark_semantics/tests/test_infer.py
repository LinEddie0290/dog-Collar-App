"""L3 inference tests: degradation matrix, the safety suppression, schema
integrity. Pure — constructs affect/burst/context directly, no audio/model."""
import itertools
import os
import sys

import pytest
import yaml

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
from infer import infer  # noqa: E402
from schema import (AffectEstimate, BarkFeatures, BurstFeatures,  # noqa: E402
                    ContextSnapshot, Intent, Slot)

CFG = yaml.safe_load(open(os.path.join(HERE, "config.yaml")))


def _bark(tonality=0.3):
    return BarkFeatures(duration=0.2, f0_mean=250.0, f0_std=40.0, f0_voiced_frac=0.7,
                        hnr=6.0, hnr_method="praat", rms_peak=0.6, attack_time=0.01,
                        spectral_centroid=1200.0, tonality=tonality)


def _burst(n=4, tonality=0.3):
    return BurstFeatures(n_barks=n, duration=1.2, ibi_mean=0.3, ibi_cv=0.1,
                         barks=[_bark(tonality) for _ in range(n)])


def _affect():
    # high arousal + low percentiles: satisfies discomfort_pain AND alert_guard
    return AffectEstimate(arousal=0.72, valence=0.3, confidence=0.9,
                          learning_period=False, baseline_n=60,
                          components={"ibi_pct": 0.1, "f0_pct": 0.1, "hnr_pct": 0.1,
                                      "valence_confidence": 0.5})


def _snapshot(env=None, is_alone=None, motion=None):
    def s(v, src_present, src_absent):
        return Slot(v, 1.0 if v is not None else 0.0,
                    src_present if v is not None else src_absent)
    return ContextSnapshot(
        env_events=s(env, "yamnet_scores", "unavailable"),
        time_of_day=Slot({"hour": 14, "day_phase": "afternoon"}, 1.0, "clock"),
        baseline=Slot({"available": True}, 0.9, "baseline"),
        is_alone=s(is_alone, "provider", "unavailable"),
        motion_state=s(motion, "provider", "no_imu"),
        recent_activity=Slot(None, 0.0, "no_imu"),
    )


# ---- SAFETY TEST (do not delete): env_events absent => no discomfort_pain ----
@pytest.mark.parametrize("is_alone,motion", itertools.product([None, True], [None, "still"]))
def test_SAFETY_discomfort_suppressed_when_env_events_missing(is_alone, motion):
    snap = _snapshot(env=None, is_alone=is_alone, motion=motion)  # env MISSING
    inf = infer(_affect(), _burst(), snap, CFG)
    intents = [h.intent for h in inf.hypotheses]
    assert Intent.DISCOMFORT_PAIN not in intents, \
        "discomfort_pain must be suppressed when env_events is missing"
    assert inf.observation  # observation still populated
    assert inf.hypotheses  # never empty


def test_discomfort_can_fire_when_env_present():
    # env present (a benign event) -> discomfort_pain is NOT suppressed and may fire
    snap = _snapshot(env=[{"category": "vehicle", "t_offset": -1.0, "score": 0.4}])
    inf = infer(_affect(), _burst(tonality=0.3), snap, CFG)
    intents = [h.intent for h in inf.hypotheses]
    assert Intent.DISCOMFORT_PAIN in intents
    dp = next(h for h in inf.hypotheses if h.intent == Intent.DISCOMFORT_PAIN)
    assert dp.confidence <= 0.5 + 1e-9  # capped by max_confidence


def test_alert_guard_fires_on_doorbell():
    snap = _snapshot(env=[{"category": "doorbell", "t_offset": -1.8, "score": 0.71}])
    inf = infer(_affect(), _burst(), snap, CFG)
    top = inf.hypotheses[0]
    assert top.intent == Intent.ALERT_GUARD
    assert any("doorbell" in e for e in top.evidence)


def test_distress_never_fires_without_is_alone():
    # is_alone unavailable in v1 -> distress_isolation can never appear
    snap = _snapshot(env=[])  # env available (empty), is_alone missing
    inf = infer(_affect(), _burst(), snap, CFG)
    assert Intent.DISTRESS_ISOLATION not in [h.intent for h in inf.hypotheses]


@pytest.mark.parametrize("env,is_alone,motion",
                         itertools.product([None, [], [{"category": "speech", "t_offset": 0.0, "score": 0.6}]],
                                           [None, True], [None, "still"]))
def test_degradation_matrix_invariants(env, is_alone, motion):
    inf = infer(_affect(), _burst(), _snapshot(env, is_alone, motion), CFG)
    # schema integrity across every slot combination:
    assert inf.observation and isinstance(inf.observation, str)   # always populated
    assert len(inf.hypotheses) >= 1                                # never empty
    for h in inf.hypotheses:
        assert isinstance(h.intent, Intent)                       # only enum values
        assert h.evidence and all(isinstance(e, str) for e in h.evidence)
    # the safety invariant holds everywhere env is absent:
    if env is None:
        assert Intent.DISCOMFORT_PAIN not in [h.intent for h in inf.hypotheses]


def test_total_degradation_returns_unknown_with_observation():
    snap = _snapshot(env=None)  # everything absent
    inf = infer(_affect(), _burst(), snap, CFG)
    assert inf.hypotheses[0].intent == Intent.UNKNOWN
    assert inf.observation


if __name__ == "__main__":
    # plain-runner fallback (no pytest params) for parity with L0 test style
    for env in (None, [], [{"category": "doorbell", "t_offset": -1.0, "score": 0.7}]):
        infer(_affect(), _burst(), _snapshot(env), CFG)
    test_discomfort_can_fire_when_env_present()
    test_alert_guard_fires_on_doorbell()
    test_distress_never_fires_without_is_alone()
    test_total_degradation_returns_unknown_with_observation()
    print("ok: infer smoke (run pytest for full parametrized matrix)")
