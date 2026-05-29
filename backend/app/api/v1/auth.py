from fastapi import APIRouter, Depends, HTTPException, Request, status
from jose import JWTError
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.schemas.auth import (
    AppleAuthRequest,
    GoogleAuthRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
)
from app.services.auth_service import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_user_by_email,
    get_user_by_id,
    register_user,
    verify_password,
)
from app.services.social_auth_service import (
    find_or_create_social_user,
    verify_apple_identity_token,
    verify_google_id_token,
)

router = APIRouter(prefix="/auth", tags=["auth"])
limiter = Limiter(key_func=get_remote_address)


def _issue_tokens(user_id: str) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(user_id),
        refresh_token=create_refresh_token(user_id),
    )


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")
async def register(request: Request, body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    existing = await get_user_by_email(db, body.email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    user = await register_user(db, body.email, body.password)
    return _issue_tokens(str(user.id))


@router.post("/login", response_model=TokenResponse)
@limiter.limit("20/minute")
async def login(request: Request, body: LoginRequest, db: AsyncSession = Depends(get_db)):
    user = await get_user_by_email(db, body.email)
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return _issue_tokens(str(user.id))


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("30/minute")
async def refresh(request: Request, body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    try:
        payload = decode_token(body.refresh_token)
        if payload.get("type") != "refresh":
            raise ValueError
        user_id = payload["sub"]
    except (JWTError, ValueError, KeyError):
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    user = await get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return _issue_tokens(str(user.id))


# ---------- Sign in with Apple ----------

@router.post("/apple", response_model=TokenResponse)
@limiter.limit("20/minute")
async def apple_auth(request: Request, body: AppleAuthRequest, db: AsyncSession = Depends(get_db)):
    try:
        apple_sub, token_email = await verify_apple_identity_token(
            body.identity_token,
            audience=settings.APPLE_CLIENT_ID,
        )
    except ValueError as e:
        raise HTTPException(status_code=401, detail=f"Apple auth failed: {e}")

    user = await find_or_create_social_user(
        db,
        provider="apple",
        provider_sub=apple_sub,
        email=body.email or token_email,
        name=body.name,
    )
    return _issue_tokens(str(user.id))


# ---------- Sign in with Google ----------

@router.post("/google", response_model=TokenResponse)
@limiter.limit("20/minute")
async def google_auth(request: Request, body: GoogleAuthRequest, db: AsyncSession = Depends(get_db)):
    if not settings.GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=500, detail="GOOGLE_CLIENT_ID is not configured")

    try:
        google_sub, email = await verify_google_id_token(
            body.id_token,
            audience=settings.GOOGLE_CLIENT_ID,
        )
    except ValueError as e:
        raise HTTPException(status_code=401, detail=f"Google auth failed: {e}")

    user = await find_or_create_social_user(
        db,
        provider="google",
        provider_sub=google_sub,
        email=email,
        name=None,
    )
    return _issue_tokens(str(user.id))
