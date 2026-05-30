from datetime import date, timedelta
from typing import List

from app.models.models import Goal


def is_planned_day(goal: Goal, check_date: date) -> bool:
    ft = goal.frequency_type
    fv = goal.frequency_value or {}
    started = goal.started_at

    if check_date < started:
        return False

    if ft == "daily":
        return True

    if ft == "every_n_days":
        n = fv.get("n", 1)
        delta = (check_date - started).days
        return delta % n == 0

    if ft == "weekdays":
        allowed = fv.get("days", [])  # 0=Mon .. 6=Sun
        return check_date.weekday() in allowed

    if ft == "times_per_week":
        # Показываем каждый день — логику выполнения считает streak_service
        return True

    return True


def get_planned_days(goal: Goal, start: date, end: date) -> List[date]:
    result = []
    current = start
    while current <= end:
        if is_planned_day(goal, current):
            result.append(current)
        current += timedelta(days=1)
    return result
