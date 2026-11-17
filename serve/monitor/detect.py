"""Layer 1 change detection on standardized daily metrics.

z_t = (x_t - median) / scale against the dog's FROZEN baseline (baseline.py).
Two detectors (both two-sided, reset after an alarm, missing days skipped):
  CUSUM : S+ = max(0, S+ + z - k), S- = max(0, S- - z - k); alarm when S > h
  EWMA  : e = lam z + (1 - lam) e; alarm when |e| > L sqrt(lam / (2 - lam))
Per-dog threshold calibration: the dog's own calibration days (no change by
construction) are resampled with a moving-block bootstrap (block_len days, since
neighbouring days are correlated) into horizon-day sequences; the smallest
threshold on a grid whose mean number of alarms per 30 days <= target is chosen.
Two weeks of own history cannot show the tail of the daily z distribution (the
bootstrap only replays those 14 values), so a fraction `pool_frac` of the
simulated sequences is drawn from a POPULATION pool instead: other dogs'
out-of-sample z sequences after their own baseline froze (same standardization),
block-resampled per dog, used unscaled. pool=None -> own days only.
With several metrics monitored, the caller splits the monthly budget across them.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass
class Cusum:
    h: float
    k: float = 0.5
    sp: float = 0.0
    sn: float = 0.0

    def update(self, z):
        if z is None or not np.isfinite(z):
            return None
        self.sp = max(0.0, self.sp + z - self.k)
        self.sn = max(0.0, self.sn - z - self.k)
        if self.sp > self.h or self.sn > self.h:
            d = "up" if self.sp > self.h else "down"
            self.sp = self.sn = 0.0
            return d
        return None


@dataclass
class Ewma:
    L: float
    lam: float = 0.2
    e: float = 0.0

    def update(self, z):
        if z is None or not np.isfinite(z):
            return None
        self.e = self.lam * z + (1 - self.lam) * self.e
        lim = self.L * np.sqrt(self.lam / (2 - self.lam))
        if abs(self.e) > lim:
            d = "up" if self.e > 0 else "down"
            self.e = 0.0
            return d
        return None


GRIDS = {"cusum": np.round(np.arange(1.0, 20.01, 0.25), 2), "ewma": np.round(np.arange(1.0, 8.01, 0.1), 2)}


def make(kind, thr, **kw):
    return Cusum(h=thr, **kw) if kind == "cusum" else Ewma(L=thr, **kw)


def block_bootstrap(z, horizon, n_boot, block_len, rng):
    z = np.asarray([v for v in z if v is not None and np.isfinite(v)], float)
    if len(z) == 0:
        return np.zeros((n_boot, horizon))
    b = min(block_len, len(z)); nb = int(np.ceil(horizon / b))
    starts = rng.integers(0, len(z) - b + 1, size=(n_boot, nb))
    seq = np.concatenate([z[starts[:, j, None] + np.arange(b)] for j in range(nb)], axis=1)
    return seq[:, :horizon]


def count_alarms(kind, thr, sims, k=0.5, lam=0.2):
    """alarms per simulated sequence, vectorized over sims (n_sims, horizon); same
    rules as Cusum / Ewma (reset after alarm)."""
    sims = np.asarray(sims, float); n = np.zeros(len(sims), int)
    if kind == "cusum":
        sp = np.zeros(len(sims)); sn = np.zeros(len(sims))
        for t in range(sims.shape[1]):
            z = sims[:, t]
            sp = np.maximum(0.0, sp + z - k); sn = np.maximum(0.0, sn - z - k)
            hit = (sp > thr) | (sn > thr); n += hit; sp[hit] = 0.0; sn[hit] = 0.0
    else:
        e = np.zeros(len(sims)); lim = thr * np.sqrt(lam / (2 - lam))
        for t in range(sims.shape[1]):
            e = lam * sims[:, t] + (1 - lam) * e
            hit = np.abs(e) > lim; n += hit; e[hit] = 0.0
    return n


def alarms_per_month(kind, thr, sims, **kw):
    return float(count_alarms(kind, thr, sims, **kw).mean()) * (30.0 / sims.shape[1])


def pool_bootstrap(pool, horizon, n_boot, block_len, rng):
    """blocks drawn from randomly chosen sequences of the pool (list of 1-d arrays).
    Pooled z values are used as they are: they are other dogs' days judged against
    their OWN frozen baselines - exactly the quantity being calibrated. (Rescaling
    them to the target dog's 14-day scale was tried and shrinks the tail whenever
    that scale is small: null false alarms rose from 1.2 to 2.2 per dog-month.)"""
    seqs = [np.asarray([v for v in s if v is not None and np.isfinite(v)], float) for s in pool]
    seqs = [s for s in seqs if len(s) >= block_len]
    if not seqs:
        return np.zeros((0, horizon))
    nb = int(np.ceil(horizon / block_len)); out = np.empty((n_boot, nb * block_len))
    pick = rng.integers(0, len(seqs), size=(n_boot, nb))
    for i in range(n_boot):
        for j in range(nb):
            s = seqs[pick[i, j]]; st = rng.integers(0, len(s) - block_len + 1)
            out[i, j * block_len:(j + 1) * block_len] = s[st:st + block_len]
    return out[:, :horizon]


def calibrate(z_hist, kind="cusum", target_per_month=1.0, horizon=90, n_boot=500, block_len=7, seed=0,
              pool=None, pool_frac=0.5, **kw):
    """smallest grid threshold with mean alarms / 30 days <= target on the block bootstrap."""
    rng = np.random.default_rng(seed)
    n_pool = int(round(n_boot * pool_frac)) if pool else 0
    sims = block_bootstrap(z_hist, horizon, n_boot - n_pool, block_len, rng)
    if n_pool:
        ps = pool_bootstrap(pool, horizon, n_pool, block_len, rng)
        sims = np.concatenate([sims, ps]) if len(ps) else sims
    grid = GRIDS[kind]
    lo, hi = 0, len(grid) - 1                      # alarms are monotone non-increasing in thr
    if alarms_per_month(kind, grid[hi], sims, **kw) > target_per_month:
        return float(grid[hi]), alarms_per_month(kind, grid[hi], sims, **kw)
    while lo < hi:
        mid = (lo + hi) // 2
        if alarms_per_month(kind, grid[mid], sims, **kw) <= target_per_month:
            hi = mid
        else:
            lo = mid + 1
    return float(grid[lo]), alarms_per_month(kind, grid[lo], sims, **kw)
