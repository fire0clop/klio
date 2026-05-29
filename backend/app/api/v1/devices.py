from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.api.deps import get_current_user
from app.database import get_db
from app.models.models import DeviceToken, User
from pydantic import BaseModel

router = APIRouter(prefix="/devices", tags=["devices"])


class TokenRegisterRequest(BaseModel):
    token: str
    platform: str = "ios"


@router.post("/token", status_code=201)
async def register_token(
    body: TokenRegisterRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(DeviceToken).where(DeviceToken.token == body.token))
    existing = result.scalar_one_or_none()

    if not existing:
        db.add(DeviceToken(user_id=user.id, token=body.token, platform=body.platform))
        await db.commit()

    return {"status": "ok"}
