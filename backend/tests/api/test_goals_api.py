"""Интеграционные тесты /goals: AI-диалог замокан, БД настоящая."""
import uuid
from datetime import date, timedelta

import pytest
from sqlalchemy.future import select

from app.models.models import Goal, GoalQuestion, Sphere
from tests.conftest import register
from tests.factories import create_goal, make_entry

READY_GOAL = {
    "status": "ready",
    "goal": {
        "title": "Отжиматься каждый день",
        "measure": "quantitative",
        "horizon": "eternal",
        "direction": "up",
        "controllability": "direct",
        "baseline": 10,
        "target": 20,
        "unit": "раз",
        "growing": True,
        "metric_has_ceiling": False,
        "cadence": "weekly",
        "summary": "Отжимания ежедневно, цель 20",
        "icon": "figure.strengthtraining.traditional",
        "effects": [{"name": "Сила", "icon": "bolt",
                     "milestones": [{"day": 7, "percent": 20, "description": "Тонус"}]}],
    },
}

QUESTION = {"status": "question", "question": "Сколько раз сейчас получается?"}


@pytest.fixture
def mock_ai(monkeypatch):
    """Мокает AI: диалог целей и назначение сфер."""
    calls = {"dialog": [], "spheres": []}

    def set_dialog(result):
        async def fake_dialog(title, qa_pairs, profile=None, lang="ru"):
            calls["dialog"].append({"title": title, "qa": list(qa_pairs)})
            return result
        monkeypatch.setattr("app.api.v1.goals.advance_goal_dialog", fake_dialog)

    async def fake_assign(goal_info, existing, lang="ru"):
        calls["spheres"].append(goal_info)
        return [{"key": "health", "name": "Здоровье", "icon": "heart"}]

    monkeypatch.setattr("app.services.sphere_service.assign_spheres", fake_assign)
    return {"set_dialog": set_dialog, "calls": calls}


class TestStartGoal:
    async def test_start_returns_first_question(self, client, user, mock_ai):
        headers, _ = user
        mock_ai["set_dialog"](QUESTION)
        resp = await client.post("/api/v1/goals/start",
                                 json={"title": "Бросить курить"}, headers=headers)
        assert resp.status_code == 201
        body = resp.json()
        assert body["question"] == QUESTION["question"]
        assert body["question_index"] == 0

    async def test_start_immediately_ready_saves_structure(self, client, user, db_session, mock_ai):
        headers, _ = user
        mock_ai["set_dialog"](READY_GOAL)
        resp = await client.post("/api/v1/goals/start",
                                 json={"title": "отжиматься"}, headers=headers)
        assert resp.status_code == 201
        body = resp.json()
        assert body["question_index"] == -1
        assert body["summary"] == "Отжимания ежедневно, цель 20"

        goal = (await db_session.execute(
            select(Goal).where(Goal.id == uuid.UUID(body["goal_id"]))
        )).scalar_one()
        assert goal.dialog_complete is True
        assert goal.measure == "quantitative"
        assert goal.target == 20
        assert goal.title == "Отжиматься каждый день"  # нормализованный заголовок
        assert goal.frequency_type == "times_per_week"  # cadence weekly → times_per_week
        assert goal.icon == "figure.strengthtraining.traditional"
        assert goal.ai_effect_trajectory == {"effects": READY_GOAL["goal"]["effects"]}

    async def test_ready_goal_gets_sphere_assignment(self, client, user, db_session, mock_ai):
        """Сферы: при создании готовой цели ИИ должен назначить сферы,
        goal.sphere_keys — заполниться, а строка Sphere — появиться в БД.

        Если тест падает при живом моке ИИ — значит вызов до ИИ не доходит
        (например, lazy-load user.profile в async-контексте молча гасится
        try/except в assign_goal_spheres).
        """
        headers, _ = user
        mock_ai["set_dialog"](READY_GOAL)
        resp = await client.post("/api/v1/goals/start",
                                 json={"title": "отжиматься"}, headers=headers)
        goal = (await db_session.execute(
            select(Goal).where(Goal.id == uuid.UUID(resp.json()["goal_id"]))
        )).scalar_one()
        assert goal.sphere_keys == ["health"]
        sphere = (await db_session.execute(select(Sphere))).scalars().all()
        assert len(sphere) == 1


class TestAnswerFlow:
    async def test_question_then_ready(self, client, user, db_session, mock_ai):
        headers, _ = user
        mock_ai["set_dialog"](QUESTION)
        start = (await client.post("/api/v1/goals/start",
                                   json={"title": "Бросить курить"}, headers=headers)).json()

        mock_ai["set_dialog"](READY_GOAL)
        resp = await client.post(f"/api/v1/goals/{start['goal_id']}/answer",
                                 json={"answer": "10 раз"}, headers=headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["done"] is True
        assert body["summary"]

        # диалог передал в ИИ пару вопрос-ответ
        assert mock_ai["calls"]["dialog"][-1]["qa"] == [
            {"question": QUESTION["question"], "answer": "10 раз"}
        ]

    async def test_second_question_appended(self, client, user, db_session, mock_ai):
        headers, _ = user
        mock_ai["set_dialog"](QUESTION)
        start = (await client.post("/api/v1/goals/start",
                                   json={"title": "Бегать"}, headers=headers)).json()
        mock_ai["set_dialog"]({"status": "question", "question": "Как часто?"})
        resp = await client.post(f"/api/v1/goals/{start['goal_id']}/answer",
                                 json={"answer": "3 км"}, headers=headers)
        body = resp.json()
        assert body["done"] is False
        assert body["question"] == "Как часто?"
        assert body["question_index"] == 1

        questions = (await db_session.execute(
            select(GoalQuestion).where(GoalQuestion.goal_id == uuid.UUID(start["goal_id"]))
            .order_by(GoalQuestion.order_index)
        )).scalars().all()
        assert [q.order_index for q in questions] == [0, 1]

    async def test_answer_after_complete_rejected(self, client, user, mock_ai):
        headers, _ = user
        mock_ai["set_dialog"](READY_GOAL)
        start = (await client.post("/api/v1/goals/start",
                                   json={"title": "отжиматься"}, headers=headers)).json()
        resp = await client.post(f"/api/v1/goals/{start['goal_id']}/answer",
                                 json={"answer": "ещё"}, headers=headers)
        assert resp.status_code == 400


class TestGoalCrud:
    async def test_confirm_sets_frequency(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id))
        resp = await client.post(
            f"/api/v1/goals/{goal.id}/confirm",
            json={"frequency": {"type": "weekdays", "value": {"days": [0, 2, 4]}}},
            headers=headers,
        )
        assert resp.status_code == 200
        await db_session.refresh(goal)
        assert goal.frequency_type == "weekdays"
        assert goal.frequency_value == {"days": [0, 2, 4]}

    async def test_list_returns_only_own_active(self, client, user, db_session):
        headers, user_id = user
        uid = uuid.UUID(user_id)
        await create_goal(db_session, uid, title="Активная")
        await create_goal(db_session, uid, title="Архив", is_active=False)

        other_headers, other_id = await register(client, "other@example.com")
        await create_goal(db_session, uuid.UUID(other_id), title="Чужая")

        resp = await client.get("/api/v1/goals", headers=headers)
        assert resp.status_code == 200
        titles = [g["title"] for g in resp.json()]
        assert titles == ["Активная"]
        g = resp.json()[0]
        assert "current_streak" in g and "completion_rate" in g

    async def test_foreign_goal_404(self, client, user, db_session):
        headers, _ = user
        _, other_id = await register(client, "other2@example.com")
        foreign = await create_goal(db_session, uuid.UUID(other_id))
        resp = await client.get(f"/api/v1/goals/{foreign.id}", headers=headers)
        assert resp.status_code == 404

    async def test_detail_includes_ai_context(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id),
                                 ai_context={"qa": [], "goal": {"x": 1}})
        resp = await client.get(f"/api/v1/goals/{goal.id}", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["ai_context"] == {"qa": [], "goal": {"x": 1}}

    async def test_archive_hides_from_list(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id))
        resp = await client.delete(f"/api/v1/goals/{goal.id}", headers=headers)
        assert resp.status_code == 204
        listing = (await client.get("/api/v1/goals", headers=headers)).json()
        assert listing == []


class TestHistory:
    async def test_history_default_14_days(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id),
                                 started_at=date.today() - timedelta(days=30))
        db_session.add(make_entry(date.today(), completed=True, goal_id=goal.id))
        db_session.add(make_entry(date.today() - timedelta(days=1), completed=False, goal_id=goal.id))
        await db_session.commit()

        resp = await client.get(f"/api/v1/goals/{goal.id}/history", headers=headers)
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 14
        assert rows[-1]["date"] == date.today().isoformat()
        assert rows[-1]["completed"] is True
        assert rows[-2]["completed"] is False

    async def test_history_clamps_to_90(self, client, user, db_session):
        headers, user_id = user
        goal = await create_goal(db_session, uuid.UUID(user_id))
        rows = (await client.get(f"/api/v1/goals/{goal.id}/history?days=500",
                                 headers=headers)).json()
        assert len(rows) == 90


class TestAdapt:
    async def _overperforming_goal(self, db_session, user_id):
        goal = await create_goal(
            db_session, uuid.UUID(user_id),
            measure="quantitative", goal_type="quantitative",
            direction="up", growing=True, horizon="eternal",
            target=10.0, unit="раз",
            started_at=date.today() - timedelta(days=30),
        )
        for n in range(6):
            db_session.add(make_entry(date.today() - timedelta(days=n),
                                      completed=True, value=12.0, goal_id=goal.id))
        await db_session.commit()
        return goal

    async def test_accept_with_explicit_target(self, client, user, db_session):
        headers, user_id = user
        goal = await self._overperforming_goal(db_session, user_id)
        resp = await client.post(f"/api/v1/goals/{goal.id}/adapt",
                                 json={"action": "accept", "target": 15}, headers=headers)
        assert resp.status_code == 200
        await db_session.refresh(goal)
        assert goal.target == 15.0

    async def test_accept_without_target_uses_suggestion(self, client, user, db_session):
        headers, user_id = user
        goal = await self._overperforming_goal(db_session, user_id)
        resp = await client.post(f"/api/v1/goals/{goal.id}/adapt",
                                 json={"action": "accept"}, headers=headers)
        assert resp.status_code == 200
        await db_session.refresh(goal)
        assert goal.target == 11.0  # 10 + 0.5*(12-10)

    async def test_decline_remembers_target(self, client, user, db_session):
        headers, user_id = user
        goal = await self._overperforming_goal(db_session, user_id)
        resp = await client.post(f"/api/v1/goals/{goal.id}/adapt",
                                 json={"action": "decline"}, headers=headers)
        assert resp.status_code == 200
        await db_session.refresh(goal)
        assert goal.ai_context.get("adapt_declined_target") == 11.0
