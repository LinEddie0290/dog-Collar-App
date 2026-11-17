"""Frozen CED-tiny embedding for server-side inference.

The embedding MUST be bit-for-bit the same function used to build the training
cache (offline/extract_crops.py::ced_embedder): each W-second window is cut and
embedded INDEPENDENTLY (AmplitudeToDB top_db is relative to that window's own
max), CED-tiny encoder tokens are pooled as [mean, max] -> 384-d. Verified
against cache/emb_ced_W2.npy to max|diff| < 1e-4.

The encoder is deliberately isolated behind `Embedder` so it can be swapped
later (e.g. an ONNX/TFLite CED export for a mobile path) without touching the
heads or the streaming logic.
"""
from __future__ import annotations

import os
import json
import hashlib
import numpy as np

TARGET_SR = 16000
HERE = os.path.dirname(os.path.abspath(__file__))


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def verify_weights(model_dir: str, manifest_path: str) -> None:
    """Refuse to start unless every pinned file is present and its sha256 matches.
    Runtime does NOT touch the network (confidential-computing requirement):
    weights are baked into the deploy image/package by fetch_weights.py at build.
    """
    if not os.path.isdir(model_dir):
        raise RuntimeError(f"CED weights dir not found: {model_dir}\n"
                           f"Populate it at BUILD time with serve/fetch_weights.py (no runtime download).")
    man = json.load(open(manifest_path))["ced_tiny"]["files"]
    bad = []
    for name, want in man.items():
        p = os.path.join(model_dir, name)
        if not os.path.isfile(p):
            bad.append(f"missing {name}")
        else:
            got = _sha256(p)
            if got != want:
                bad.append(f"sha256 mismatch {name}: got {got[:12]}.. want {want[:12]}..")
    if bad:
        raise RuntimeError("CED weight verification FAILED (refusing to start):\n  " + "\n  ".join(bad))


def to_float_mono_16k(pcm, sr: int) -> np.ndarray:
    """int16 (or float) PCM -> float32 mono [-1,1] @ 16 kHz."""
    x = np.frombuffer(pcm, dtype=np.int16) if isinstance(pcm, (bytes, bytearray)) else np.asarray(pcm)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if np.issubdtype(x.dtype, np.integer):
        x = x.astype(np.float32) / 32768.0
    else:
        x = x.astype(np.float32)
    if sr != TARGET_SR:
        from math import gcd
        from scipy.signal import resample_poly
        g = gcd(int(sr), TARGET_SR)
        x = resample_poly(x, TARGET_SR // g, int(sr) // g).astype(np.float32)
    return x


def crop(x: np.ndarray, center_s: float, W: float) -> np.ndarray:
    """W-second window centered on center_s, zero-padded past the signal edges
    (identical to offline/extract_crops.crop)."""
    n = int(round(W * TARGET_SR))
    s = int(round((center_s - W / 2) * TARGET_SR))
    out = np.zeros(n, np.float32)
    a, b = max(0, s), min(len(x), s + n)
    if b > a:
        out[a - s:b - s] = x[a:b]
    return out


class CEDEmbedder:
    """CED-tiny (mispeech/ced-tiny) frozen encoder -> 384-d [mean,max]."""

    dim = 384

    def __init__(self, model_dir: str, weights_manifest: str | None = None):
        """model_dir: local path to the CED-tiny weights (REQUIRED). No HF fallback:
        runtime never downloads. weights_manifest pins sha256 of every file loaded;
        verified before use, mismatch -> refuse to start."""
        # hard-offline: transformers must not reach out even if code changes
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
        os.environ["HF_HUB_OFFLINE"] = "1"
        if not model_dir:
            raise ValueError("CEDEmbedder requires an explicit local model_dir (no HF fallback).")
        manifest = weights_manifest or os.path.join(HERE, "weights_manifest.json")
        verify_weights(model_dir, manifest)
        import torch
        from transformers import AutoFeatureExtractor, AutoModelForAudioClassification
        self._torch = torch
        self.fe = AutoFeatureExtractor.from_pretrained(model_dir, trust_remote_code=True, local_files_only=True)
        self.enc = AutoModelForAudioClassification.from_pretrained(
            model_dir, trust_remote_code=True, local_files_only=True).eval().encoder
        torch.set_num_threads(min(8, os.cpu_count() or 1))

    def embed_window(self, w: np.ndarray) -> np.ndarray:
        with self._torch.no_grad():
            h = self.enc(self.fe(w, sampling_rate=TARGET_SR)["input_values"])[0][0].numpy()
        return np.concatenate([h.mean(0), h.max(0)]).astype(np.float32)

    def embed_stream(self, wav: np.ndarray, W: float, hop: float):
        """Slide a W-second window at `hop` over `wav`; return (E[N,384], centers[N])."""
        dur = len(wav) / TARGET_SR
        centers = np.arange(W / 2, max(W / 2, dur - W / 2) + 1e-9, hop)
        E = np.zeros((len(centers), self.dim), np.float32)
        for i, c in enumerate(centers):
            E[i] = self.embed_window(crop(wav, float(c), W))
        return E, centers
