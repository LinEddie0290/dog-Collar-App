"""Model A — event layer (server-side, Python).

audio (int16 16 kHz mono) -> dog-vocalization events:
    { start_ms, end_ms, class, prob, presence, app_slot }

Two frozen-CED heads (pure-numpy, no sklearn at inference):
  * presence (1 s window) — detector p(dog vocalization); defines the bouts.
  * type7    (2 s window) — 7-class {breathing,coughing,dog,pant,sneezing,
               snoring,others}; assigns the class of each detected bout.
               All vocalizations (bark/growl/whine/grunt/moan) fall under `dog`.

`class_map` (config) maps the 7 classes onto the App's existing slots (e.g.
dog->bark); classes with no mapping are still emitted (app_slot=null) and the
App decides how to show them. Encoder and heads are swappable (see embed.py) so
a future mobile export is not blocked.

Reproduced acceptance (held-out, offline/stream_eval2.py): presence onset
F1 0.562, type/probe7 onset F1 0.360 — see checkpoints/model_a_manifest.json.
"""
from __future__ import annotations

import os
import pickle
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# checkpoints: bundled (serve/checkpoints) first, else repo-level (collar-audio/checkpoints)
CKPT = next((p for p in (os.path.join(HERE, "checkpoints"), os.path.join(ROOT, "checkpoints"))
             if os.path.isdir(p)), os.path.join(ROOT, "checkpoints"))


# --------------------------------------------------------------- heads ------
def _load(path):
    with open(path, "rb") as f:
        return pickle.load(f)


def _standardize(E, h):
    return (E - h["scaler_mean"]) / h["scaler_scale"]


def presence_score(E, h):
    """p(dog vocalization) per row. Binary LR -> sigmoid."""
    z = _standardize(E, h) @ h["lr_coef"][0] + h["lr_intercept"][0]
    return 1.0 / (1.0 + np.exp(-z))


def type7_proba(E, h):
    """softmax over the 7 classes per row (no bias)."""
    logits = _standardize(E, h) @ h["lr_coef"].T + h["lr_intercept"]
    logits -= logits.max(1, keepdims=True)
    P = np.exp(logits)
    return P / P.sum(1, keepdims=True)


# --------------------------------------------------- streaming -> bouts -----
# (identical semantics to offline/stream_eval.py::runs / merge / predict_bouts)
def _runs(p, c, th, r, m):
    if m > 1:
        from scipy.ndimage import median_filter
        p = median_filter(p, size=m, mode="nearest")
    on, out, s = False, [], 0
    for i, v in enumerate(p):
        if not on and v >= th:
            on, s = True, i
        elif on and v < th * r:
            out.append((c[s], c[i - 1])); on = False
    if on:
        out.append((c[s], c[-1]))
    return out


def _merge(iv, gap):
    out = []
    for a, b in sorted(iv):
        if out and a - out[-1][1] < gap:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def predict_bouts(p, c, cfg, gap):
    # onset/offset offsets are median corrections; on a very short run they can
    # push end before start -> clamp so every bout stays a valid interval.
    runs = [(a + cfg["o_on"], max(a + cfg["o_on"], b + cfg["o_off"]))
            for a, b in _runs(p, c, cfg["th"], cfg["r"], cfg["m"])]
    return _merge(runs, gap)


# ------------------------------------------------------------- Model A ------
DEFAULTS = {
    "presence_window_s": 1.0,
    "type_window_s": 2.0,
    "hop_s": 0.25,
    "gap_s": 1.0,
    # operating point (tuned on full dogplay; see build_cfg.py / config.yaml)
    "cfg": {"th": 0.7, "r": 0.5, "m": 3, "o_on": 0.0, "o_off": 0.0},
    # 7-class -> App slot. EMPTY by default: the head does not separate bark/growl
    # (all vocalizations = generic `dog`), so we never fill the bark/growl slots.
    # Unmapped classes are emitted with app_slot=None + their real `class`.
    "class_map": {},
    # CED-tiny weights: local only (no runtime download). Relative paths resolve
    # against serve/. Populate the dir at BUILD time via serve/fetch_weights.py.
    "ced_model_dir": "models/ced-tiny",
    "weights_manifest": "weights_manifest.json",
}


def _resolve(p):
    return p if os.path.isabs(p) else os.path.join(HERE, p)


class ModelA:
    def __init__(self, embedder=None, presence_pkl=None, type7_pkl=None, config=None):
        self.cfg = {**DEFAULTS, **(config or {})}
        self.presence = _load(presence_pkl or os.path.join(CKPT, "model_a_v2_presence.pkl"))
        self.type7 = _load(type7_pkl or os.path.join(CKPT, "model_a_type7_W2.pkl"))
        self.labels = self.type7["labels"]
        self.bias = np.array([self.type7["biases_recommended"][l] for l in self.labels])
        if embedder is None:
            from embed import CEDEmbedder
            embedder = CEDEmbedder(model_dir=_resolve(self.cfg["ced_model_dir"]),
                                   weights_manifest=_resolve(self.cfg["weights_manifest"]))
        self.emb = embedder

    def detect(self, pcm, sr=16000):
        from embed import to_float_mono_16k
        wav = to_float_mono_16k(pcm, sr)
        hop = self.cfg["hop_s"]

        # presence stream (1 s) -> bouts
        Ep, cp = self.emb.embed_stream(wav, self.cfg["presence_window_s"], hop)
        p = presence_score(Ep, self.presence)
        bouts = predict_bouts(p, cp, self.cfg["cfg"], self.cfg["gap_s"])
        if not bouts:
            return []

        # type stream (2 s) over the whole signal, reused for every bout
        Et, ct = self.emb.embed_stream(wav, self.cfg["type_window_s"], hop)
        Pt = type7_proba(Et, self.type7)

        events = []
        for a, b in bouts:
            # presence windows inside the bout
            mp = (cp >= a) & (cp <= b)
            pres = float(p[mp].mean()) if mp.any() else float(p[np.argmin(np.abs(cp - (a + b) / 2))])
            # type windows overlapping the bout (fallback: nearest center)
            mt = (ct >= a) & (ct <= b)
            probs = Pt[mt].mean(0) if mt.any() else Pt[np.argmin(np.abs(ct - (a + b) / 2))]
            j = int(np.argmax(np.log(probs + 1e-12) + self.bias))
            cls = self.labels[j]
            emb = Et[mt].mean(0) if mt.any() else Et[np.argmin(np.abs(ct - (a + b) / 2))]
            events.append({
                "start_ms": int(round(a * 1000)),
                "end_ms": int(round(b * 1000)),
                "class": cls,
                "prob": round(float(probs[j]), 3),
                "presence": round(pres, 3),
                "app_slot": self.cfg["class_map"].get(cls),
                "_emb": emb,   # CED [mean,max] of the bout; consumed by Model B (arousal), not for the App
            })
        return events
