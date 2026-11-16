"""
L1 — acoustic descriptors. Input: mono waveform at L0's sample rate + the L0
bark-segment list. Output: BurstFeatures.

F0 and HNR both come from Praat (praat-parselmouth), on purpose:
  * to_pitch_ac + to_harmonicity_cc share one autocorrelation framework, so the
    two features are mutually self-consistent (a librosa/Praat mix would not be).
  * Praat needs ~3 pitch periods (~30 ms at floor=100 Hz). Segments shorter than
    that, or too unvoiced, return f0_mean=None — we do NOT lower the floor to
    force a number out of noise.
  * Growls routinely return f0=None. That is correct and informative, not a bug:
    growl is noise-dominated and the low HNR already carries that signal.

Everything else (spectral centroid/flatness, rms_peak, attack_time, tonality) is
plain numpy + scipy. parselmouth is required, but it can still raise on degraded
segments, so a spectral HNR fallback is kept per-segment and tagged in
hnr_method — a silently different metric would corrupt the baseline.

No magic numbers: all thresholds/windows come from config `semantics.l1`.
"""
from __future__ import annotations

import math

import numpy as np
import parselmouth
from scipy import signal as sp_signal

from schema import BarkFeatures, BurstFeatures

_EPS = 1e-12


def _spectral(seg: np.ndarray, sr: int, n_fft: int) -> tuple[float, float]:
    """(spectral_centroid_hz, spectral_flatness[0..1]) over the segment."""
    if seg.size < 8:
        return 0.0, 1.0
    win = min(n_fft, seg.size)
    f, _, Zxx = sp_signal.stft(seg, fs=sr, nperseg=win, noverlap=win // 2)
    psd = np.abs(Zxx).mean(axis=1) + _EPS
    centroid = float(np.sum(f * psd) / np.sum(psd))
    gm = math.exp(float(np.mean(np.log(psd))))
    flatness = float(gm / float(np.mean(psd)))
    return centroid, min(max(flatness, 0.0), 1.0)


def _rms_peak_attack(seg: np.ndarray, sr: int, frame_s: float) -> tuple[float, float]:
    """(peak short-frame RMS, time-to-peak seconds)."""
    fl = max(1, int(frame_s * sr))
    hop = max(1, fl // 2)
    if seg.size < fl:
        return float(np.sqrt(np.mean(seg ** 2)) + _EPS), 0.0
    rms = np.array([np.sqrt(np.mean(seg[i:i + fl] ** 2))
                    for i in range(0, seg.size - fl + 1, hop)])
    return float(rms.max()), float(np.argmax(rms) * hop / sr)


def _spectral_hnr_db(flatness: float) -> float:
    """Spectral fallback HNR (dB proxy): peaky spectrum -> high, flat -> low.
    Different scale from Praat's cc HNR — hence hnr_method records which ran."""
    return float(-10.0 * math.log10(flatness + _EPS))


def _tonality(flatness: float, hnr_praat: float | None, tcfg: dict) -> float:
    """Continuous harmonicity ~[0,1]. Mostly (1 - spectral_flatness), nudged by
    Praat HNR when available. NOT a discrete bark/whine/growl label."""
    tonal = 1.0 - flatness
    if hnr_praat is None:
        return min(max(tonal, 0.0), 1.0)
    hnr_norm = min(max(hnr_praat / tcfg["hnr_norm_db"], 0.0), 1.0)
    wf, wh = tcfg["flatness_weight"], tcfg["hnr_weight"]
    t = (wf * tonal + wh * hnr_norm) / (wf + wh)
    return min(max(t, 0.0), 1.0)


def compute_bark_features(seg: np.ndarray, sr: int, l1cfg: dict) -> BarkFeatures:
    duration = len(seg) / sr
    f0cfg = l1cfg["f0"]
    centroid, flatness = _spectral(seg, sr, l1cfg["spectral"]["n_fft"])
    rms_peak, attack = _rms_peak_attack(seg, sr, l1cfg["rms"]["frame_s"])

    f0_mean = f0_std = None
    voiced_frac = 0.0
    hnr = None
    hnr_method = "praat"

    try:
        snd = parselmouth.Sound(np.ascontiguousarray(seg, dtype=np.float64),
                                sampling_frequency=sr)
    except Exception:
        snd = None

    # F0 — only when long enough; short/unvoiced -> None (no forced number)
    if snd is not None and duration >= f0cfg["min_segment_s"]:
        try:
            pitch = snd.to_pitch_ac(pitch_floor=f0cfg["pitch_floor"],
                                    pitch_ceiling=f0cfg["pitch_ceiling"])
            fv = pitch.selected_array["frequency"]  # 0 == unvoiced
            voiced = fv[fv > 0]
            voiced_frac = float(len(voiced) / len(fv)) if len(fv) else 0.0
            if voiced_frac >= f0cfg["min_voiced_frac"] and voiced.size:
                f0_mean = float(voiced.mean())
                f0_std = float(voiced.std())
        except Exception:
            pass  # f0 stays None

    # HNR — Praat cc, else spectral fallback (tagged)
    if snd is not None:
        try:
            harm = snd.to_harmonicity_cc(minimum_pitch=f0cfg["pitch_floor"])
            hv = harm.values.flatten()
            hv = hv[hv != -200]  # -200 dB == undefined
            if hv.size:
                hnr = float(hv.mean())
                hnr_method = "praat"
            else:
                raise ValueError("no defined HNR frames")
        except Exception:
            hnr = _spectral_hnr_db(flatness)
            hnr_method = "spectral_fallback"
    else:
        hnr = _spectral_hnr_db(flatness)
        hnr_method = "spectral_fallback"

    tonality = _tonality(flatness, hnr if hnr_method == "praat" else None,
                         l1cfg["tonality"])

    return BarkFeatures(
        duration=duration, f0_mean=f0_mean, f0_std=f0_std,
        f0_voiced_frac=voiced_frac, hnr=hnr, hnr_method=hnr_method,
        rms_peak=rms_peak, attack_time=attack, spectral_centroid=centroid,
        tonality=tonality,
    )


def segment_bursts(segments: list[dict], burst_gap_s: float) -> list[list[dict]]:
    """Group L0 bark segments into bursts split at gaps >= burst_gap_s."""
    bursts: list[list[dict]] = []
    cur: list[dict] = []
    for seg in sorted(segments, key=lambda s: s["start_s"]):
        if cur and seg["start_s"] - cur[-1]["end_s"] >= burst_gap_s:
            bursts.append(cur)
            cur = []
        cur.append(seg)
    if cur:
        bursts.append(cur)
    return bursts


def compute_burst_features(wav: np.ndarray, sr: int, burst: list[dict],
                           l1cfg: dict) -> BurstFeatures:
    barks, onsets = [], []
    for seg in burst:
        s, e = int(seg["start_s"] * sr), int(seg["end_s"] * sr)
        barks.append(compute_bark_features(wav[s:e], sr, l1cfg))
        onsets.append(seg["start_s"])
    n = len(barks)
    duration = burst[-1]["end_s"] - burst[0]["start_s"]
    ibi_mean = ibi_cv = None
    if n >= 2:
        ibis = np.diff(onsets)                       # onset-to-onset intervals
        m = float(ibis.mean())
        ibi_mean = m
        ibi_cv = float(ibis.std() / m) if m > 0 else None
    return BurstFeatures(n_barks=n, duration=duration, ibi_mean=ibi_mean,
                         ibi_cv=ibi_cv, barks=barks)


def features_from_segments(wav: np.ndarray, sr: int, segments: list[dict],
                           cfg: dict) -> list[BurstFeatures]:
    """Top-level L1: L0 segment list -> per-burst features."""
    l1cfg = cfg["semantics"]["l1"]
    return [compute_burst_features(wav, sr, b, l1cfg)
            for b in segment_bursts(segments, l1cfg["burst_gap_s"])]
