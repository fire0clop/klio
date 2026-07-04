"""Фабрики доменных объектов.

`make_goal`/`make_entry` создают ORM-объекты в памяти (для юнит-тестов чистой
логики Python-дефолты колонок надо задавать явно — они применяются только при
INSERT). `create_goal` кладёт цель в БД для интеграционных тестов.
"""
import uuid
from datetime import date, timedelta
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.models import Goal, GoalEntry


def make_goal(**overrides) -> Goal:
    defaults = dict(
        id=uuid.uuid4(),
        title="Тестовая цель",
        frequency_type="daily",
        frequency_value=None,
        goal_type="binary",
        horizon="eternal",
        measure="fact",
        direction=None,
        controllability=None,
        baseline=None,
        target=None,
        unit=None,
        growing=False,
        metric_has_ceiling=False,
        horizon_days=None,
        ai_context=None,
        ai_effect_trajectory=None,
        daily_plan=None,
        dialog_complete=True,
        started_at=date.today(),
        is_active=True,
    )
    defaults.update(overrides)
    return Goal(**defaults)


def make_entry(d: date, completed: bool = True,
               value: Optional[float] = None, goal_id=None) -> GoalEntry:
    return GoalEntry(
        id=uuid.uuid4(),
        goal_id=goal_id or uuid.uuid4(),
        date=d,
        completed=completed,
        confirmed=False,
        actual_value=value,
    )


def entries_days_ago(days: list[int], completed: bool = True,
                     value: Optional[float] = None) -> list[GoalEntry]:
    """Записи за N дней назад от сегодня (0 = сегодня)."""
    today = date.today()
    return [make_entry(today - timedelta(days=n), completed, value) for n in days]


async def create_goal(db: AsyncSession, user_id, **overrides) -> Goal:
    values = dict(
        user_id=user_id,
        title="Тестовая цель",
        started_at=date.today(),
        frequency_type="daily",
        dialog_complete=True,
    )
    values.update(overrides)
    goal = Goal(**values)
    db.add(goal)
    await db.commit()
    await db.refresh(goal)
    return goal
