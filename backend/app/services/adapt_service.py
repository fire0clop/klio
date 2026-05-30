"""Адаптация цели по отклонению (docs/GOAL_DESIGN.md §4).

Для вечных растущих количественных целей: если человек стабильно перевыполняет,
предлагаем поднять планку — не на фиксированный шаг, а на долю от разрыва между
устойчивым показанным уровнем и текущей целью. У метрик со смысловым пределом —
предлагаем сменить метрику, а не наращивать число. Всё — opt-in (предложение).
"""
from datetime import date
from statistics import median
from typing import List, Optional

from app.models.models import Goal, GoalEntry

_K = 0.5            # доля разрыва, на которую двигаем цель
_WINDOW = 14        # дней истории
_MIN_DAYS = 5       # минимум залогированных дней
_OVER_MARGIN = 1.12 # устойчивый уровень должен превышать цель хотя бы на 12%


def _fmt(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else f"{v:.1f}"


def compute_suggestion(goal: Goal, entries: List[GoalEntry]) -> Optional[dict]:
    if goal.measure != "quantitative" or goal.direction != "up" or not goal.growing:
        return None
    if goal.horizon != "eternal":        # ситуативные идут к заявленной точке
        return None
    target = goal.target
    if target is None or target <= 0:
        return None

    today = date.today()
    recent = [
        e.actual_value for e in entries
        if e.actual_value is not None and 0 <= (today - e.date).days < _WINDOW
    ]
    if len(recent) < _MIN_DAYS:
        return None

    level = median(recent)                       # устойчивый уровень, не пик
    over_days = sum(1 for v in recent if v >= target)
    if level < target * _OVER_MARGIN or over_days < max(4, int(len(recent) * 0.6)):
        return None

    ctx = goal.ai_context or {}

    # Метрика со смысловым пределом, уже сильно выросшая — предложить смену метрики
    if goal.metric_has_ceiling and goal.baseline and target >= goal.baseline * 3:
        if ctx.get("adapt_switch_dismissed_day") is not None:
            dismissed = ctx["adapt_switch_dismissed_day"]
            if isinstance(dismissed, str):
                try:
                    if (today - date.fromisoformat(dismissed)).days < 30:
                        return None
                except ValueError:
                    pass
        return {
            "kind": "switch_metric",
            "suggested_target": None,
            "unit": goal.unit,
            "message": (
                f"Ты стабильно делаешь ~{_fmt(level)} {goal.unit or ''}. Это уже много — "
                f"возможно, осмысленнее менять метрику (вес, время, сложность), а не наращивать число."
            ),
        }

    new_target = target + _K * (level - target)
    new_target = round(new_target) if float(target).is_integer() else round(new_target, 1)
    if new_target <= target:
        return None

    declined = ctx.get("adapt_declined_target")
    if declined is not None and new_target <= float(declined) + 1e-6:
        return None

    return {
        "kind": "raise",
        "suggested_target": float(new_target),
        "unit": goal.unit,
        "message": (
            f"Ты стабильно перевыполняешь: ~{_fmt(level)} {goal.unit or ''} при цели "
            f"{_fmt(target)}. Поднять цель до {_fmt(new_target)}?"
        ),
    }
