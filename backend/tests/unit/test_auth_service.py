"""Юнит-тесты криптопримитивов авторизации (bcrypt + JWT)."""
from datetime import timedelta

import pytest
from jose import JWTError, jwt
from jose.exceptions import ExpiredSignatureError

from app.config import settings
from app.services.auth_service import (
    create_access_token,
    create_refresh_token,
    create_token,
    decode_token,
    hash_password,
    verify_password,
)


class TestPasswordHashing:
    def test_hash_differs_from_plain(self):
        assert hash_password("secret123") != "secret123"

    def test_same_password_different_salts(self):
        assert hash_password("secret123") != hash_password("secret123")

    def test_verify_correct(self):
        hashed = hash_password("secret123")
        assert verify_password("secret123", hashed)

    def test_verify_wrong(self):
        hashed = hash_password("secret123")
        assert not verify_password("wrong", hashed)


class TestTokens:
    def test_access_token_claims(self):
        payload = decode_token(create_access_token("user-1"))
        assert payload["sub"] == "user-1"
        assert payload["type"] == "access"
        assert "exp" in payload

    def test_refresh_token_claims(self):
        payload = decode_token(create_refresh_token("user-1"))
        assert payload["type"] == "refresh"

    def test_expired_token_rejected(self):
        token = create_token({"sub": "u", "type": "access"}, timedelta(seconds=-10))
        with pytest.raises(ExpiredSignatureError):
            decode_token(token)

    def test_tampered_token_rejected(self):
        token = create_access_token("user-1") + "x"
        with pytest.raises(JWTError):
            decode_token(token)

    def test_wrong_secret_rejected(self):
        forged = jwt.encode({"sub": "u", "type": "access"}, "another-secret",
                            algorithm=settings.ALGORITHM)
        with pytest.raises(JWTError):
            decode_token(forged)
