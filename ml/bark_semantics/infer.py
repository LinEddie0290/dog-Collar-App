"""
L3 — rule-based intent inference. The rule table lives in config
(`semantics.intent_rules`), not in branching code here; this module only
evaluates it.

Safety degradation (the important part): with all L2 slots absent, every rule
but `discomfort_pain` requires a slot, so the only branch that could still fire
is the one with medical consequences. `semantics.degradation.suppress_when_missing`
suppresses `discomfort_pain` when `env_events` is missing, so degraded mode
returns UNKNOWN rather than the riskiest sentence. `discomfort_pain` is also
capped (max_confidence) and its downstream phrasing must always be "worth
observing / consider a vet", never a statement of fact (L4's job).

`observation` is ALWAYS populated from L1 — it is the measured half of the UI and
never depends on inference succeeding. Every evidence string cites a concrete
measured value with its percentile.
"""
from __future__ import annotations

import numpy as np

from schema import AffectEstimate, BurstFeatures, ContextSnapshot, Hypothesis, Inference, Intent


def _evidence(ckey: str, v: float, burst: BurstFeatures) -> str:
    pct = f"{int(round(v * 100))}th pct"
    if ckey == "arousal":
        return f"arousal={v:.2f} (percentile for this dog)"
    if ckey == "valence":
        return f"valence={v:.2f} (percentile for this dog)"
    if ckey == "ibi_percentile":
        ibi = f"{burst.ibi_mean:.2f}s" if burst.ibi_mean is not None else "n/a"
        return f"ibi_mean={ibi} ({pct} for this dog)"
    if ckey == "f0_percentile":
        return f"f0 {pct} for this dog"
    if ckey == "hnr_percentile":
        return f"hnr {pct} for this dog"
    if ckey == "tonality":
        return f"tonality={v:.2f}"
    return f"{ckey}={v:.2f}"


def _build_observation(burst: BurstFeatures, affect: AffectEstimate,
                       snapshot: ContextSnapshot) -> str:
    """Measured-only sentence. Non-empty in every path (burst always has
    n_barks/duration), independent of any hypothesis."""
    parts = [f"{burst.n_barks}-bark burst over {burst.duration:.1f}s"]
    if burst.ibi_mean is not None:
        parts.append(f"mean IBI {burst.ibi_mean:.2f}s")
    if affect.arousal is not None:
        parts.append(f"arousal {affect.arousal:.2f}")
    if affect.valence is not None:
        parts.append(f"valence {affect.valence:.2f}")
    elif affect.learning_period:
        parts.append("baseline still learning")
    env = snapshot.env_events.value
    if env:
        parts.append("env " + ", ".join(f"{e['category']}@{e['t_offset']}s" for e in env[:2]))
    return "; ".join(parts) + "."


def infer(affect: AffectEstimate, burst: BurstFeatures,
          snapshot: ContextSnapshot, cfg: dict) -> Inference:
    sem = cfg["semantics"]
    rules = sem["intent_rules"]
    suppress = sem["degradation"]["suppress_when_missing"]
    missing = set(snapshot.missing())

    env_val = snapshot.env_events.value
    env_available = env_val is not None
    present_cats = {e["category"] for e in env_val} if env_available else set()
    tonality = float(np.mean([b.tonality for b in burst.barks])) if burst.barks else 0.0
    comp = affect.components

    scalar = {
        "arousal": affect.arousal,
        "valence": affect.valence,
        "ibi_percentile": comp.get("ibi_pct"),
        "f0_percentile": comp.get("f0_pct"),
        "hnr_percentile": comp.get("hnr_pct"),
        "tonality": tonality,
    }

    hypotheses: list[Hypothesis] = []
    for rule in rules:
        intent = rule["intent"]

        # 1) safety suppression — independent of conditions (see module docstring)
        if intent in suppress and any(s in missing for s in suppress[intent]):
            continue
        # 2) required slots must be available
        if any(s in missing for s in rule.get("required_slots", [])):
            continue

        ok = True
        evidence: list[str] = []
        uses_valence = False
        for ckey, spec in rule.get("conditions", {}).items():
            if ckey == "env_events_any":
                hits = [e for e in env_val if e["category"] in spec] if env_available else []
                if not hits:
                    ok = False
                    break
                evidence.append("env_event=" + ", ".join(
                    f"{e['category']} @ {e['t_offset']}s (score {e['score']})" for e in hits[:2]))
            elif ckey == "env_events_none":
                if not env_available or (present_cats & set(spec)):
                    ok = False
                    break
                evidence.append(f"none of {spec} present")
            elif ckey == "burst_repetition_min":
                if burst.n_barks < spec:
                    ok = False
                    break
                evidence.append(f"n_barks={burst.n_barks} (>= {spec})")
            else:
                v = scalar.get(ckey)
                if v is None:
                    ok = False
                    break
                if "min" in spec and v < spec["min"]:
                    ok = False
                    break
                if "max" in spec and v > spec["max"]:
                    ok = False
                    break
                if ckey == "valence":
                    uses_valence = True
                evidence.append(_evidence(ckey, v, burst))
        if not ok:
            continue

        # confidence: rule prior x baseline certainty, optional-slot penalty,
        # valence cap (weak signal can't inherit strong certainty), max cap.
        conf = rule["base_confidence"] * affect.confidence
        for opt in rule.get("optional_slots", []):
            if opt in missing:
                conf *= rule.get("missing_optional_penalty", 1.0)
        if uses_valence and "valence_confidence" in comp:
            conf = min(conf, comp["valence_confidence"])
        if "max_confidence" in rule:
            conf = min(conf, rule["max_confidence"])
        hypotheses.append(Hypothesis(Intent(intent), round(conf, 3), evidence))

    hypotheses.sort(key=lambda h: -h.confidence)
    if not hypotheses:
        hypotheses = [Hypothesis(Intent.UNKNOWN, 0.0,
                                 ["no rule matched with the available slots"])]

    return Inference(hypotheses=hypotheses, degraded_slots=sorted(missing),
                     observation=_build_observation(burst, affect, snapshot))
