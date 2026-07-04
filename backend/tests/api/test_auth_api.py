"""Интеграционные тесты /auth и защиты эндпоинтов."""
from datetime import timedelta

from app.services.auth_service import create_token

from tests.conftest import register


class TestRegister:
    async def test_register_returns_token_pair(self, client):
        resp = await client.post("/api/v1/auth/register",
                                 json={"email": "new@example.com", "password": "secret-123"})
        assert resp.status_code == 201
        body = resp.json()
        assert body["access_token"] and body["refresh_token"]
        assert body["token_type"] == "bearer"

    async def test_duplicate_email_rejected(self, client):
        payload = {"email": "dup@example.com", "password": "secret-123"}
        await client.post("/api/v1/auth/register", json=payload)
        resp = await client.post("/api/v1/auth/register", json=payload)
        assert resp.status_code == 400

    async def test_invalid_email_rejected(self, client):
        resp = await client.post("/api/v1/auth/register",
                                 json={"email": "not-an-email", "password": "secret-123"})
        assert resp.status_code == 422

    async def test_short_password_rejected(self, client):
        """Контракт безопасности: минимум 6 символов, как в iOS-клиенте."""
        for bad in ("", "12345"):
            resp = await client.post("/api/v1/auth/register",
                                     json={"email": "weak@example.com", "password": bad})
            assert resp.status_code == 422

    async def test_six_char_password_accepted(self, client):
        resp = await client.post("/api/v1/auth/register",
                                 json={"email": "sixchars@example.com", "password": "123456"})
        assert resp.status_code == 201


class TestLogin:
    async def test_login_ok(self, client):
        await register(client, "login@example.com", "secret-123")
        resp = await client.post("/api/v1/auth/login",
                                 json={"email": "login@example.com", "password": "secret-123"})
        assert resp.status_code == 200
        assert resp.json()["access_token"]

    async def test_wrong_password(self, client):
        await register(client, "login2@example.com", "secret-123")
        resp = await client.post("/api/v1/auth/login",
                                 json={"email": "login2@example.com", "password": "wrong"})
        assert resp.status_code == 401

    async def test_unknown_email(self, client):
        resp = await client.post("/api/v1/auth/login",
                                 json={"email": "ghost@example.com", "password": "whatever"})
        assert resp.status_code == 401


class TestRefresh:
    async def test_refresh_rotates_pair(self, client):
        resp = await client.post("/api/v1/auth/register",
                                 json={"email": "r@example.com", "password": "secret-123"})
        refresh_token = resp.json()["refresh_token"]
        resp2 = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
        assert resp2.status_code == 200
        assert resp2.json()["access_token"]

    async def test_access_token_not_accepted_as_refresh(self, client):
        resp = await client.post("/api/v1/auth/register",
                                 json={"email": "r2@example.com", "password": "secret-123"})
        access_token = resp.json()["access_token"]
        resp2 = await client.post("/api/v1/auth/refresh", json={"refresh_token": access_token})
        assert resp2.status_code == 401

    async def test_garbage_refresh_rejected(self, client):
        resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": "garbage"})
        assert resp.status_code == 401


class TestProtectedRoutes:
    async def test_missing_token(self, client):
        resp = await client.get("/api/v1/goals")
        assert resp.status_code in (401, 403)  # HTTPBearer → 403 Not authenticated

    async def test_invalid_token(self, client):
        resp = await client.get("/api/v1/goals",
                                headers={"Authorization": "Bearer invalid"})
        assert resp.status_code == 401

    async def test_refresh_token_not_accepted_as_access(self, client):
        resp = await client.post("/api/v1/auth/register",
                                 json={"email": "p@example.com", "password": "secret-123"})
        refresh_token = resp.json()["refresh_token"]
        resp2 = await client.get("/api/v1/goals",
                                 headers={"Authorization": f"Bearer {refresh_token}"})
        assert resp2.status_code == 401

    async def test_expired_access_token(self, client, user):
        _, user_id = user
        expired = create_token({"sub": user_id, "type": "access"}, timedelta(seconds=-5))
        resp = await client.get("/api/v1/goals",
                                headers={"Authorization": f"Bearer {expired}"})
        assert resp.status_code == 401

    async def test_token_of_deleted_user(self, client, user):
        headers, _ = user
        await client.delete("/api/v1/profile/me", headers=headers)
        resp = await client.get("/api/v1/goals", headers=headers)
        assert resp.status_code == 401


class TestHealth:
    async def test_health(self, client):
        resp = await client.get("/health")
        assert resp.status_code == 200
        assert resp.json() == {"status": "ok"}
