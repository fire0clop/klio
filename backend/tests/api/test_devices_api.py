"""Интеграционные тесты /devices."""
from sqlalchemy.future import select

from app.models.models import DeviceToken


class TestDeviceTokens:
    async def test_register_token(self, client, user, db_session):
        headers, _ = user
        resp = await client.post("/api/v1/devices/token", headers=headers,
                                 json={"token": "apns-token-1", "platform": "ios"})
        assert resp.status_code == 201
        rows = (await db_session.execute(select(DeviceToken))).scalars().all()
        assert len(rows) == 1
        assert rows[0].token == "apns-token-1"

    async def test_duplicate_token_idempotent(self, client, user, db_session):
        headers, _ = user
        for _ in range(2):
            resp = await client.post("/api/v1/devices/token", headers=headers,
                                     json={"token": "apns-token-dup"})
            assert resp.status_code == 201
        rows = (await db_session.execute(select(DeviceToken))).scalars().all()
        assert len(rows) == 1

    async def test_requires_auth(self, client):
        resp = await client.post("/api/v1/devices/token", json={"token": "x"})
        assert resp.status_code in (401, 403)
