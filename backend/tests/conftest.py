"""Общая тестовая инфраструктура.

Переменные окружения выставляются ДО импорта приложения, чтобы pydantic
Settings не подхватил боевые значения из backend/.env.

Интеграционные тесты ходят в отдельную БД klio_test локального PostgreSQL —
та же СУБД, что и в проде, поэтому UUID/JSON-колонки и уникальные
констрейнты ведут себя по-настоящему.
"""
import os

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://fire0clap@localhost:5432/klio_test",
)
# Страховка от запуска drop_all на небоевой базе.
assert "test" in TEST_DATABASE_URL, "Tests must run against a *_test database"

os.environ["DATABASE_URL"] = TEST_DATABASE_URL
os.environ["SECRET_KEY"] = "test-secret-key-not-for-production"
os.environ["ANTHROPIC_API_KEY"] = "test-anthropic-key-unused"
os.environ["GOOGLE_CLIENT_ID"] = "test-client.apps.googleusercontent.com"

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

import app.api.v1.auth as auth_routes
import app.main as app_main
from app.database import Base, get_db
from app.main import app
from app.services.auth_service import decode_token

# Лимиты считаются по IP; в тестах все запросы идут с одного клиента,
# поэтому limiter выключен — иначе соседние тесты ловят 429.
app_main.limiter.enabled = False
auth_routes.limiter.enabled = False


@pytest_asyncio.fixture()
async def db_engine():
    engine = create_async_engine(TEST_DATABASE_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture()
async def db_session(db_engine):
    maker = async_sessionmaker(db_engine, expire_on_commit=False)
    async with maker() as session:
        yield session


@pytest_asyncio.fixture()
async def client(db_engine):
    maker = async_sessionmaker(db_engine, expire_on_commit=False)

    async def _get_test_db():
        async with maker() as session:
            yield session

    app.dependency_overrides[get_db] = _get_test_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


async def register(client: AsyncClient, email: str = "user@example.com",
                   password: str = "correct-horse-battery") -> tuple[dict, str]:
    """Регистрирует пользователя, возвращает (auth-заголовки, user_id)."""
    resp = await client.post("/api/v1/auth/register",
                             json={"email": email, "password": password})
    assert resp.status_code == 201, resp.text
    tokens = resp.json()
    user_id = decode_token(tokens["access_token"])["sub"]
    return {"Authorization": f"Bearer {tokens['access_token']}"}, user_id


@pytest_asyncio.fixture()
async def user(client):
    """Зарегистрированный пользователь: (headers, user_id)."""
    return await register(client)
