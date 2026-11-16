"""L1 baseline tests — SQLite store in a temp file, no model/network."""
import os
import sys
import tempfile

import yaml

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import baseline as B  # noqa: E402
from schema import BarkFeatures, BurstFeatures  # noqa: E402

BCFG = yaml.safe_load(open(os.path.join(HERE, "config.yaml")))["semantics"]["baseline"]


def _bark(dur=0.2, f0=300.0, f0_std=20.0, hnr=15.0, tonality=0.6, rms=0.5):
    return BarkFeatures(duration=dur, f0_mean=f0, f0_std=f0_std, f0_voiced_frac=0.8,
                        hnr=hnr, hnr_method="praat", rms_peak=rms, attack_time=0.01,
                        spectral_centroid=1000.0, tonality=tonality)


def _burst(n=3, ibi=0.4, **bk):
    barks = [_bark(**bk) for _ in range(n)]
    return BurstFeatures(n_barks=n, duration=ibi * (n - 1) + 0.2,
                         ibi_mean=(ibi if n >= 2 else None),
                         ibi_cv=(0.1 if n >= 2 else None), barks=barks)


def _store():
    fd, path = tempfile.mkstemp(suffix=".sqlite")
    os.close(fd)
    return B.SQLiteBaselineStore(path), path


def _seed(store, dog, device, n, days=5, **bk):
    for i in range(n):
        bf = _burst(**bk)
        store.add(dog, device, f"2026-09-{(i % days) + 1:02d}", B.burst_scalars(bf))


def test_store_creates_missing_parent_dir():
    # regression: a fresh checkout has no data/ dir; the store must create it
    import tempfile
    d = tempfile.mkdtemp()
    path = os.path.join(d, "nested", "sub", "baselines.sqlite")
    store = B.SQLiteBaselineStore(path)           # must not raise
    store.add("rex", "phone", "2026-09-13", B.burst_scalars(_burst()))
    assert store.n_samples("rex", "phone") == 1
    assert os.path.exists(path)


def test_percentile_rank_correct():
    store, _ = _store()
    # seed rms_peak distribution 0.0..0.9 (10 samples)
    for i in range(10):
        store.add("rex", "phone", f"2026-09-{i+1:02d}",
                  B.burst_scalars(_burst(rms=i / 10.0)))
    hist = store.history("rex", "phone")
    assert abs(B._pct(hist, "rms_peak", 0.5) - 0.6) < 1e-9  # {0..0.5} = 6/10


def test_empty_history_returns_none_estimate():
    store, _ = _store()
    est = B.estimate_affect(_burst(), "nobody", "phone", store, BCFG)
    assert est.arousal is None and est.valence is None
    assert est.confidence == 0.0 and est.baseline_n == 0


def test_learning_period_and_penalty():
    store, _ = _store()
    _seed(store, "rex", "phone", n=10, days=2)          # < 30 samples, < 3 days
    est = B.estimate_affect(_burst(rms=0.9), "rex", "phone", store, BCFG)
    assert est.learning_period is True
    # confidence must reflect the penalty (<= n/min * penalty)
    assert est.confidence <= (10 / BCFG["min_baseline_samples"]) * BCFG["learning_confidence_penalty"] + 1e-9
    assert est.arousal is not None  # still produces a percentile once history exists


def test_device_separation():
    store, _ = _store()
    _seed(store, "rex", "phone_mic", n=40, days=5)
    assert store.n_samples("rex", "phone_mic") == 40
    assert store.n_samples("rex", "collar_mic") == 0     # no leak across devices
    est = B.estimate_affect(_burst(), "rex", "collar_mic", store, BCFG)
    assert est.baseline_n == 0 and est.arousal is None   # collar has no baseline yet


def test_valence_confidence_capped():
    store, _ = _store()
    _seed(store, "rex", "phone", n=60, days=5)           # plenty of history
    est = B.estimate_affect(_burst(rms=0.9), "rex", "phone", store, BCFG)
    assert est.valence is not None
    assert est.components["valence_confidence"] <= BCFG["valence_confidence_cap"] + 1e-9


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print("ok:", fn.__name__)
    print(f"\nALL {len(fns)} BASELINE TESTS PASSED ✅")
