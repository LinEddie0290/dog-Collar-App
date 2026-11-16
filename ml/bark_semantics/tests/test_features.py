"""L1 feature tests — synthetic signals, no model/network."""
import os
import sys

import numpy as np
import yaml

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import features as F  # noqa: E402

SR = 16000
L1 = yaml.safe_load(open(os.path.join(HERE, "config.yaml")))["semantics"]["l1"]


def _tone(freq, dur, sr=SR):
    t = np.arange(int(dur * sr)) / sr
    return (0.6 * np.sin(2 * np.pi * freq * t)).astype(np.float32)


def test_f0_recovers_known_tone():
    for freq in (300.0, 500.0, 800.0):
        bf = F.compute_bark_features(_tone(freq, 0.4), SR, L1)
        assert bf.f0_mean is not None, f"{freq}Hz tone should be voiced"
        assert abs(bf.f0_mean - freq) < 25, f"{freq}: got {bf.f0_mean}"


def test_white_noise_gives_no_f0():
    rng = np.random.default_rng(0)
    noise = (0.3 * rng.standard_normal(int(0.4 * SR))).astype(np.float32)
    bf = F.compute_bark_features(noise, SR, L1)
    assert bf.f0_mean is None, "noise must not yield a fabricated F0"


def test_short_segment_no_f0():
    bf = F.compute_bark_features(_tone(300, 0.02), SR, L1)  # 20ms < min_segment_s
    assert bf.f0_mean is None


def test_hnr_method_tagging():
    # long clean tone -> praat path works
    clean = F.compute_bark_features(_tone(300, 0.4), SR, L1)
    assert clean.hnr_method == "praat"
    assert clean.hnr is not None
    # tiny segment -> praat harmonicity throws -> spectral fallback, tagged
    tiny = F.compute_bark_features(_tone(300, 0.008), SR, L1)
    assert tiny.hnr_method == "spectral_fallback"
    assert tiny.hnr is not None


def test_tonality_tone_vs_noise():
    tone = F.compute_bark_features(_tone(400, 0.4), SR, L1).tonality
    rng = np.random.default_rng(1)
    noise = F.compute_bark_features(
        (0.3 * rng.standard_normal(int(0.4 * SR))).astype(np.float32), SR, L1).tonality
    assert tone > noise, "harmonic tone should be more tonal than noise"


def _seg(start, end):
    return {"start_s": start, "end_s": end, "type": "bark"}


def test_burst_segmentation_splits_on_gap():
    segs = [_seg(0, 0.2), _seg(0.5, 0.7), _seg(5.0, 5.2)]  # gap 4.3s > 2.0
    bursts = F.segment_bursts(segs, L1["burst_gap_s"])
    assert len(bursts) == 2
    assert len(bursts[0]) == 2 and len(bursts[1]) == 1


def test_ibi_computed_and_none_for_single():
    wav = _tone(400, 6.0)
    multi = F.compute_burst_features(wav, SR, [_seg(0, 0.2), _seg(0.5, 0.7), _seg(1.0, 1.2)], L1)
    assert multi.n_barks == 3
    assert multi.ibi_mean is not None and abs(multi.ibi_mean - 0.5) < 1e-6
    single = F.compute_burst_features(wav, SR, [_seg(0, 0.2)], L1)
    assert single.ibi_mean is None and single.ibi_cv is None  # never 0


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print("ok:", fn.__name__)
    print(f"\nALL {len(fns)} FEATURE TESTS PASSED ✅")
