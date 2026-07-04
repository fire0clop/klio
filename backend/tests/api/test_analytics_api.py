"""Интеграционные тесты /analytics: стрики, таймлайны, инсайты (AI замокан), сферы."""
import uuid
from datetime import date, datetime, timedelta

import pytest
from sqlalchemy.future import select

from app.models.models import DailyLog, Insight, Sphere
from tests.factories import create_goal, make_entry

TODAY = date.today()


@pytest.fixture
def mock_reactions(monkeypatch):
    """Мокает генерацию дневных реакций Claude."""
    state = {"calls": 0, "items": [
        {"kind": "win", "title": "Так держать", "text": "3 дня подряд!"},
        {"kind": "tip", "title": "Совет", "text": "Пей воду."},
        {"kind": "reaction", "title": "Вчера", "text": "Все цели закрыты."},
    ]}

    async def fake(user_data, lang="ru"):
        state["calls"] += 1
        return state["items"]

    monkeypatch.setattr("app.services.insight_service.generate_daily_reactions", fake)
    return state


async def _seeded_goal(db_session, user_id, completed_days=3):
    goal = await create_goal(db_session, uuid.UUID(user_id),
                             started_at=TODAY - timedelta(days=9))
    for n in range(completed_days):
        db_session.add(make_entry(TODAY - timedelta(days=n), goal_id=goal.id))
    await db_session.commit()
    return goal


class TestStreakEndpoint:
    async def test_streak_numbers(self, client, user, db_session):
        headers, user_id = user
        goal = await _seeded_goal(db_session, user_id, completed_days=3)
        body = (await client.get(f"/api/v1/analytics/goals/{goal.id}/streak",
                                 headers=headers)).json()
        assert body["current_streak"] == 3
        assert body["best_streak"] == 3
        assert body["total_completed"] == 3
        assert body["weekly_rate"] == round(3 / 7, 2)
        assert body["monthly_rate"] == 0.3  # 3 из 10 плановых дней

    async def test_foreign_goal_404(self, client, user, db_session):
        from tests.conftest import register
        headers, _ = user
        _, other_id = await register(client, "an-other@example.com")
        foreign = await create_goal(db_session, uuid.UUID(other_id))
        resp = await client.get(f"/api/v1/analytics/goals/{foreign.id}/streak",
                                headers=headers)
        assert resp.status_code == 404


class TestTimeline:
    async def test_timeline_marks_planned_and_completed(self, client, user, db_session):
        headers, user_id = user
        goal = await _seeded_goal(db_session, user_id, completed_days=2)
        body = (await client.get(
            f"/api/v1/analytics/goals/{goal.id}/timeline?days=10", headers=headers,
        )).json()
        entries = body["entries"]
        assert len(entries) == 10
        assert entries[-1]["date"] == TODAY.isoformat()
        assert entries[-1]["completed"] is True
        assert entries[0]["is_planned"] is True
        assert entries[0]["completed"] is None  # планово, но не отмечено

    async def test_weekday_goal_offdays_unplanned(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(
            db_session, uuid.UUID(user_id),
            frequency_type="weekdays",
            frequency_value={"days": [TODAY.weekday()]},
            started_at=TODAY - timedelta(days=6),
        )
        body = (await client.get(
            f"/api/v1/analytics/goals/{goal.id}/timeline?days=7", headers=headers,
        )).json()
        planned = [e for e in body["entries"] if e["is_planned"]]
        assert len(planned) == 1  # только сегодняшний день недели


class TestEffects:
    async def test_effect_progress_at_streak(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(
            db_session, uuid.UUID(user_id),
            started_at=TODAY - timedelta(days=6),
            ai_effect_trajectory={"effects": [{
                "name": "Сон", "icon": "moon",
                "milestones": [
                    {"day": 7, "percent": 30, "description": "Лучше засыпаешь"},
                    {"day": 30, "percent": 100, "description": "Стабильный сон"},
                ],
            }]},
        )
        for n in range(7):
            db_session.add(make_entry(TODAY - timedelta(days=n), goal_id=goal.id))
        await db_session.commit()

        body = (await client.get(f"/api/v1/analytics/goals/{goal.id}/effects",
                                 headers=headers)).json()
        assert body["current_streak"] == 7
        effect = body["effects"][0]
        assert effect["current_percent"] == 30
        assert effect["description"] == "Лучше засыпаешь"

    async def test_no_trajectory_empty_effects(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id))
        body = (await client.get(f"/api/v1/analytics/goals/{goal.id}/effects",
                                 headers=headers)).json()
        assert body["effects"] == []


class TestDailyLogTimeline:
    async def test_returns_window(self, client, user, db_session):
        headers, user_id = user
        uid = uuid.UUID(user_id)
        db_session.add(DailyLog(user_id=uid, date=TODAY, energy=8, weight_kg=80))
        db_session.add(DailyLog(user_id=uid, date=TODAY - timedelta(days=1), mood=6))
        db_session.add(DailyLog(user_id=uid, date=TODAY - timedelta(days=60), energy=1))
        await db_session.commit()

        body = (await client.get("/api/v1/analytics/daily-log/timeline?days=30",
                                 headers=headers)).json()
        dates = [e["date"] for e in body["entries"]]
        assert dates == [(TODAY - timedelta(days=1)).isoformat(), TODAY.isoformat()]


class TestInsights:
    async def test_generated_on_first_request(self, client, user, db_session, mock_reactions):
        headers, user_id = user
        await _seeded_goal(db_session, user_id)
        body = (await client.get("/api/v1/analytics/insights", headers=headers)).json()
        assert mock_reactions["calls"] == 1
        assert len(body) == 3
        # отсортированы по порядку kind: reaction, win, ... , tip
        assert [i["kind"] for i in body] == ["reaction", "win", "tip"]

    async def test_cached_within_same_day(self, client, user, db_session, mock_reactions):
        headers, user_id = user
        await _seeded_goal(db_session, user_id)
        await client.get("/api/v1/analytics/insights", headers=headers)
        await client.get("/api/v1/analytics/insights", headers=headers)
        assert mock_reactions["calls"] == 1  # вторая выдача из БД

    async def test_no_goals_no_generation(self, client, user, mock_reactions):
        headers, _ = user
        body = (await client.get("/api/v1/analytics/insights", headers=headers)).json()
        assert body == []
        assert mock_reactions["calls"] == 0

    async def test_status_endpoint(self, client, user, db_session, mock_reactions):
        headers, user_id = user
        status = (await client.get("/api/v1/analytics/insights/status",
                                   headers=headers)).json()
        assert status == {"has_insights": False, "last_updated": None}

        await _seeded_goal(db_session, user_id)
        await client.get("/api/v1/analytics/insights", headers=headers)
        status = (await client.get("/api/v1/analytics/insights/status",
                                   headers=headers)).json()
        assert status["has_insights"] is True

    async def test_force_refresh_generates_new_batch(self, client, user, db_session, mock_reactions):
        headers, user_id = user
        await _seeded_goal(db_session, user_id)
        await client.get("/api/v1/analytics/insights", headers=headers)
        resp = await client.post("/api/v1/analytics/insights/refresh", headers=headers)
        assert resp.status_code == 200
        assert mock_reactions["calls"] == 2


class TestSpheres:
    async def test_spheres_payload(self, client, user, db_session, monkeypatch):
        headers, user_id = user
        uid = uuid.UUID(user_id)

        # ИИ-пересчёт не должен дёргаться: сферы уже свежие, цели размечены
        async def fail(*a, **kw):
            raise AssertionError("AI не должен вызываться для свежих сфер")
        monkeypatch.setattr("app.services.sphere_service.compute_sphere_updates", fail)

        goal = await create_goal(db_session, uid, sphere_keys=["health"])
        db_session.add(Sphere(user_id=uid, key="health", name="Здоровье", icon="heart",
                              value=42.4, caption="Ровный прогресс",
                              updated_at=datetime.now()))
        await db_session.commit()

        body = (await client.get("/api/v1/analytics/spheres", headers=headers)).json()
        assert len(body) == 1
        sphere = body[0]
        assert sphere["name"] == "Здоровье"
        assert sphere["percent"] == 42
        assert sphere["goals"] == [goal.title]
        assert sphere["caption"] == "Ровный прогресс"

    async def test_stale_spheres_trigger_ai_recount(self, client, user, db_session, monkeypatch):
        """Сферы, обновлённые вчера, должны пересчитаться через ИИ.

        Если тест падает (значение не обновилось) — ИИ-вызов не дошёл до мока:
        см. lazy-load user.profile внутри update_spheres, гасится try/except.
        """
        headers, user_id = user
        uid = uuid.UUID(user_id)

        async def fake_updates(payload, lang="ru"):
            return [{"key": "health", "value": 55, "caption": "Рост"}]
        monkeypatch.setattr("app.services.sphere_service.compute_sphere_updates", fake_updates)

        await create_goal(db_session, uid, sphere_keys=["health"])
        db_session.add(Sphere(user_id=uid, key="health", name="Здоровье", icon="heart",
                              value=40, updated_at=datetime.now() - timedelta(days=1)))
        await db_session.commit()

        body = (await client.get("/api/v1/analytics/spheres", headers=headers)).json()
        assert body[0]["percent"] == 55
        assert body[0]["caption"] == "Рост"
