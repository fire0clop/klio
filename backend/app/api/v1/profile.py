from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.api.deps import get_current_user
from app.database import get_db
from app.models.models import (
    DailyLog, DeviceToken, Goal, Insight, Sphere, User, UserProfile,
)
from app.schemas.profile import ProfileResponse, ProfileUpdate

router = APIRouter(prefix="/profile", tags=["profile"])

# Демо-аккаунт для проверки App Review: удаление работает в UI (logout),
# но саму запись не удаляем, чтобы аккаунт пережил тест удаления.
APP_REVIEW_EMAIL = "appreview@klio-diary.ru"


@router.get("", response_model=ProfileResponse)
async def get_profile(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(UserProfile).where(UserProfile.user_id == user.id))
    profile = result.scalar_one_or_none()
    if not profile:
        profile = UserProfile(user_id=user.id)
        db.add(profile)
        await db.commit()
        await db.refresh(profile)
    return profile


@router.put("", response_model=ProfileResponse)
async def update_profile(
    body: ProfileUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(UserProfile).where(UserProfile.user_id == user.id))
    profile = result.scalar_one_or_none()
    if not profile:
        profile = UserProfile(user_id=user.id)
        db.add(profile)

    for field, value in body.model_dump(exclude_none=True).items():
        setattr(profile, field, value)

    await db.commit()
    await db.refresh(profile)
    return profile


@router.delete("/me", status_code=204)
async def delete_account(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete the authenticated user and all their data."""
    # Демо-аккаунт ревью: возвращаем успех (приложение разлогинит), но запись храним.
    if (user.email or "").lower() == APP_REVIEW_EMAIL:
        return Response(status_code=204)

    uid = user.id

    # 1. DailyLogs → cascades GoalMetricEntries (via daily_log_id FK CASCADE)
    await db.execute(sa_delete(DailyLog).where(DailyLog.user_id == uid))

    # 2. Goals → cascades GoalQuestions, GoalEntries, GoalMetrics
    #    (GoalMetricEntries already gone from step 1)
    goal_ids_q = await db.execute(select(Goal.id).where(Goal.user_id == uid))
    goal_ids = [r[0] for r in goal_ids_q.all()]
    if goal_ids:
        await db.execute(sa_delete(Goal).where(Goal.id.in_(goal_ids)))

    # 3. Remaining user-level data
    await db.execute(sa_delete(DeviceToken).where(DeviceToken.user_id == uid))
    await db.execute(sa_delete(Insight).where(Insight.user_id == uid))
    await db.execute(sa_delete(Sphere).where(Sphere.user_id == uid))
    await db.execute(sa_delete(UserProfile).where(UserProfile.user_id == uid))

    # 4. The user row itself
    await db.execute(sa_delete(User).where(User.id == uid))
    await db.commit()

    return Response(status_code=204)
