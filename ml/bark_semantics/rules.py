"""
Event-rules layer (Step 5). Pure rules on top of the event stream.

Fully decoupled from YAMNet / detection: it consumes a list of event dicts
(as produced by aggregate.frames_to_events / detect.py) and the `rules` section
of config.yaml, and returns triggered rules. Swap the detector freely — this
module never imports it.

Windows are anchored at event start times, which is sufficient to find the
worst-case window for counts and (overlap-clamped) durations.
"""
from __future__ import annotations

from datetime import datetime, timedelta


def _overlap(a0: float, a1: float, b0: float, b1: float) -> float:
    return max(0.0, min(a1, b1) - max(a0, b0))


def _by_type(events, t):
    return [e for e in events if e.get("type") == t]


def sustained_howl(events, r) -> list[dict]:
    """Howl seconds > min_total_s within any window_s sliding window."""
    howls = _by_type(events, "howl")
    W, X = r["window_s"], r["min_total_s"]
    best, best_win = 0.0, None
    for anchor in howls:
        t0 = anchor["start_s"]
        t1 = t0 + W
        total = sum(_overlap(h["start_s"], h["end_s"], t0, t1) for h in howls)
        if total > best:
            best, best_win = total, (t0, t1)
    if best > X:
        return [{
            "rule": "sustained_howl",
            "window": [round(best_win[0], 2), round(best_win[1], 2)],
            "total_howl_s": round(best, 2),
            "threshold_s": X,
        }]
    return []


def sustained_whine(events, r) -> list[dict]:
    """Whimper occupying > min_fraction of any window_s window."""
    whines = _by_type(events, "whimper")
    W, frac = r["window_s"], r["min_fraction"]
    best, best_win = 0.0, None
    for anchor in whines:
        t0 = anchor["start_s"]
        t1 = t0 + W
        total = sum(_overlap(w["start_s"], w["end_s"], t0, t1) for w in whines)
        if total > best:
            best, best_win = total, (t0, t1)
    if best / W > frac:
        return [{
            "rule": "sustained_whine",
            "window": [round(best_win[0], 2), round(best_win[1], 2)],
            "whine_fraction": round(best / W, 3),
            "threshold_fraction": frac,
        }]
    return []


def dense_barking(events, r) -> list[dict]:
    """Bark event count > min_events_per_min in any 60 s window."""
    barks = _by_type(events, "bark")
    N = r["min_events_per_min"]
    best, best_win = 0, None
    for anchor in barks:
        t0 = anchor["start_s"]
        t1 = t0 + 60.0
        cnt = sum(1 for b in barks if t0 <= b["start_s"] < t1)
        if cnt > best:
            best, best_win = cnt, (t0, t1)
    if best > N:
        return [{
            "rule": "dense_barking",
            "window": [round(best_win[0], 2), round(best_win[1], 2)],
            "bark_count": best,
            "threshold_per_min": N,
        }]
    return []


def night_vocalization(events, r, recording_start: datetime | None) -> list[dict]:
    """Any event whose local wall-clock hour is within [start_hour, end_hour).

    Needs recording_start (wall clock of t=0) to map event start_s -> hour.
    If not provided, the rule cannot be evaluated and is skipped (reported).
    """
    start_h, end_h = r["start_hour"], r["end_hour"]

    def is_night(h: int) -> bool:
        return (h >= start_h or h < end_h) if start_h > end_h else (start_h <= h < end_h)

    if recording_start is None:
        return [{"rule": "night_vocalization", "skipped": True,
                 "reason": "no recording_start wall-clock provided"}]
    hits = []
    for e in events:
        h = (recording_start + timedelta(seconds=e["start_s"])).hour
        if is_night(h):
            hits.append({"start_s": e["start_s"], "type": e["type"], "hour": h})
    if hits:
        return [{"rule": "night_vocalization",
                 "night_window": [start_h, end_h], "events": hits}]
    return []


def evaluate(events, cfg, recording_start: datetime | None = None) -> list[dict]:
    """Run all rules; return the list of triggered rule dicts."""
    r = cfg["rules"]
    out = []
    out += sustained_howl(events, r["sustained_howl"])
    out += sustained_whine(events, r["sustained_whine"])
    out += dense_barking(events, r["dense_barking"])
    out += night_vocalization(events, r["night_vocalization"], recording_start)
    return out


if __name__ == "__main__":
    import argparse
    import json

    import yaml

    ap = argparse.ArgumentParser(description="Apply event rules to an event JSON list.")
    ap.add_argument("events_json", help="file with a JSON list of events")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--recording-start", default=None,
                    help="ISO datetime of t=0 (for night rule), e.g. 2026-09-10T23:30:00")
    args = ap.parse_args()

    cfg = yaml.safe_load(open(args.config))
    events = json.load(open(args.events_json))
    rs = datetime.fromisoformat(args.recording_start) if args.recording_start else None
    print(json.dumps(evaluate(events, cfg, rs), indent=2, ensure_ascii=False))
