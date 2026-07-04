"""Интеграционные тесты /profile: автосоздание, обновление, удаление аккаунта."""
import uuid
from datetime import date

from sqlalchemy.future import select

from app.models.models import (
    DailyLog, GoalEntry, Insight, Sphere, User, UserProfile,
)
from tests.conftest import register
from tests.factories import create_goal, make_entry


class TestGetProfile:
    async def test_autocreated_with_defaults(self, client, user):
        headers, _ = user
        resp = await client.get("/api/v1/profile", headers=headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["language"] == "ru"
        assert body["onboarding_completed"] is False
        assert body["name"] is None


class TestUpdateProfile:
    async def test_partial_update(self, client, user):
        headers, _ = user
        resp = await client.put("/api/v1/profile", headers=headers, json={
            "name": "Егор", "weight_kg": 78.5, "language": "en",
        })
        assert resp.status_code == 200
        body = resp.json()
        assert body["name"] == "Егор"
        assert body["weight_kg"] == 78.5
        assert body["language"] == "en"

    async def test_second_update_keeps_previous_fields(self, client, user):
        headers, _ = user
        await client.put("/api/v1/profile", headers=headers, json={"name": "Егор"})
        await client.put("/api/v1/profile", headers=headers,
                         json={"onboarding_completed": True})
        body = (await client.get("/api/v1/profile", headers=headers)).json()
        assert body["name"] == "Егор"
        assert body["onboarding_completed"] is True

    async def test_date_of_birth_roundtrip(self, client, user):
        headers, _ = user
        await client.put("/api/v1/profile", headers=headers,
                         json={"date_of_birth": "1995-03-14"})
        body = (await client.get("/api/v1/profile", headers=headers)).json()
        assert body["date_of_birth"] == "1995-03-14"


class TestDeleteAccount:
    async def test_deletes_user_and_all_data(self, client, user, db_session):
        headers, user_id = user
        uid = uuid.UUID(user_id)

        goal = await create_goal(db_session, uid)
        db_session.add(make_entry(date.today(), goal_id=goal.id))
        db_session.add(DailyLog(user_id=uid, date=date.today(), energy=5))
        db_session.add(Insight(user_id=uid, content="совет", kind="tip", title="t"))
        db_session.add(Sphere(user_id=uid, key="health", name="Здоровье",
                              icon="heart", value=10))
        await db_session.commit()

        resp = await client.delete("/api/v1/profile/me", headers=headers)
        assert resp.status_code == 204

        for model in (User, UserProfile, DailyLog, Insight, Sphere):
            rows = (await db_session.execute(select(model))).scalars().all()
            assert rows == [], f"{model.__name__} не удалён"
        entries = (await db_session.execute(select(GoalEntry))).scalars().all()
        assert entries == []

    async def test_app_review_account_survives_deletion(self, client, db_session):
        headers, _ = await register(client, "appreview@klio-diary.ru", "review-pass-1")
        resp = await client.delete("/api/v1/profile/me", headers=headers)
        assert resp.status_code == 204  # приложению отвечаем успехом
        login = await client.post("/api/v1/auth/login", json={
            "email": "appreview@klio-diary.ru", "password": "review-pass-1",
        })
        assert login.status_code == 200  # но запись жива
