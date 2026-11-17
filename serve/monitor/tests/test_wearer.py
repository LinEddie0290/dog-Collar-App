"""Layer 0 wearer verification: enrolment gate, own vs other dog, near-field veto."""
import numpy as np

from monitor import wearer as W


def dogs(seed=0, dim=32, n=60):
    rng = np.random.default_rng(seed)
    a, b = rng.standard_normal(dim) * 2, rng.standard_normal(dim) * 2
    return a + rng.standard_normal((n, dim)), b + rng.standard_normal((n, dim))


def test_not_enrolled_gives_none_then_separates_dogs():
    A, B = dogs()
    v = W.WearerVerifier(W.PopulationStats.fit(np.vstack([A, B])), threshold=0.3)
    assert v.score(A[0]) is None
    v.enrol(A[:5]); assert not v.enrolled
    v.enrol(A[5:20]); assert v.enrolled and v.n_enrolled == 20
    own = np.mean([v.score(x) for x in A[20:]]); other = np.mean([v.score(x) for x in B])
    assert own > 0.9 and other < 0.1


def test_incremental_enrol_equals_batch():
    A, B = dogs(1)
    pop = W.PopulationStats.fit(np.vstack([A, B]))
    v1, v2 = W.WearerVerifier(pop), W.WearerVerifier(pop)
    v1.enrol(A[:20]); v2.enrol(A[:7]); v2.enrol(A[7:20])
    assert np.allclose(v1.centroid, v2.centroid)


def test_near_field_and_combine():
    nf = W.NearFieldCheck(min_peak_dbfs=-30, min_margin_db=15)
    assert nf(-10, -40) is True and nf(-10, -20) is False and nf(-40, -70) is False and nf(None, -40) is None
    assert W.combine(0.9, False) == 0.0
    assert W.combine(None, None) is None and W.combine(None, True) == 1.0 and W.combine(0.2, True) == 0.2


def test_lda_projection_matches_sklearn_transform():
    from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
    rng = np.random.default_rng(3)
    E = np.vstack([rng.standard_normal(16) * 2 + rng.standard_normal((30, 16)) for _ in range(6)]); y = np.repeat(np.arange(6), 30)
    pop = W.PopulationStats.fit(E, dog_ids=y)
    Z = (E - pop.mean) / np.sqrt(pop.var + 1e-12)
    ref = LinearDiscriminantAnalysis(solver="eigen", shrinkage="auto", n_components=5).fit(Z, y).transform(Z)
    ref /= np.linalg.norm(ref, axis=1, keepdims=True)
    assert np.allclose(np.abs(np.sum(pop.whiten(E) * ref, axis=1)), 1, atol=1e-6)
