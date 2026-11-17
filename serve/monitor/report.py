"""Owner-facing sentences: fixed templates, observations and trends only.

Never a diagnosis or an emotional label - only what was counted, when, and how it
compares with this dog's own usual level. FORBIDDEN lists words the templates
must never produce (checked by the tests).
"""
from __future__ import annotations

from .aggregate import by_hour_block

BLOCK_ZH = {"night": "夜里", "morning": "上午", "afternoon": "下午", "evening": "晚上"}
FORBIDDEN = ("焦虑", "抑郁", "生病", "疾病", "疼痛", "诊断", "异常行为", "情绪", "开心", "难过", "害怕", "分离焦虑")


def _when(day):
    blocks = {k: v for k, v in by_hour_block(day).items() if v}
    if not blocks or day.n_bouts == 0:
        return ""
    top, n = max(blocks.items(), key=lambda kv: kv[1])
    if n == day.n_bouts:
        return f"，都在{BLOCK_ZH[top]}"
    if n >= 2 * day.n_bouts / 3:
        return f"，大多在{BLOCK_ZH[top]}"
    return ""


def daily_sentence(day, status: dict, dog_name: str = "它") -> str:
    s = status.get("n_bouts", {})
    st = s.get("status")
    if day.missing or st == "missing":
        return "今天项圈记录不完整，不做比较。"
    if st in ("no_history", "learning"):
        n_days = s.get("n_days", 1)
        return f"还在熟悉{dog_name}平时的样子（已记录 {n_days} 天），这段时间只记录、不比较。今天叫了 {day.n_bouts} 串{_when(day)}。"
    if day.n_bouts == 0:
        base = "今天很安静，没有记录到叫声。"
    else:
        base = f"今天叫了 {day.n_bouts} 串{_when(day)}。"
    alarm = s.get("alarm")
    if alarm == "up":
        return base + f"比平时（一般约 {s['frozen'].median:.0f} 串）明显多，最近几天在持续增加。"
    if alarm == "down":
        return base + f"比平时（一般约 {s['frozen'].median:.0f} 串）明显少，最近几天在持续减少。"
    return "今天正常，" + base[2:] if day.n_bouts else base


def alone_trend_sentence(rolling_stat, frozen_stat, alarm) -> str | None:
    """'After you leave, barking went up about N-fold over two weeks' - only with an alarm."""
    if alarm != "up" or rolling_stat is None or frozen_stat is None or frozen_stat.median <= 0:
        return None
    ratio = rolling_stat.median / frozen_stat.median
    if ratio < 1.5:
        return None
    return f"离家后的叫声两周内约涨了 {ratio:.0f} 倍。" if ratio >= 2 else f"离家后的叫声两周内约多了 {100 * (ratio - 1):.0f}%。"
