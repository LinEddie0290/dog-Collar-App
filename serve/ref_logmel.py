"""Pure-numpy reference log-mel for CED-tiny — the standard the collar C impl aligns to.

NO torchaudio / librosa at runtime. Parameters are from frontend_spec.json (read
from source, not memory). Produces PRE-top_db log-mel: 10*log10(max(mel_power,1e-10)).
The top_db=120 window clamp is NOT applied here — the server applies it per encoding
window in encode_from_logmel (see frontend_spec.json whole_segment_dependent).

Two modes:
  window(x)  reproduce the HF per-window front-end EXACTLY (center=True reflect-pads
             THIS array's own two edges). Self-check target: matches the HF
             CedFeatureExtractor to < 1e-5. Use only for verification.
  stream(x)  model the collar: frame the WHOLE recording continuously (frame k is
             centered at sample k*hop), reflect-pad ONLY at the recording's absolute
             start/end (start_pad param). Interior frames use real neighbouring audio
             — so window edges are NOT mirror-padded, unlike `window`. The server then
             slices these frames by index into the same W-second encoding windows.

Both return log-mel shaped [n_frames, n_mels=64] (time-major).
"""
from __future__ import annotations

import os
import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
# Canonical filterbank shipped alongside (exported ONCE from torchaudio.functional.
# melscale_fbanks(htk, norm=None); the SAME matrix handed to the collar C side, see
# ced_mel_fb_64x257.bin). The analytic htk fb below differs from torchaudio by ~0.5%
# on edge bins, so we load the canonical one to stay bit-aligned with the model.

# ---- pinned front-end params (frontend_spec.json) --------------------------
SR = 16000
N_FFT = 512
WIN = 512
HOP = 160
N_MELS = 64
F_MIN = 0.0
F_MAX = 8000.0
AMIN = 1e-10
PAD = N_FFT // 2          # center=True pads n_fft//2 = 256 each side


def hann_periodic(n=WIN):
    """torch.hann_window(n, periodic=True) = 0.5 - 0.5*cos(2*pi*k/n), k=0..n-1."""
    k = np.arange(n, dtype=np.float64)
    return (0.5 - 0.5 * np.cos(2.0 * np.pi * k / n)).astype(np.float64)


def _hz_to_mel_htk(f):
    return 2595.0 * np.log10(1.0 + f / 700.0)


def _mel_to_hz_htk(m):
    return 700.0 * (10.0 ** (m / 2595.0) - 1.0)


def mel_filterbank(n_freqs=N_FFT // 2 + 1, n_mels=N_MELS, f_min=F_MIN, f_max=F_MAX, sr=SR):
    """htk triangular filterbank [n_freqs, n_mels], norm=None — matches
    torchaudio.functional.melscale_fbanks(mel_scale='htk', norm=None)."""
    all_freqs = np.linspace(0.0, sr / 2.0, n_freqs, dtype=np.float64)
    m_min, m_max = _hz_to_mel_htk(f_min), _hz_to_mel_htk(f_max)
    m_pts = np.linspace(m_min, m_max, n_mels + 2)
    f_pts = _mel_to_hz_htk(m_pts)                       # [n_mels+2]
    f_diff = np.diff(f_pts)                             # [n_mels+1]
    slopes = f_pts[np.newaxis, :] - all_freqs[:, np.newaxis]   # [n_freqs, n_mels+2]
    down = -slopes[:, :-2] / f_diff[:-1]
    up = slopes[:, 2:] / f_diff[1:]
    fb = np.maximum(0.0, np.minimum(down, up))         # [n_freqs, n_mels]
    return fb.astype(np.float64)


_WINDOW = hann_periodic()


def _load_fb():
    """canonical [257,64] fb (torchaudio float32, cast to float64 for compute). Falls
    back to the analytic htk fb with a warning if the shipped file is missing."""
    p = os.path.join(_HERE, "ced_mel_fb_257x64.npy")
    if os.path.isfile(p):
        return np.load(p).astype(np.float64)
    import warnings
    warnings.warn("ced_mel_fb_257x64.npy missing; using analytic htk fb (~0.5% off torchaudio edge bins)")
    return mel_filterbank()


_FB = _load_fb()


def _frame_powmel(x_padded):
    """x_padded: 1D float64 already padded. Returns pre-top_db log-mel [T, n_mels]."""
    n = len(x_padded)
    if n < N_FFT:
        return np.zeros((0, N_MELS), np.float32)
    n_frames = 1 + (n - N_FFT) // HOP
    # frames [n_frames, n_fft]
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(n_frames)[:, None]
    frames = x_padded[idx] * _WINDOW[None, :]
    spec = np.fft.rfft(frames, n=N_FFT, axis=1)        # [T, 257]
    power = (spec.real ** 2 + spec.imag ** 2)          # |.|^2, power=2.0
    mel = power @ _FB                                   # [T, 64]
    logmel = 10.0 * np.log10(np.maximum(mel, AMIN))     # ref=1 -> db_multiplier 0
    return logmel.astype(np.float32)


def stream_debug(x, start_pad="reflect", end_pad="reflect", n_frames=3):
    """Like stream(), but also returns the first `n_frames` of each intermediate
    (windowed frame [512], power spectrum [257], mel energy pre-log [64]) so the C
    side can compare stage by stage. Returns dict of float64 arrays."""
    x = np.asarray(x, np.float64)
    xp = np.pad(np.pad(x, (PAD, 0), mode=("reflect" if start_pad == "reflect" else "constant")),
                (0, PAD), mode=("reflect" if end_pad == "reflect" else "constant"))
    n = len(xp)
    nf = 1 + (n - N_FFT) // HOP if n >= N_FFT else 0
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(nf)[:, None]
    frames = xp[idx] * _WINDOW[None, :]
    spec = np.fft.rfft(frames, n=N_FFT, axis=1)
    power = spec.real ** 2 + spec.imag ** 2
    mel = power @ _FB
    logmel = 10.0 * np.log10(np.maximum(mel, AMIN))
    k = min(n_frames, nf)
    return {"windowed_frames": frames[:k].astype(np.float32),
            "power_spectrum": power[:k].astype(np.float32),
            "mel_energy": mel[:k].astype(np.float32),
            "logmel_pre_top_db": logmel.astype(np.float32)}


def window(x):
    """Per-window front-end with center=True reflect pad on this array's two edges.
    Reproduces the HF CedFeatureExtractor for a single window (self-check)."""
    x = np.asarray(x, np.float64)
    xp = np.pad(x, (PAD, PAD), mode="reflect")
    return _frame_powmel(xp)


def stream(x, start_pad="reflect", end_pad="reflect"):
    """Continuous framing of the WHOLE recording. Frame k centered at sample k*HOP.
    Reflect(or zero)-pad ONLY at the recording's absolute start/end. Interior frames
    (incl. window boundaries) use real audio — this is what the collar computes."""
    x = np.asarray(x, np.float64)
    xp = np.pad(x, (PAD, PAD), mode=("reflect" if start_pad == "reflect" else "constant")) \
        if start_pad == end_pad else \
        np.pad(np.pad(x, (PAD, 0), mode=("reflect" if start_pad == "reflect" else "constant")),
               (0, PAD), mode=("reflect" if end_pad == "reflect" else "constant"))
    return _frame_powmel(xp)


def frames_for_window(center_s, W):
    """Which STREAM frame indices make up the W-second encoding window centered at
    center_s. The server uses this to slice stream log-mel into the same windows the
    waveform path builds via embed.crop. A W-second window = W*SR samples; with
    center framing its frames are those whose centers fall in [start, start+W*SR)."""
    start = int(round((center_s - W / 2) * SR))
    n = int(round(W * SR))
    # stream frame k center (original coords) = k*HOP ; window covers samples [start, start+n)
    k0 = int(np.ceil(start / HOP))
    k1 = int(np.floor((start + n - 1) / HOP))
    return max(0, k0), k1  # inclusive range [k0, k1]


if __name__ == "__main__":
    # tiny self-smoke
    rng = np.random.default_rng(0)
    x = rng.standard_normal(16000).astype(np.float32) * 0.1
    print("window", window(x).shape, "stream", stream(x).shape, "fb", _FB.shape)
