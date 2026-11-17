"""Model B — state layer (server-side, Python), feeds the App '心理' board.

Product stance (fixed): "relative to THIS dog's own baseline, has anything
changed" — welfare/health direction. NO emotion translation, NO diagnosis
(enforced by monitor/report.py FORBIDDEN list). Daily output per dog×device:
  * counts_by_type   — per-type bout counts (Model A `class`)
  * n_bouts          — total bouts + z vs own baseline + higher/lower + status
  * arousal          — daily arousal intensity (0..2, relative signal only) + z
  * status           — no_history / learning / monitoring (per metric)
  * sentence         — owner-facing, observation-only (monitor/report.py)

Only the WEARER's own vocalizations are counted. Per offline/MODEL_B_REPORT T3
the voiceprint alone is too weak for a collar (CED+LDA EER 0.27, optimistic);
NearFieldCheck (near-field energy) is the PRIMARY gate and needs collar-recorded
calibration (placeholder params). Here each event carries wearer_score (None =
not computed -> passes); wire NearFieldCheck/WearerVerifier from monitor/wearer.py
once collar audio exists.

Reuses the already-built monitor/ stack (aggregate, baseline, CUSUM detect,
report). Arousal head: checkpoints/model_b_arousal.pkl (acc 0.505 ~ report 0.51).
"""
from __future__ import annotations

import os
import sys
import pickle
import datetime as dt
from collections import Counter

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# `monitor/` package: bundled (serve/monitor) or repo-level (collar-audio/monitor)
sys.path.insert(0, ROOT)
sys.path.insert(0, HERE)
CKPT = next((p for p in (os.path.join(HERE, "checkpoints"), os.path.join(ROOT, "checkpoints"))
             if os.path.isdir(p)), os.path.join(ROOT, "checkpoints"))

from monitor import events as EV
from monitor import aggregate as AG
from monitor import baseline as B
from monitor import monitor as MON
from monitor import report as RP


def _softmax_expected(emb, h):
    z = (emb - h["scaler_mean"]) / h["scaler_scale"]
    logit = z @ h["lr_coef"].T + h["lr_intercept"]
    logit -= logit.max()
    p = np.exp(logit); p /= p.sum()
    return float((p * np.array(h["intensity_levels"])).sum())   # 0..2


class ModelB:
    # rhythm metric (n_bouts) + arousal (treated as a timbre-style metric so it
    # reuses the robust baseline/CUSUM machinery); both judged vs the dog's own history.
    METRICS = ("n_bouts", "arousal")

    def __init__(self, arousal_pkl=None, dog_id="dog", device="collar", utc_offset_h=0.0,
                 fa_budget_per_month=1.0, time_of_day_known=False, wearer_verification="disabled"):
        self.arousal = pickle.load(open(arousal_pkl or os.path.join(CKPT, "model_b_arousal.pkl"), "rb"))
        self.dog_id = dog_id
        self.device = device
        self.tz = utc_offset_h
        # only emit a time-of-day phrase when event timestamps are real wall-clock
        # (collar RTC). For dataset audio there is NO trusted clock -> suppress it.
        self.time_of_day_known = time_of_day_known
        # wearer gate is OFF until the voiceprint head is enabled AND NearFieldCheck
        # is calibrated on collar audio -> counts may include other dogs / TV dogs.
        self.wearer_verification = wearer_verification
        self.mon = MON.DogMonitor(dog_id=dog_id, metrics=self.METRICS, fa_budget_per_month=fa_budget_per_month)

    # ---- one day: Model A events -> DayAggregate (+ per-type counts, arousal) ----
    def day_aggregate(self, a_events, day: dt.date, coverage_h: float, day_start_unix: float | None = None):
        if day_start_unix is None:
            day_start_unix = dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc).timestamp()
        evs, arous = [], []
        counts = Counter()
        for e in a_events:
            ws = e.get("wearer_score")              # None -> passes the layer-0 gate
            t0 = day_start_unix + e["start_ms"] / 1000.0
            t1 = day_start_unix + e["end_ms"] / 1000.0
            a = _softmax_expected(np.asarray(e["_emb"]), self.arousal) if "_emb" in e else None
            evs.append(EV.Event(dog_id=self.dog_id, t_start=t0, t_end=t1, type=e["class"],
                                wearer_score=ws, device=self.device,
                                features=(("arousal", a),) if a is not None else ()))
            if ws is None or ws >= 0.5:
                counts[e["class"]] += 1
                if a is not None:
                    arous.append(a)
        cov = {day: coverage_h}
        agg = AG.aggregate_days(evs, cov, dog_id=self.dog_id, device=self.device,
                                utc_offset_h=self.tz, min_coverage_h=0.0)[day]
        # inject daily arousal as a timbre-style metric (median over the day's events)
        if arous:
            agg.timbre["arousal"] = float(np.median(arous)); agg.timbre_n["arousal"] = len(arous)
        return agg, dict(counts)

    # ---- step the monitor one day, return the App-facing daily state ----
    def step_day(self, a_events, day: dt.date, coverage_h: float, dog_name="它"):
        agg, counts = self.day_aggregate(a_events, day, coverage_h)
        if not self.time_of_day_known:
            agg.hour_hist = [0] * 24      # no trusted clock -> no time-of-day phrase
        status = self.mon.step(agg)

        def metric_out(m):
            s = status.get(m, {})
            o = {"status": s.get("status")}
            if s.get("status") == "monitoring":
                z = s["z"]
                o.update(value=round(float(s["value"]), 3), z=round(float(z), 2),
                         direction=("higher" if z > 0 else "lower" if z < 0 else "same"),
                         alarm=bool(s["alarm"]),
                         baseline_median=round(float(s["frozen"].median), 3))
            elif s.get("status") in ("learning", "no_history"):
                o["n_days"] = s.get("n_days")
            return o

        arousal = {"daily_intensity": round(agg.timbre.get("arousal"), 2) if "arousal" in agg.timbre else None,
                   "signal": "weak_relative_only",
                   "note": "arousal head trained on EmotionalCanines (acc 0.505); on collar-domain audio it is "
                           "out-of-domain and regresses toward the ~1.0 prior. Relative changes only, unvalidated here.",
                   **metric_out("arousal")}
        return {
            "dog_id": self.dog_id, "device": self.device, "date": day.isoformat(),
            # wearer gate is OFF -> these counts may include other dogs / TV dogs
            "wearer_verification": self.wearer_verification,
            "counts_by_type": counts,
            "n_bouts": {"total": agg.n_bouts, **metric_out("n_bouts")},
            "arousal": arousal,
            "sentence": RP.daily_sentence(agg, status, dog_name),
        }
