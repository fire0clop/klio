import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.database import get_db
from app.models.models import DailyLog, Goal, User
from app.schemas.analytics import (
    DailyLogPoint,
    DailyLogTimelineResponse,
    EffectProgress,
    GoalEffectsResponse,
    GoalTimelineResponse,
    InsightResponse,
    SphereResponse,
    StreakResponse,
    TimelineEntry,
)
from app.services.goal_schedule import get_planned_days, is_planned_day
from app.services.insight_service import ensure_today_insights, get_latest_insights, refresh_insights
from app.services.sphere_service import ensure_today_spheres, get_spheres_payload
from app.services.streak_service import (
    calculate_completion_rate,
    calculate_effect_percent,
    calculate_streak,
)

router = APIRouter(prefix="/analytics", tags=["analytics"])


async def _load_goal(goal_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession) -> Goal:
    result = await db.execute(
        select(Goal)
        .where(Goal.id == goal_id, Goal.user_id == user_id)
        .options(selectinload(Goal.entries))
    )
    goal = result.scalar_one_or_none()
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    return goal


@router.get("/goals/{goal_id}/streak", response_model=StreakResponse)
async def goal_streak(
    goal_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)
    data = calculate_streak(goal, goal.entries)
    return StreakResponse(
        goal_id=goal_id,
        current_streak=data["current_streak"],
        best_streak=data["best_streak"],
        total_completed=data["total_completed"],
        weekly_rate=calculate_completion_rate(goal, goal.entries, 7),
        monthly_rate=calculate_completion_rate(goal, goal.entries, 30),
        quarterly_rate=calculate_completion_rate(goal, goal.entries, 90),
    )


@router.get("/goals/{goal_id}/effects", response_model=GoalEffectsResponse)
async def goal_effects(
    goal_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)
    streak_data = calculate_streak(goal, goal.entries)
    streak = streak_data["current_streak"]

    trajectory = goal.ai_effect_trajectory or {}
    effects_out = []

    for effect in trajectory.get("effects", []):
        milestones = sorted(effect.get("milestones", []), key=lambda m: m["day"])
        current_pct = 0
        current_desc = ""

        for m in milestones:
            if streak >= m["day"]:
                current_pct = m["percent"]
                current_desc = m["description"]
            else:
                if current_pct == 0 and milestones:
                    progress = streak / m["day"] if m["day"] > 0 else 0
                    current_pct = int(progress * m["percent"])
                    current_desc = m["description"]
                break

        effects_out.append(EffectProgress(
            name=effect["name"],
            icon=effect.get("icon", ""),
            current_percent=current_pct,
            description=current_desc,
        ))

    return GoalEffectsResponse(
        goal_id=goal_id,
        title=goal.title,
        current_streak=streak,
        effects=effects_out,
    )


@router.get("/goals/{goal_id}/timeline", response_model=GoalTimelineResponse)
async def goal_timeline(
    goal_id: uuid.UUID,
    days: int = 90,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)
    today = date.today()
    start = today - timedelta(days=days - 1)
    planned = set(get_planned_days(goal, max(start, goal.started_at), today))
    by_date = {e.date: e.completed for e in goal.entries}

    entries = []
    current = max(start, goal.started_at)
    while current <= today:
        is_planned = current in planned
        entries.append(TimelineEntry(
            date=current,
            completed=by_date.get(current) if is_planned else None,
            is_planned=is_planned,
        ))
        current += timedelta(days=1)

    return GoalTimelineResponse(goal_id=goal_id, entries=entries)


@router.get("/daily-log/timeline", response_model=DailyLogTimelineResponse)
async def daily_log_timeline(
    days: int = 30,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    today = date.today()
    start = today - timedelta(days=days - 1)

    result = await db.execute(
        select(DailyLog)
        .where(DailyLog.user_id == user.id, DailyLog.date >= start)
        .order_by(DailyLog.date)
    )
    logs = result.scalars().all()

    return DailyLogTimelineResponse(entries=[
        DailyLogPoint(
            date=log.date,
            weight_kg=log.weight_kg,
            sleep_hours=log.sleep_hours,
            energy=log.energy,
            mood=log.mood,
        )
        for log in logs
    ])


@router.get("/insights", response_model=list[InsightResponse])
async def get_insights(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Подгружаем профиль/цели/записи и при необходимости генерируем свежую пачку на сегодня.
    result = await db.execute(
        select(User)
        .where(User.id == user.id)
        .options(
            selectinload(User.profile),
            selectinload(User.goals).selectinload(Goal.entries),
        )
    )
    user_full = result.scalar_one()
    insights = await ensure_today_insights(user_full, db)
    return [
        InsightResponse(
            id=i.id,
            kind=i.kind,
            title=i.title,
            content=i.content,
            generated_at=i.generated_at.isoformat(),
        )
        for i in insights
    ]


@router.get("/spheres", response_model=list[SphereResponse])
async def get_spheres(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Сферы/навыки человека: ИИ-ведомый реестр, обновляется ежедневно."""
    result = await db.execute(
        select(Goal)
        .where(Goal.user_id == user.id, Goal.is_active == True)
        .options(selectinload(Goal.entries))
    )
    goals = list(result.scalars().all())
    await ensure_today_spheres(user, goals, db)
    payload = await get_spheres_payload(user, goals, db)
    return [SphereResponse(**s) for s in payload]


@router.get("/insights/status")
async def insights_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Возвращает время последней генерации инсайтов для этого пользователя."""
    insights = await get_latest_insights(user.id, db)
    if not insights:
        return {"has_insights": False, "last_updated": None}
    latest = max(i.generated_at for i in insights)
    return {"has_insights": True, "last_updated": latest.isoformat()}


@router.post("/insights/refresh", response_model=list[InsightResponse])
async def force_refresh_insights(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy.orm import selectinload
    result = await db.execute(
        select(User)
        .where(User.id == user.id)
        .options(selectinload(User.profile))
    )
    user_full = result.scalar_one()

    insights = await refresh_insights(user_full, db)
    return [
        InsightResponse(
            id=i.id,
            kind=i.kind,
            title=i.title,
            content=i.content,
            generated_at=i.generated_at.isoformat(),
        )
        for i in insights
    ]
