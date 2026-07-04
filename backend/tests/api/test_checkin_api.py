"""Интеграционные тесты /checkin: дневные отметки, quantitative-логика, метрики."""
import uuid
from datetime import date, timedelta

from sqlalchemy.future import select

from app.models.models import DailyLog, GoalEntry, GoalMetric, GoalMetricEntry
from tests.factories import create_goal

TODAY = date.today()


class TestGetCheckin:
    async def test_empty_day(self, client, user):
        headers, _ = user
        resp = await client.get("/api/v1/checkin/today", headers=headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["goals"] == []
        assert body["all_done"] is False

    async def test_shows_active_goal_unchecked(self, client, user, db_session):
        headers, user_id = user
        await create_goal(db_session, uuid.UUID(user_id), title="Читать")
        body = (await client.get("/api/v1/checkin/today", headers=headers)).json()
        assert len(body["goals"]) == 1
        item = body["goals"][0]
        assert item["title"] == "Читать"
        assert item["completed_today"] is None
        assert item["current_streak"] == 0

    async def test_future_date_rejected(self, client, user):
        headers, _ = user
        tomorrow = (TODAY + timedelta(days=1)).isoformat()
        resp = await client.get(f"/api/v1/checkin/{tomorrow}", headers=headers)
        assert resp.status_code == 400

    async def test_past_date_ok(self, client, user):
        headers, _ = user
        yesterday = (TODAY - timedelta(days=1)).isoformat()
        resp = await client.get(f"/api/v1/checkin/{yesterday}", headers=headers)
        assert resp.status_code == 200

    async def test_weekday_goal_hidden_on_offday(self, client, user, db_session):
        headers, user_id = user
        off_day = (TODAY.weekday() + 1) % 7
        await create_goal(
            db_session, uuid.UUID(user_id),
            frequency_type="weekdays", frequency_value={"days": [off_day]},
            started_at=TODAY - timedelta(days=7),
        )
        body = (await client.get("/api/v1/checkin/today", headers=headers)).json()
        assert body["goals"] == []


class TestSaveBinary:
    async def test_save_creates_entry_and_streak(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id))
        resp = await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(goal.id), "completed": True, "note": "готово"}],
        })
        assert resp.status_code == 200

        body = (await client.get("/api/v1/checkin/today", headers=headers)).json()
        item = body["goals"][0]
        assert item["completed_today"] is True
        assert item["current_streak"] == 1
        assert item["note"] == "готово"
        assert body["all_done"] is True

    async def test_upsert_updates_same_row(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id))
        for completed in (True, False):
            await client.post("/api/v1/checkin", headers=headers, json={
                "date": TODAY.isoformat(),
                "entries": [{"goal_id": str(goal.id), "completed": completed}],
            })
        rows = (await db_session.execute(
            select(GoalEntry).where(GoalEntry.goal_id == goal.id)
        )).scalars().all()
        assert len(rows) == 1
        assert rows[0].completed is False

    async def test_unplanned_day_rejected(self, client, user, db_session):
        headers, user_id = user
        off_day = (TODAY.weekday() + 1) % 7
        goal = await create_goal(
            db_session, uuid.UUID(user_id),
            frequency_type="weekdays", frequency_value={"days": [off_day]},
            started_at=TODAY - timedelta(days=7),
        )
        resp = await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(goal.id), "completed": True}],
        })
        assert resp.status_code == 400

    async def test_unknown_goal_silently_skipped(self, client, user):
        """Текущий контракт: несуществующая цель в entries молча пропускается.

        Спорно (клиент не узнаёт об ошибке), но фиксируем поведение.
        """
        headers, _ = user
        resp = await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(uuid.uuid4()), "completed": True}],
        })
        assert resp.status_code == 200

    async def test_foreign_goal_not_writable(self, client, user, db_session):
        from tests.conftest import register
        headers, _ = user
        _, other_id = await register(client, "other-checkin@example.com")
        foreign = await create_goal(db_session, uuid.UUID(other_id))
        resp = await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(foreign.id), "completed": True}],
        })
        assert resp.status_code == 200  # пропущена как чужая
        rows = (await db_session.execute(
            select(GoalEntry).where(GoalEntry.goal_id == foreign.id)
        )).scalars().all()
        assert rows == []


class TestSaveQuantitative:
    async def _quant_goal(self, db_session, user_id, direction, target, **kw):
        return await create_goal(
            db_session, uuid.UUID(user_id),
            measure="quantitative", goal_type="quantitative",
            direction=direction, target=target, unit="шт", **kw,
        )

    async def test_down_goal_under_limit_completed(self, client, user, db_session):
        headers, user_id = user
        goal = await self._quant_goal(db_session, user_id, "down", 5.0)
        await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(goal.id), "completed": False, "actual_value": 3}],
        })
        entry = (await db_session.execute(
            select(GoalEntry).where(GoalEntry.goal_id == goal.id)
        )).scalar_one()
        assert entry.completed is True  # 3 <= 5 — уложился
        assert entry.actual_value == 3

    async def test_down_goal_over_limit_not_completed(self, client, user, db_session):
        headers, user_id = user
        goal = await self._quant_goal(db_session, user_id, "down", 5.0)
        await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(goal.id), "completed": True, "actual_value": 7}],
        })
        entry = (await db_session.execute(
            select(GoalEntry).where(GoalEntry.goal_id == goal.id)
        )).scalar_one()
        assert entry.completed is False  # 7 > 5 — сервер переопределил клиента

    async def test_up_goal_reaching_target_completed(self, client, user, db_session):
        headers, user_id = user
        goal = await self._quant_goal(db_session, user_id, "up", 10.0)
        await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(goal.id), "completed": False, "actual_value": 12}],
        })
        entry = (await db_session.execute(
            select(GoalEntry).where(GoalEntry.goal_id == goal.id)
        )).scalar_one()
        assert entry.completed is True

    async def test_ramped_limit_used_for_completion(self, client, user, db_session):
        """День 6 рампы 20→10 за 11 дней: лимит 15, факт 14 → выполнено."""
        headers, user_id = user
        goal = await self._quant_goal(
            db_session, user_id, "down", 10.0,
            baseline=20.0, horizon_days=11,
            started_at=TODAY - timedelta(days=5),
        )
        await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [{"goal_id": str(goal.id), "completed": False, "actual_value": 14}],
        })
        entry = (await db_session.execute(
            select(GoalEntry).where(GoalEntry.goal_id == goal.id)
        )).scalar_one()
        assert entry.completed is True

    async def test_checkin_exposes_plan_limit(self, client, user, db_session):
        headers, user_id = user
        await self._quant_goal(
            db_session, user_id, "down", 10.0,
            baseline=20.0, horizon_days=11,
            started_at=TODAY - timedelta(days=5),
        )
        body = (await client.get("/api/v1/checkin/today", headers=headers)).json()
        assert body["goals"][0]["plan"]["limit"] == 15.0
        assert body["goals"][0]["plan"]["day_number"] == 6


class TestDailyLog:
    async def test_saved_and_returned(self, client, user):
        headers, _ = user
        await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "entries": [],
            "daily_log": {"weight_kg": 80.5, "sleep_hours": 7, "energy": 8, "mood": 9},
        })
        body = (await client.get("/api/v1/checkin/today", headers=headers)).json()
        assert body["daily_log"] == {
            "weight_kg": 80.5, "sleep_hours": 7.0, "energy": 8, "mood": 9,
        }

    async def test_merge_does_not_wipe_other_fields(self, client, user, db_session):
        headers, user_id = user
        await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(), "entries": [],
            "daily_log": {"weight_kg": 80.5},
        })
        await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(), "entries": [],
            "daily_log": {"mood": 5},
        })
        log = (await db_session.execute(
            select(DailyLog).where(DailyLog.user_id == uuid.UUID(user_id))
        )).scalar_one()
        assert log.weight_kg == 80.5
        assert log.mood == 5


class TestGoalMetrics:
    async def test_metric_values_saved_with_daily_log(self, client, user, db_session):
        """Сохранение чек-ина с метриками цели.

        В checkin.py используется GoalMetricEntry, который не импортирован —
        если тест падает с 500 (NameError), это подтверждённый баг.
        """
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id))
        metric = GoalMetric(goal_id=goal.id, metric_name="Пульс покоя",
                            unit="уд/мин", prompt="Измерь пульс утром")
        db_session.add(metric)
        await db_session.commit()
        await db_session.refresh(metric)

        resp = await client.post("/api/v1/checkin", headers=headers, json={
            "date": TODAY.isoformat(),
            "daily_log": {"energy": 7},
            "entries": [{
                "goal_id": str(goal.id),
                "completed": True,
                "metrics": [{"goal_metric_id": str(metric.id), "value": "58"}],
            }],
        })
        assert resp.status_code == 200, f"metrics save failed: {resp.status_code} {resp.text[:200]}"
        row = (await db_session.execute(
            select(GoalMetricEntry).where(GoalMetricEntry.goal_metric_id == metric.id)
        )).scalar_one()
        assert row.value == "58"
