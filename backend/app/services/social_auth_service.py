"""Verification of Apple / Google identity tokens.

Both providers sign their tokens with RS256 against rotating RSA keys exposed
as JWKS (JSON Web Key Sets). We:
  1. Fetch and cache JWKS (1h TTL).
  2. Find the key by 'kid' in the token header.
  3. Verify signature + iss + aud + exp via python-jose.

`find_or_create_social_user` lookup order:
  - by provider-sub (apple_sub / google_sub)
  - by email (link existing email-password account)
  - create a new user
"""

import time
from typing import Optional, Tuple

import httpx
from jose import jwt
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.models.models import User, UserProfile

APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"

GOOGLE_KEYS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ("https://accounts.google.com", "accounts.google.com")

_JWKS_CACHE: dict[str, tuple[dict, float]] = {}
_JWKS_TTL_SECONDS = 3600


async def _fetch_jwks(url: str) -> dict:
    cached = _JWKS_CACHE.get(url)
    if cached and (time.time() - cached[1]) < _JWKS_TTL_SECONDS:
        return cached[0]
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        jwks = resp.json()
    _JWKS_CACHE[url] = (jwks, time.time())
    return jwks


def _find_jwk(jwks: dict, kid: str) -> Optional[dict]:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key
    return None


async def verify_apple_identity_token(token: str, audience: str) -> Tuple[str, Optional[str]]:
    """Returns (apple_sub, email_if_present). Raises ValueError on failure."""
    try:
        header = jwt.get_unverified_header(token)
    except Exception as e:
        raise ValueError(f"Invalid token header: {e}") from e

    kid = header.get("kid")
    if not kid:
        raise ValueError("Apple token missing 'kid'")

    jwks = await _fetch_jwks(APPLE_KEYS_URL)
    key = _find_jwk(jwks, kid)
    if key is None:
        # JWKS could have rotated; force refresh once.
        _JWKS_CACHE.pop(APPLE_KEYS_URL, None)
        jwks = await _fetch_jwks(APPLE_KEYS_URL)
        key = _find_jwk(jwks, kid)
    if key is None:
        raise ValueError("Apple signing key not found")

    try:
        payload = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=audience,
            issuer=APPLE_ISSUER,
        )
    except Exception as e:
        raise ValueError(f"Apple token verification failed: {e}") from e

    sub = payload.get("sub")
    if not sub:
        raise ValueError("Apple token missing 'sub'")
    return sub, payload.get("email")


async def verify_google_id_token(token: str, audience: str) -> Tuple[str, Optional[str]]:
    """Returns (google_sub, email). Raises ValueError on failure."""
    try:
        header = jwt.get_unverified_header(token)
    except Exception as e:
        raise ValueError(f"Invalid token header: {e}") from e

    kid = header.get("kid")
    if not kid:
        raise ValueError("Google token missing 'kid'")

    jwks = await _fetch_jwks(GOOGLE_KEYS_URL)
    key = _find_jwk(jwks, kid)
    if key is None:
        _JWKS_CACHE.pop(GOOGLE_KEYS_URL, None)
        jwks = await _fetch_jwks(GOOGLE_KEYS_URL)
        key = _find_jwk(jwks, kid)
    if key is None:
        raise ValueError("Google signing key not found")

    try:
        # Google uses two valid issuer values; we accept both manually.
        # verify_at_hash=False because we only receive id_token (no access_token
        # to hash against), and signature + iss + aud + exp are already verified.
        payload = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=audience,
            options={"verify_iss": False, "verify_at_hash": False},
        )
    except Exception as e:
        raise ValueError(f"Google token verification failed: {e}") from e

    if payload.get("iss") not in GOOGLE_ISSUERS:
        raise ValueError(f"Invalid Google issuer: {payload.get('iss')}")

    sub = payload.get("sub")
    if not sub:
        raise ValueError("Google token missing 'sub'")
    return sub, payload.get("email")


async def find_or_create_social_user(
    db: AsyncSession,
    *,
    provider: str,  # "apple" | "google"
    provider_sub: str,
    email: Optional[str],
    name: Optional[str] = None,
) -> User:
    """Lookup-or-create flow used by both /auth/apple and /auth/google."""
    if provider not in ("apple", "google"):
        raise ValueError("Unknown provider")

    sub_col = User.apple_sub if provider == "apple" else User.google_sub
    sub_attr = "apple_sub" if provider == "apple" else "google_sub"

    # 1. Find by provider sub
    result = await db.execute(select(User).where(sub_col == provider_sub))
    user = result.scalar_one_or_none()
    if user:
        # Backfill profile name if we got it now and didn't before.
        if name:
            profile_q = await db.execute(select(UserProfile).where(UserProfile.user_id == user.id))
            profile = profile_q.scalar_one_or_none()
            if profile and not profile.name:
                profile.name = name
                await db.commit()
        return user

    # 2. Link by email if a password-account already exists
    if email:
        result = await db.execute(select(User).where(User.email == email))
        user = result.scalar_one_or_none()
        if user:
            setattr(user, sub_attr, provider_sub)
            await db.commit()
            await db.refresh(user)
            return user

    # 3. Create a fresh user. Apple may hide email via private relay or omit it on
    # subsequent sign-ins; in that case synthesize a placeholder.
    placeholder_email = email or f"{provider}_{provider_sub}@users.private"

    user = User(email=placeholder_email, password_hash=None)
    setattr(user, sub_attr, provider_sub)
    db.add(user)
    await db.flush()

    profile = UserProfile(user_id=user.id, name=name)
    db.add(profile)
    await db.commit()
    await db.refresh(user)
    return user
