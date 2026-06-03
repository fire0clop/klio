from datetime import date, timedelta
from typing import Dict, List

from app.models.models import Goal, GoalEntry
from app.services.goal_schedule import get_planned_days, is_planned_day


def _entries_by_date(entries: List[GoalEntry]) -> Dict[date, bool]:
    return {e.date: e.completed for e in entries}


def calculate_streak(goal: Goal, entries: List[GoalEntry]) -> dict:
    today = date.today()
    by_date = _entries_by_date(entries)

    if goal.frequency_type == "times_per_week":
        return _streak_times_per_week(goal, by_date, today)

    planned = get_planned_days(goal, goal.started_at, today)
    planned_set = set(planned)
    total_completed = sum(1 for d in planned_set if by_date.get(d))

    current_streak = 0
    best_streak = 0
    run = 0

    for d in planned:
        if by_date.get(d):
            run += 1
            best_streak = max(best_streak, run)
        else:
            if d < today:
                run = 0

    # current streak: count backwards from today
    for d in reversed(planned):
        if d > today:
            continue
        if by_date.get(d):
            current_streak += 1
        else:
            break

    return {
        "current_streak": current_streak,
        "best_streak": best_streak,
        "total_completed": total_completed,
    }


def _streak_times_per_week(goal: Goal, by_date: Dict[date, bool], today: date) -> dict:
    times = (goal.frequency_value or {}).get("times", 1)
    total_completed = sum(1 for v in by_date.values() if v)

    current_streak = 0
    best_streak = 0

    week_start = goal.started_at
    while week_start <= today:
        week_end = min(week_start + timedelta(days=6), today)
        count = sum(
            1 for d, v in by_date.items()
            if week_start <= d <= week_end and v
        )
        if count >= times:
            current_streak += 1
            best_streak = max(best_streak, current_streak)
        else:
            if week_end < today:
                current_streak = 0
        week_start += timedelta(days=7)

    return {
        "current_streak": current_streak,
        "best_streak": best_streak,
        "total_completed": total_completed,
    }


def calculate_completion_rate(goal: Goal, entries: List[GoalEntry], days: int) -> float:
    today = date.today()
    start = today - timedelta(days=days - 1)
    planned = get_planned_days(goal, max(start, goal.started_at), today)
    if not planned:
        return 0.0

    by_date = _entries_by_date(entries)
    completed = sum(1 for d in planned if by_date.get(d))
    return round(completed / len(planned), 2)


def calculate_effect_percent(goal: Goal, entries: List[GoalEntry]) -> int:
    """
    Возвращает текущий общий процент прогресса от 0 до 100
    на основе стрика и траектории эффектов.
    """
    streak_data = calculate_streak(goal, entries)
    streak = streak_data["current_streak"]

    trajectory = goal.ai_effect_trajectory
    if not trajectory:
        return min(streak, 100)

    milestones = []
    for effect in trajectory.get("effects", []):
        milestones.extend(effect.get("milestones", []))

    if not milestones:
        return min(streak, 100)

    milestones_sorted = sorted(milestones, key=lambda m: m["day"])

    prev_day, prev_pct = 0, 0
    for m in milestones_sorted:
        if streak <= m["day"]:
            if m["day"] == prev_day:
                return prev_pct
            progress = (streak - prev_day) / (m["day"] - prev_day)
            return int(prev_pct + progress * (m["percent"] - prev_pct))
        prev_day, prev_pct = m["day"], m["percent"]

    return prev_pct
