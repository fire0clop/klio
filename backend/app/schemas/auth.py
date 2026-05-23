from typing import Optional

from pydantic import BaseModel, EmailStr


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


class AppleAuthRequest(BaseModel):
    """Body for POST /auth/apple.

    `identity_token` — JWT issued by Apple (from ASAuthorizationAppleIDCredential).
    `name` / `email` — Apple передаёт их только при первом входе пользователя в это
    приложение; iOS-клиент должен сохранить и приложить здесь, чтобы мы могли
    создать запись профиля с именем.
    """

    identity_token: str
    name: Optional[str] = None
    email: Optional[EmailStr] = None


class GoogleAuthRequest(BaseModel):
    """Body for POST /auth/google. `id_token` — Google ID Token (OpenID Connect)."""

    id_token: str
