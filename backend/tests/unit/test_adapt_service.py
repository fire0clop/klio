"""Юнит-тесты адаптации цели (предложение поднять планку / сменить метрику)."""
from datetime import date, timedelta

from app.services.adapt_service import compute_suggestion
from tests.factories import entries_days_ago, make_goal

TODAY = date.today()


def _growing_goal(**kw):
    base = dict(
        measure="quantitative",
        direction="up",
        growing=True,
        horizon="eternal",
        target=10.0,
        unit="отж",
        started_at=TODAY - timedelta(days=30),
    )
    base.update(kw)
    return make_goal(**base)


def _overperforming_entries(value: float = 12.0, days: int = 6):
    return entries_days_ago(list(range(days)), completed=True, value=value)


class TestEligibility:
    def test_fact_goal_ineligible(self):
        goal = _growing_goal(measure="fact")
        assert compute_suggestion(goal, _overperforming_entries()) is None

    def test_direction_down_ineligible(self):
        goal = _growing_goal(direction="down")
        assert compute_suggestion(goal, _overperforming_entries()) is None

    def test_not_growing_ineligible(self):
        goal = _growing_goal(growing=False)
        assert compute_suggestion(goal, _overperforming_entries()) is None

    def test_situational_ineligible(self):
        goal = _growing_goal(horizon="situational")
        assert compute_suggestion(goal, _overperforming_entries()) is None

    def test_no_target_ineligible(self):
        goal = _growing_goal(target=None)
        assert compute_suggestion(goal, _overperforming_entries()) is None


class TestRaiseSuggestion:
    def test_not_enough_history(self):
        goal = _growing_goal()
        assert compute_suggestion(goal, _overperforming_entries(days=4)) is None

    def test_level_below_margin_no_suggestion(self):
        # медиана 11 < 10*1.12 = 11.2 — недостаточно устойчивое перевыполнение
        goal = _growing_goal()
        assert compute_suggestion(goal, _overperforming_entries(value=11.0)) is None

    def test_stable_overperformance_suggests_half_gap(self):
        goal = _growing_goal(target=10.0)
        sugg = compute_suggestion(goal, _overperforming_entries(value=12.0))
        assert sugg is not None
        assert sugg["kind"] == "raise"
        # 10 + 0.5 * (12 - 10) = 11; цель целочисленная → округление к целому
        assert sugg["suggested_target"] == 11.0
        assert sugg["unit"] == "отж"

    def test_old_entries_outside_window_ignored(self):
        goal = _growing_goal()
        old = entries_days_ago([20, 21, 22, 23, 24], value=15.0)
        assert compute_suggestion(goal, old) is None

    def test_declined_target_suppresses_same_suggestion(self):
        goal = _growing_goal(ai_context={"adapt_declined_target": 11.0})
        assert compute_suggestion(goal, _overperforming_entries(value=12.0)) is None

    def test_higher_level_overrides_declined(self):
        goal = _growing_goal(ai_context={"adapt_declined_target": 11.0})
        sugg = compute_suggestion(goal, _overperforming_entries(value=16.0))
        assert sugg is not None
        assert sugg["suggested_target"] == 13.0  # 10 + 0.5*(16-10)


class TestSwitchMetric:
    def _ceiling_goal(self, **kw):
        return _growing_goal(metric_has_ceiling=True, baseline=5.0, target=20.0, **kw)

    def test_grown_metric_with_ceiling_suggests_switch(self):
        sugg = compute_suggestion(self._ceiling_goal(), _overperforming_entries(value=23.0))
        assert sugg is not None
        assert sugg["kind"] == "switch_metric"
        assert sugg["suggested_target"] is None

    def test_recent_dismissal_suppresses(self):
        dismissed = (TODAY - timedelta(days=5)).isoformat()
        goal = self._ceiling_goal(ai_context={"adapt_switch_dismissed_day": dismissed})
        assert compute_suggestion(goal, _overperforming_entries(value=23.0)) is None

    def test_old_dismissal_resurfaces(self):
        dismissed = (TODAY - timedelta(days=45)).isoformat()
        goal = self._ceiling_goal(ai_context={"adapt_switch_dismissed_day": dismissed})
        sugg = compute_suggestion(goal, _overperforming_entries(value=23.0))
        assert sugg is not None
        assert sugg["kind"] == "switch_metric"
