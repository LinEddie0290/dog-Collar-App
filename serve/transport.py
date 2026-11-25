"""Collar upload transport for pre-top_db log-mel. CONTRACT (frozen format):

The collar computes pre-top_db log-mel [T, 64] (ref_logmel.stream) and uploads it
quantized to **int8 per-segment** (chosen format; see frontend_spec.json transport).

int8 per-segment quantization (per segment of `seg_frames` consecutive frames, over
ALL 64 bins of that segment):
    offset = min(segment)                         # float32
    scale  = (max(segment) - offset) / 255.0      # float32; if 0 -> 1.0 (silent seg)
    q      = round((x - offset) / scale)          # uint8 in [0,255]
dequantize (server):
    x_hat  = q * scale + offset
On the wire per segment: q [seg_frames, 64] uint8, then offset (float32 LE), then
scale (float32 LE). seg_frames = round(seg_len_s * 16000 / 160); default seg_len_s
= 1.0 s (100 frames). The collar segments the CONTINUOUS stream at fixed seg_len_s
(independent of the server's 1 s / 2 s encode windows); the server dequantizes the
whole stream, then slices into encode windows and applies top_db.

`roundtrip()` returns the dequantized log-mel (what the server reconstructs) and is
what the eval feeds to encode_from_logmel, so the eval runs the ACTUAL wire format.
"""
from __future__ import annotations
import numpy as np

HOP, SR = 160, 16000


def seg_frames_for(seg_len_s: float) -> int:
    return max(1, int(round(seg_len_s * SR / HOP)))


def quantize_int8_seg(logmel, seg_frames):
    """-> list of (q_uint8[seg,64], offset f32, scale f32), one per segment."""
    x = np.asarray(logmel, np.float32)
    segs = []
    for s in range(0, len(x), seg_frames):
        blk = x[s:s + seg_frames]
        lo = float(blk.min()); hi = float(blk.max())
        scale = (hi - lo) / 255.0
        if scale <= 0:
            scale = 1.0
        q = np.clip(np.round((blk - lo) / scale), 0, 255).astype(np.uint8)
        segs.append((q, np.float32(lo), np.float32(scale)))
    return segs


def dequantize_int8_seg(segs):
    return np.concatenate([q.astype(np.float32) * float(scale) + float(lo) for q, lo, scale in segs], axis=0)


def roundtrip(logmel, mode="int8_seg", seg_len_s=1.0):
    """apply the transport format's loss and return the reconstructed float32 log-mel."""
    x = np.asarray(logmel, np.float32)
    if mode == "float32":
        return x
    if mode == "fp16":
        return x.astype(np.float16).astype(np.float32)
    if mode == "int8_seg":
        return dequantize_int8_seg(quantize_int8_seg(x, seg_frames_for(seg_len_s)))
    raise ValueError(f"unknown transport mode {mode}")
