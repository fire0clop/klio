"""Юнит-тесты расписания целей (goal_schedule)."""
from datetime import date, timedelta

from app.services.goal_schedule import get_planned_days, is_planned_day
from tests.factories import make_goal

START = date(2026, 6, 1)


def _monday_after(d: date) -> date:
    return d + timedelta(days=(0 - d.weekday()) % 7)


class TestIsPlannedDay:
    def test_daily_every_day_is_planned(self):
        goal = make_goal(frequency_type="daily", started_at=START)
        assert is_planned_day(goal, START)
        assert is_planned_day(goal, START + timedelta(days=1))
        assert is_planned_day(goal, START + timedelta(days=365))

    def test_before_start_date_never_planned(self):
        goal = make_goal(frequency_type="daily", started_at=START)
        assert not is_planned_day(goal, START - timedelta(days=1))

    def test_every_n_days_cycle(self):
        goal = make_goal(
            frequency_type="every_n_days",
            frequency_value={"n": 3},
            started_at=START,
        )
        assert is_planned_day(goal, START)
        assert not is_planned_day(goal, START + timedelta(days=1))
        assert not is_planned_day(goal, START + timedelta(days=2))
        assert is_planned_day(goal, START + timedelta(days=3))
        assert is_planned_day(goal, START + timedelta(days=6))

    def test_every_n_days_defaults_to_every_day(self):
        goal = make_goal(frequency_type="every_n_days", frequency_value={}, started_at=START)
        assert is_planned_day(goal, START + timedelta(days=1))

    def test_weekdays_only_selected_days(self):
        monday = _monday_after(START)
        goal = make_goal(
            frequency_type="weekdays",
            frequency_value={"days": [0, 2]},  # Пн, Ср
            started_at=monday,
        )
        assert is_planned_day(goal, monday)                        # Пн
        assert not is_planned_day(goal, monday + timedelta(days=1))  # Вт
        assert is_planned_day(goal, monday + timedelta(days=2))      # Ср
        assert not is_planned_day(goal, monday + timedelta(days=6))  # Вс

    def test_weekdays_empty_list_means_never(self):
        goal = make_goal(frequency_type="weekdays", frequency_value={"days": []}, started_at=START)
        assert not is_planned_day(goal, START + timedelta(days=1))

    def test_times_per_week_shows_every_day(self):
        goal = make_goal(
            frequency_type="times_per_week",
            frequency_value={"times": 3},
            started_at=START,
        )
        assert is_planned_day(goal, START + timedelta(days=5))

    def test_unknown_frequency_falls_back_to_daily(self):
        goal = make_goal(frequency_type="lunar_cycle", started_at=START)
        assert is_planned_day(goal, START + timedelta(days=1))


class TestGetPlannedDays:
    def test_daily_range_inclusive(self):
        goal = make_goal(frequency_type="daily", started_at=START)
        days = get_planned_days(goal, START, START + timedelta(days=4))
        assert len(days) == 5
        assert days[0] == START and days[-1] == START + timedelta(days=4)

    def test_weekdays_subset(self):
        monday = _monday_after(START)
        goal = make_goal(
            frequency_type="weekdays",
            frequency_value={"days": [0]},  # только Пн
            started_at=monday,
        )
        days = get_planned_days(goal, monday, monday + timedelta(days=13))
        assert days == [monday, monday + timedelta(days=7)]

    def test_empty_when_end_before_start(self):
        goal = make_goal(frequency_type="daily", started_at=START)
        assert get_planned_days(goal, START, START - timedelta(days=1)) == []
