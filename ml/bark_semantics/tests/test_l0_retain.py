"""Regression: retaining YAMNet scores is PURELY ADDITIVE — detect()'s events
are byte-identical with the flag on vs off. Uses a fake YAMNet (fixed scores) so
it needs no model/network and is deterministic.

'Purely additive' is a claim that must be test-backed; this is the cheapest
insurance on the only already-verified part of the system (L0)."""
import copy
import os
import sys

import numpy as np
import yaml

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import detect as L0  # noqa: E402

CFG = yaml.safe_load(open(os.path.join(HERE, "config.yaml")))


class _FakeYam:
    """Callable like the TF Hub model: wav -> (scores[F,521], emb, spec)."""
    def __init__(self, scores):
        self.scores = scores

    def __call__(self, wav):
        return (self.scores, None, None)


def _fixed_scores(n_frames=12):
    s = np.zeros((n_frames, 521), dtype=np.float32)
    s[3:8, 69] = 0.8   # Dog high for frames 3..7 -> a bark event
    s[3:8, 70] = 0.7   # Bark
    s[5, 40] = 0.9     # a Pant frame (diagnostic only)
    return s


def test_retain_scores_does_not_change_events():
    scores = _fixed_scores()
    yam = _FakeYam(scores)
    hop = int(CFG["model"]["hop_s"] * L0.TARGET_SR)
    win = int(CFG["model"]["window_s"] * L0.TARGET_SR)
    wav = np.zeros(scores.shape[0] * hop + win, dtype=np.float32)

    cfg_on = copy.deepcopy(CFG); cfg_on["model"]["retain_scores"] = True
    cfg_off = copy.deepcopy(CFG); cfg_off["model"]["retain_scores"] = False

    ev_on, pant_on, sc_on = L0.detect(wav, yam, cfg_on)
    ev_off, pant_off, sc_off = L0.detect(wav, yam, cfg_off)

    assert ev_on == ev_off, "events must be identical regardless of retain flag"
    assert pant_on == pant_off
    assert sc_on is not None and sc_off is None       # flag controls only retention
    assert len(ev_on) >= 1                             # sanity: an event was produced


if __name__ == "__main__":
    test_retain_scores_does_not_change_events()
    print("ok: retain-scores regression (events identical on/off)")
