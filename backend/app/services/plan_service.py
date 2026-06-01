from datetime import date
from typing import Optional

from app.models.models import Goal
from app.schemas.checkin import PlanStepInfo


def _ramped_target(goal: Goal, day_number: int) -> float:
    """Дневной лимит/цель на сегодня вдоль траектории baseline → target.

    Если задан baseline и horizon_days > 1 и baseline != target — лимит плавно
    интерполируется от baseline (день 1) к target (день horizon_days), затем держится
    на target. Иначе сразу target.
    """
    target = goal.target
    baseline = goal.baseline
    horizon = goal.horizon_days or 0

    if baseline is None or horizon <= 1 or baseline == target:
        return target

    # day_number начинается с 1; доля прогресса по рампе 0..1
    frac = (day_number - 1) / (horizon - 1)
    frac = max(0.0, min(1.0, frac))
    value = baseline + (target - baseline) * frac

    # Округление: целые единицы — к целому, иначе к 1 знаку
    if float(baseline).is_integer() and float(target).is_integer():
        return float(round(value))
    return round(value, 1)


def get_today_plan(goal: Goal, today: date) -> Optional[PlanStepInfo]:
    day_number = (today - goal.started_at).days + 1

    # Новая модель: дневная цель/лимит считается от факта (траектория baseline → target).
    if getattr(goal, "measure", None) == "quantitative" and goal.target is not None:
        limit = _ramped_target(goal, day_number)
        return PlanStepInfo(day_number=day_number, limit=limit, unit=goal.unit)

    # Legacy: старая зашитая лесенка daily_plan.
    if goal.goal_type != "quantitative" or not goal.daily_plan:
        return None

    for step in goal.daily_plan:
        start = step.get("day_start", 1)
        end = step.get("day_end")  # None = до конца
        if day_number >= start and (end is None or day_number <= end):
            return PlanStepInfo(
                day_number=day_number,
                limit=step.get("limit"),
                unit=step.get("unit"),
            )

    return PlanStepInfo(day_number=day_number, limit=None, unit=None)
