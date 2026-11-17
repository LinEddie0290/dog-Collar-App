"""Layer 1 orchestration: feed one dog's DayAggregates in date order, get a
daily status per metric and an owner-facing sentence (report.py).

Per metric: status in {"no_history", "learning", "monitoring"}; while learning
only "learning" is output (no z, no alarm). When the frozen baseline locks, the
detector threshold is calibrated on the calibration days plus a population tail
pool of other dogs' out-of-sample z (block bootstrap; target = monthly budget
split across the metrics, divided by a safety factor). CUSUM uses k = 0.75. Missing days: status
"missing", detector not updated, not counted as zero.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from . import baseline as B
from . import detect as D


@dataclass
class MetricState:
    metric: str
    frozen: B.FrozenBaseline
    detector: object = None
    threshold: float | None = None
    calib_fa: float | None = None


@dataclass
class DogMonitor:
    dog_id: str
    metrics: tuple = ("n_bouts", "vocal_s", "n_bouts_alone", "f0_mean", "hnr", "spectral_centroid")
    kind: str = "cusum"
    fa_budget_per_month: float = 1.0
    cfg: dict = field(default_factory=lambda: dict(B.DEFAULTS))
    block_len: int = 7
    pool: dict = None             # metric -> list of population out-of-sample z sequences (detect.calibrate)
    pool_frac: float = 1.0
    safety: float = 2.0           # calibrate to budget / safety (the pool is a proxy for this dog's tail)
    cusum_k: float = 0.75
    history: list = field(default_factory=list)
    states: dict = field(default_factory=dict)

    def __post_init__(self):
        self.states = {m: MetricState(m, B.FrozenBaseline(m, self.cfg)) for m in self.metrics}

    def step(self, day_agg):
        """Process one day (chronological). Returns {metric: dict}."""
        if self.history and day_agg.day <= self.history[-1].day:
            raise ValueError("days must be fed in increasing order")
        out = {}
        for m, st in self.states.items():
            if day_agg.missing:
                out[m] = {"status": "missing"}
                continue
            if st.frozen.stat is None:
                n_valid = sum(not d.missing for d in self.history)
                out[m] = {"status": "no_history" if n_valid == 0 else "learning", "n_days": n_valid + 1,
                          "rolling": B.rolling(self.history, day_agg.day, m, self.cfg)}
                continue
            x = B.day_value(day_agg, m, self.cfg)
            z = st.frozen.stat.z(x)
            alarm = st.detector.update(z)
            out[m] = {"status": "monitoring", "value": x, "z": z, "alarm": alarm, "frozen": st.frozen.stat,
                      "rolling": B.rolling(self.history, day_agg.day, m, self.cfg), "threshold": st.threshold}
        self.history.append(day_agg)
        budget = self.fa_budget_per_month / len(self.states) / self.safety
        kw = {"k": self.cusum_k} if self.kind == "cusum" else {}
        for m, st in self.states.items():                # lock + calibrate AFTER judging today
            if st.frozen.update(self.history):
                zs = [st.frozen.stat.z(B.day_value(d, m, self.cfg)) for d in st.frozen.calib_days]
                st.threshold, st.calib_fa = D.calibrate(zs, self.kind, budget, block_len=self.block_len,
                                                        pool=(self.pool or {}).get(m), pool_frac=self.pool_frac, **kw)
                st.detector = D.make(self.kind, st.threshold, **kw)
                out[m]["calibrated_now"] = True
        return out
