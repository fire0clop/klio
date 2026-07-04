"""Юнит-тесты стриков, completion rate и процента эффекта."""
from datetime import date, timedelta

from app.services.streak_service import (
    calculate_completion_rate,
    calculate_effect_percent,
    calculate_streak,
)
from tests.factories import entries_days_ago, make_goal

TODAY = date.today()


class TestDailyStreak:
    def test_perfect_run(self):
        goal = make_goal(started_at=TODAY - timedelta(days=2))
        entries = entries_days_ago([2, 1, 0])
        data = calculate_streak(goal, entries)
        assert data == {"current_streak": 3, "best_streak": 3, "total_completed": 3}

    def test_gap_resets_current_but_keeps_best(self):
        goal = make_goal(started_at=TODAY - timedelta(days=5))
        # дни -5..-3 выполнены, -2 пропуск, -1 и 0 выполнены
        entries = entries_days_ago([5, 4, 3, 1, 0]) + entries_days_ago([2], completed=False)
        data = calculate_streak(goal, entries)
        assert data["current_streak"] == 2
        assert data["best_streak"] == 3
        assert data["total_completed"] == 5

    def test_no_entries(self):
        goal = make_goal(started_at=TODAY - timedelta(days=3))
        data = calculate_streak(goal, [])
        assert data == {"current_streak": 0, "best_streak": 0, "total_completed": 0}

    def test_today_not_yet_logged_zeroes_current_streak(self):
        """Документирует текущее поведение: пока сегодняшний день не отмечен,
        current_streak = 0, даже если вчера и позавчера выполнены.

        Спорное UX-решение (пользователь каждое утро видит «стрик 0»), но
        так работает calculate_streak сейчас — тест фиксирует это как контракт.
        """
        goal = make_goal(started_at=TODAY - timedelta(days=2))
        entries = entries_days_ago([2, 1])  # сегодня записи нет
        data = calculate_streak(goal, entries)
        assert data["current_streak"] == 0
        assert data["best_streak"] == 2

    def test_weekdays_goal_counts_only_planned_days(self):
        # Цель по будням Пн и Ср; выполнения именно в эти дни
        monday = TODAY - timedelta(days=(TODAY.weekday() - 0) % 7 + 14)
        goal = make_goal(
            frequency_type="weekdays",
            frequency_value={"days": [0, 2]},
            started_at=monday,
        )
        planned = [d for d in (monday + timedelta(days=i) for i in range(0, 15))
                   if d.weekday() in (0, 2) and d <= TODAY]
        entries = [e for e in ({"d": d} for d in planned)]
        from tests.factories import make_entry
        entries = [make_entry(d) for d in planned]
        data = calculate_streak(goal, entries)
        assert data["total_completed"] == len(planned)
        # Пропусков нет — best == всем плановым дням до сегодня
        assert data["best_streak"] == len([d for d in planned if d <= TODAY])


class TestTimesPerWeekStreak:
    def test_two_full_weeks(self):
        started = TODAY - timedelta(days=13)  # ровно две недели: дни 0-6 и 7-13
        goal = make_goal(
            frequency_type="times_per_week",
            frequency_value={"times": 2},
            started_at=started,
        )
        entries = [
            *entries_days_ago([13, 11]),  # первая неделя: 2 выполнения
            *entries_days_ago([5, 3]),    # вторая неделя: 2 выполнения
        ]
        data = calculate_streak(goal, entries)
        assert data["current_streak"] == 2
        assert data["best_streak"] == 2
        assert data["total_completed"] == 4

    def test_failed_week_resets(self):
        started = TODAY - timedelta(days=20)  # три недели
        goal = make_goal(
            frequency_type="times_per_week",
            frequency_value={"times": 2},
            started_at=started,
        )
        entries = [
            *entries_days_ago([20, 19]),  # неделя 1: норма
            *entries_days_ago([12]),      # неделя 2: только 1 из 2 — срыв
            *entries_days_ago([5, 4]),    # неделя 3: норма
        ]
        data = calculate_streak(goal, entries)
        assert data["current_streak"] == 1
        assert data["best_streak"] == 1
        assert data["total_completed"] == 5


class TestCompletionRate:
    def test_half_completed(self):
        goal = make_goal(started_at=TODAY - timedelta(days=9))
        entries = entries_days_ago([0, 2, 4, 6, 8])  # 5 из 10 плановых
        assert calculate_completion_rate(goal, entries, 10) == 0.5

    def test_window_shorter_than_goal_age(self):
        goal = make_goal(started_at=TODAY - timedelta(days=100))
        entries = entries_days_ago([0, 1, 2, 3, 4, 5, 6])
        assert calculate_completion_rate(goal, entries, 7) == 1.0

    def test_goal_started_today(self):
        goal = make_goal(started_at=TODAY)
        assert calculate_completion_rate(goal, entries_days_ago([0]), 30) == 1.0

    def test_no_planned_days_returns_zero(self):
        goal = make_goal(started_at=TODAY + timedelta(days=5))  # ещё не началась
        assert calculate_completion_rate(goal, [], 30) == 0.0


class TestEffectPercent:
    def _goal_with_trajectory(self, streak_days: int, milestones):
        goal = make_goal(
            started_at=TODAY - timedelta(days=max(streak_days - 1, 0)),
            ai_effect_trajectory={"effects": [{"name": "e", "milestones": milestones}]},
        )
        entries = entries_days_ago(list(range(streak_days)))
        return goal, entries

    def test_without_trajectory_uses_streak(self):
        goal = make_goal(started_at=TODAY - timedelta(days=4))
        entries = entries_days_ago([4, 3, 2, 1, 0])
        assert calculate_effect_percent(goal, entries) == 5

    def test_zero_streak(self):
        goal, _ = self._goal_with_trajectory(0, [{"day": 7, "percent": 30}])
        assert calculate_effect_percent(goal, []) == 0

    def test_exact_milestone(self):
        goal, entries = self._goal_with_trajectory(7, [{"day": 7, "percent": 30}])
        assert calculate_effect_percent(goal, entries) == 30

    def test_interpolation_between_milestones(self):
        milestones = [{"day": 10, "percent": 30}, {"day": 30, "percent": 100}]
        goal, entries = self._goal_with_trajectory(20, milestones)
        # 30 + (20-10)/(30-10) * 70 = 65
        assert calculate_effect_percent(goal, entries) == 65

    def test_beyond_last_milestone_caps(self):
        goal, entries = self._goal_with_trajectory(50, [{"day": 7, "percent": 40}])
        assert calculate_effect_percent(goal, entries) == 40

    def test_empty_milestones_falls_back_to_streak(self):
        goal = make_goal(
            started_at=TODAY - timedelta(days=2),
            ai_effect_trajectory={"effects": [{"name": "e", "milestones": []}]},
        )
        entries = entries_days_ago([2, 1, 0])
        assert calculate_effect_percent(goal, entries) == 3
