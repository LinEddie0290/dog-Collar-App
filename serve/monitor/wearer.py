"""Layer 0: is this vocalization from the dog WEARING the collar?

This layer deliberately uses identity (who is barking). It is kept separate from
layer 2 (what the bark means), which must not rely on identity cues.

Two independent checks, combined into Event.wearer_score:
  WearerVerifier   enrol the wearer from its first bouts (CED embedding, whitened
                   with POPULATION mean/var, optionally projected with a
                   within-dog LDA fit on OTHER dogs - DogSpeak EER 0.33 -> 0.27 at
                   n = 30 - then L2-normalized, cosine to the enrolment mean).
                   Score mapped to (0, 1) with a logistic around the operating
                   threshold, so 0.5 = threshold (aggregate.py gates
                   on wearer_min = 0.5). offline/wearer_verify.py measures EER /
                   FAR on DogSpeak (far-field, contiguous enrol/test: optimistic).
  NearFieldCheck   the collar mic sits ~10 cm from the wearer's mouth, other dogs
                   are metres away: the wearer's bouts are far louder and have a
                   higher direct-to-background ratio. INTERFACE + PARAMETERS ONLY -
                   the defaults are placeholders and must be measured on collar
                   recordings (none exist yet). Returns None when a level is missing.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np


@dataclass
class PopulationStats:
    mean: np.ndarray
    var: np.ndarray
    proj_mean: np.ndarray | None = None     # LDA: z -> (z - proj_mean) @ proj
    proj: np.ndarray | None = None

    @classmethod
    def fit(cls, embeddings, dog_ids=None, n_components=128):
        """population stats from OTHER dogs; with dog_ids also a shrinkage LDA projection."""
        E = np.asarray(embeddings, float)
        st = cls(E.mean(0), E.var(0))
        if dog_ids is not None:
            from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
            Z = (E - st.mean) / np.sqrt(st.var + 1e-12); y = np.asarray(dog_ids)
            k = min(n_components, len(np.unique(y)) - 1, E.shape[1])
            lda = LinearDiscriminantAnalysis(solver="eigen", shrinkage="auto", n_components=k).fit(Z, y)
            st.proj_mean, st.proj = np.zeros(E.shape[1]), lda.scalings_[:, :k]   # = sklearn eigen-solver transform (no centring), as evaluated
        return st

    def whiten(self, E):
        W = (np.atleast_2d(np.asarray(E, float)) - self.mean) / np.sqrt(self.var + 1e-12)
        if self.proj is not None:
            W = (W - self.proj_mean) @ self.proj
        return W / np.maximum(np.linalg.norm(W, axis=1, keepdims=True), 1e-12)


@dataclass
class WearerVerifier:
    pop: PopulationStats
    threshold: float = 0.30          # cosine; set from the operating point (e.g. FRR 5 %) - see offline/wearer_verify.py
    temperature: float = 0.05
    min_enrol: int = 10
    centroid: np.ndarray | None = None
    n_enrolled: int = 0
    _sum: np.ndarray | None = field(default=None, repr=False)

    @property
    def enrolled(self):
        return self.n_enrolled >= self.min_enrol

    def enrol(self, embeddings):
        """add bouts known (or assumed during set-up) to be the wearer's."""
        W = self.pop.whiten(embeddings)
        self._sum = W.sum(0) if self._sum is None else self._sum + W.sum(0)
        self.n_enrolled += len(W)
        self.centroid = self._sum / max(np.linalg.norm(self._sum), 1e-12)

    def cosine(self, embedding):
        if not self.enrolled:
            return None
        return float(self.pop.whiten(embedding)[0] @ self.centroid)

    def score(self, embedding):
        """wearer probability-like score in (0, 1); None before enrolment is complete."""
        c = self.cosine(embedding)
        if c is None:
            return None
        return float(1.0 / (1.0 + np.exp(-(c - self.threshold) / self.temperature)))


@dataclass
class NearFieldCheck:
    """placeholders - measure on collar data before use."""
    min_peak_dbfs: float = -30.0     # wearer's bouts peak above this at the collar mic
    min_margin_db: float = 15.0      # bout peak minus the rolling background level

    def __call__(self, peak_dbfs, background_dbfs):
        if peak_dbfs is None or background_dbfs is None:
            return None
        return bool(peak_dbfs >= self.min_peak_dbfs and peak_dbfs - background_dbfs >= self.min_margin_db)


def combine(verifier_score, near_field):
    """wearer_score for Event: near-field failure vetoes; missing checks are skipped;
    None when neither check is available (aggregate.py then keeps the bout)."""
    if near_field is False:
        return 0.0
    if verifier_score is None:
        return None if near_field is None else 1.0
    return verifier_score
