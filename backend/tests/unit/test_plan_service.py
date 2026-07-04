"""Юнит-тесты дневного плана (рампа baseline → target и legacy-лесенка)."""
from datetime import date, timedelta

from app.services.plan_service import get_today_plan
from tests.factories import make_goal

TODAY = date.today()


class TestQuantitativeRamp:
    def _goal(self, **kw):
        base = dict(
            measure="quantitative",
            goal_type="quantitative",
            direction="down",
            baseline=20.0,
            target=10.0,
            horizon_days=11,
            unit="сиг",
        )
        base.update(kw)
        return make_goal(**base)

    def test_day_one_starts_at_baseline(self):
        goal = self._goal(started_at=TODAY)
        plan = get_today_plan(goal, TODAY)
        assert plan.day_number == 1
        assert plan.limit == 20.0
        assert plan.unit == "сиг"

    def test_midpoint_interpolates(self):
        goal = self._goal(started_at=TODAY - timedelta(days=5))  # день 6 из 11
        plan = get_today_plan(goal, TODAY)
        assert plan.limit == 15.0

    def test_end_of_ramp_reaches_target(self):
        goal = self._goal(started_at=TODAY - timedelta(days=10))  # день 11
        assert get_today_plan(goal, TODAY).limit == 10.0

    def test_after_horizon_holds_target(self):
        goal = self._goal(started_at=TODAY - timedelta(days=40))
        assert get_today_plan(goal, TODAY).limit == 10.0

    def test_integer_baseline_and_target_round_to_int(self):
        goal = self._goal(baseline=20.0, target=10.0,
                          started_at=TODAY - timedelta(days=2), horizon_days=11)
        # день 3: 20 + (10-20)*2/10 = 18.0 — целое
        assert get_today_plan(goal, TODAY).limit == 18.0

    def test_fractional_values_round_to_one_decimal(self):
        goal = self._goal(baseline=2.5, target=5.0, horizon_days=10,
                          started_at=TODAY - timedelta(days=4))  # день 5
        # 2.5 + (5-2.5)*4/9 ≈ 3.611 → 3.6
        assert get_today_plan(goal, TODAY).limit == 3.6

    def test_no_baseline_means_flat_target(self):
        goal = self._goal(baseline=None, started_at=TODAY)
        assert get_today_plan(goal, TODAY).limit == 10.0

    def test_baseline_equals_target_flat(self):
        goal = self._goal(baseline=10.0, target=10.0, started_at=TODAY)
        assert get_today_plan(goal, TODAY).limit == 10.0


class TestNonQuantitative:
    def test_fact_goal_has_no_plan(self):
        goal = make_goal(measure="fact", goal_type="binary", started_at=TODAY)
        assert get_today_plan(goal, TODAY) is None


class TestLegacyDailyPlan:
    def _legacy_goal(self, days_ago: int):
        return make_goal(
            measure="fact",  # новая ветка не срабатывает
            goal_type="quantitative",
            started_at=TODAY - timedelta(days=days_ago),
            daily_plan=[
                {"day_start": 1, "day_end": 7, "limit": 15, "unit": "шт"},
                {"day_start": 8, "day_end": None, "limit": 10, "unit": "шт"},
            ],
        )

    def test_first_step(self):
        plan = get_today_plan(self._legacy_goal(days_ago=0), TODAY)
        assert plan.day_number == 1
        assert plan.limit == 15

    def test_open_ended_step(self):
        plan = get_today_plan(self._legacy_goal(days_ago=20), TODAY)
        assert plan.day_number == 21
        assert plan.limit == 10
