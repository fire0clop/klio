from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.database import get_db
from app.models.models import DailyLog, Goal, GoalEntry, GoalMetricEntry, User
from app.schemas.checkin import (
    CheckInRequest,
    CheckInTodayResponse,
    DailyLogInput,
    GoalCheckInItem,
    GoalSuggestion,
)
from app.services.adapt_service import compute_suggestion
from app.services.goal_schedule import is_planned_day
from app.services.plan_service import get_today_plan
from app.services.streak_service import calculate_streak

router = APIRouter(prefix="/checkin", tags=["checkin"])


async def _build_checkin(target_date: date, user: User, db: AsyncSession) -> CheckInTodayResponse:
    goals_result = await db.execute(
        select(Goal)
        .where(Goal.user_id == user.id, Goal.is_active == True)
        .options(selectinload(Goal.entries), selectinload(Goal.metrics))
    )
    goals = goals_result.scalars().all()

    log_result = await db.execute(
        select(DailyLog).where(DailyLog.user_id == user.id, DailyLog.date == target_date)
    )
    log = log_result.scalar_one_or_none()

    items = []
    for goal in goals:
        if not is_planned_day(goal, target_date):
            continue

        day_entry = next((e for e in goal.entries if e.date == target_date), None)
        streak_data = calculate_streak(goal, goal.entries)
        plan_info = get_today_plan(goal, target_date)
        sugg = compute_suggestion(goal, goal.entries) if target_date == date.today() else None

        items.append(GoalCheckInItem(
            goal_id=goal.id,
            title=goal.title,
            goal_type=goal.goal_type,
            frequency_type=goal.frequency_type,
            icon=goal.icon,
            suggestion=GoalSuggestion(**sugg) if sugg else None,
            direction=goal.direction,
            controllability=goal.controllability,
            unit=goal.unit,
            baseline=goal.baseline,
            target=goal.target,
            current_streak=streak_data["current_streak"],
            completed_today=day_entry.completed if day_entry else None,
            confirmed_today=day_entry.confirmed if day_entry else False,
            actual_value_today=day_entry.actual_value if day_entry else None,
            note=day_entry.note if day_entry else None,
            plan=plan_info,
            metrics=[],
        ))

    all_done = all(item.completed_today for item in items) and len(items) > 0

    return CheckInTodayResponse(
        date=target_date,
        goals=items,
        daily_log=DailyLogInput(
            weight_kg=log.weight_kg if log else None,
            sleep_hours=log.sleep_hours if log else None,
            energy=log.energy if log else None,
            mood=log.mood if log else None,
        ) if log else None,
        all_done=all_done,
    )


@router.get("/today", response_model=CheckInTodayResponse)
async def get_today(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await _build_checkin(date.today(), user, db)


@router.get("/{checkin_date}", response_model=CheckInTodayResponse)
async def get_day(
    checkin_date: date,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if checkin_date > date.today():
        raise HTTPException(status_code=400, detail="Cannot view future dates")
    return await _build_checkin(checkin_date, user, db)


@router.post("")
async def save_checkin(
    body: CheckInRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    log_result = await db.execute(
        select(DailyLog).where(DailyLog.user_id == user.id, DailyLog.date == body.date)
    )
    log = log_result.scalar_one_or_none()

    if body.daily_log:
        if log:
            for field, value in body.daily_log.model_dump(exclude_none=True).items():
                setattr(log, field, value)
        else:
            log = DailyLog(user_id=user.id, date=body.date, **body.daily_log.model_dump(exclude_none=True))
            db.add(log)
        await db.flush()

    for entry_input in body.entries:
        goal_result = await db.execute(
            select(Goal).where(Goal.id == entry_input.goal_id, Goal.user_id == user.id)
        )
        goal = goal_result.scalar_one_or_none()
        if not goal:
            continue

        if not is_planned_day(goal, body.date):
            raise HTTPException(status_code=400, detail=f"Goal {goal.id} not planned for {body.date}")

        # Для quantitative: определяем completed по цели с учётом направления
        completed = entry_input.completed
        if goal.goal_type == "quantitative" and entry_input.actual_value is not None:
            plan = get_today_plan(goal, body.date)
            if plan and plan.limit is not None:
                if goal.direction == "up":
                    completed = entry_input.actual_value >= plan.limit  # надо набрать
                else:
                    completed = entry_input.actual_value <= plan.limit  # down/target: не больше
            else:
                completed = True  # цели-числа нет — засчитываем факт

        entry_result = await db.execute(
            select(GoalEntry).where(GoalEntry.goal_id == goal.id, GoalEntry.date == body.date)
        )
        entry = entry_result.scalar_one_or_none()

        if entry:
            entry.completed = completed
            entry.confirmed = entry_input.confirmed
            entry.actual_value = entry_input.actual_value
            entry.note = entry_input.note
        else:
            entry = GoalEntry(
                goal_id=goal.id,
                date=body.date,
                completed=completed,
                confirmed=entry_input.confirmed,
                actual_value=entry_input.actual_value,
                note=entry_input.note,
            )
            db.add(entry)

        if log and entry_input.metrics:
            await db.flush()
            for metric_input in entry_input.metrics:
                me_result = await db.execute(
                    select(GoalMetricEntry).where(
                        GoalMetricEntry.goal_metric_id == metric_input.goal_metric_id,
                        GoalMetricEntry.daily_log_id == log.id,
                    )
                )
                me = me_result.scalar_one_or_none()
                if me:
                    me.value = metric_input.value
                else:
                    db.add(GoalMetricEntry(
                        goal_metric_id=metric_input.goal_metric_id,
                        daily_log_id=log.id,
                        value=metric_input.value,
                    ))

    await db.commit()
    return {"status": "ok", "date": str(body.date)}
