import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.database import get_db
from app.models.models import Goal, GoalQuestion, User, UserProfile
from app.schemas.goal import (
    GoalAdaptRequest,
    GoalAnswerRequest,
    GoalAnswerResponse,
    GoalConfirmRequest,
    GoalDetailResponse,
    GoalResponse,
    GoalStartRequest,
    GoalStartResponse,
)
from app.services.adapt_service import compute_suggestion
from app.services.ai_service import advance_goal_dialog
from app.services.sphere_service import assign_goal_spheres
from app.services.streak_service import calculate_completion_rate, calculate_streak

router = APIRouter(prefix="/goals", tags=["goals"])


async def _load_goal(goal_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession) -> Goal:
    result = await db.execute(
        select(Goal)
        .where(Goal.id == goal_id, Goal.user_id == user_id)
        .options(selectinload(Goal.questions), selectinload(Goal.entries), selectinload(Goal.metrics))
    )
    goal = result.scalar_one_or_none()
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    return goal


def _profile_dict(profile: UserProfile | None) -> dict | None:
    if not profile:
        return None
    return {
        "date_of_birth": str(profile.date_of_birth) if profile.date_of_birth else None,
        "gender": profile.gender,
        "weight_kg": profile.weight_kg,
    }


def _enrich(goal: Goal) -> dict:
    streak_data = calculate_streak(goal, goal.entries)
    rate_30d = calculate_completion_rate(goal, goal.entries, 30)
    return {
        **{c.key: getattr(goal, c.key) for c in goal.__table__.columns},
        "current_streak": streak_data["current_streak"],
        "completion_rate": rate_30d,
        "metrics": goal.metrics,
    }


@router.post("/start", response_model=GoalStartResponse, status_code=201)
async def start_goal(
    body: GoalStartRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    profile_result = await db.execute(select(UserProfile).where(UserProfile.user_id == user.id))
    profile = profile_result.scalar_one_or_none()

    result = await advance_goal_dialog(body.title, [], _profile_dict(profile), lang=(profile.language if profile else "ru"))

    goal = Goal(
        user_id=user.id,
        title=body.title,
        started_at=date.today(),
        frequency_type="daily",
    )
    db.add(goal)
    await db.flush()

    if result.get("status") == "ready":
        _save_structured_goal(goal, result.get("goal") or {}, qa_pairs=[])
        await assign_goal_spheres(user, goal, db)
        goal_id, summary = goal.id, goal.ai_summary
        await db.commit()
        return GoalStartResponse(
            goal_id=goal_id, question="", question_index=-1, summary=summary
        )

    q = GoalQuestion(goal_id=goal.id, question_text=result["question"], order_index=0)
    db.add(q)
    goal_id = goal.id
    await db.commit()
    return GoalStartResponse(goal_id=goal_id, question=result["question"], question_index=0)


@router.post("/{goal_id}/answer", response_model=GoalAnswerResponse)
async def answer_question(
    goal_id: uuid.UUID,
    body: GoalAnswerRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)

    if goal.dialog_complete:
        raise HTTPException(status_code=400, detail="Dialog already complete")

    unanswered = next((q for q in goal.questions if q.answer_text is None), None)
    if not unanswered:
        raise HTTPException(status_code=400, detail="No pending question")

    unanswered.answer_text = body.answer
    await db.flush()

    profile_result = await db.execute(select(UserProfile).where(UserProfile.user_id == user.id))
    profile = profile_result.scalar_one_or_none()

    qa_pairs = [{"question": q.question_text, "answer": q.answer_text} for q in goal.questions]
    result = await advance_goal_dialog(goal.title, qa_pairs, _profile_dict(profile), lang=(profile.language if profile else "ru"))

    if result.get("status") == "ready":
        _save_structured_goal(goal, result.get("goal") or {}, qa_pairs=qa_pairs)
        await assign_goal_spheres(user, goal, db)
        summary = goal.ai_summary
        await db.commit()
        return GoalAnswerResponse(done=True, summary=summary)

    next_q = GoalQuestion(
        goal_id=goal.id,
        question_text=result["question"],
        order_index=len(goal.questions),
    )
    db.add(next_q)
    await db.commit()

    return GoalAnswerResponse(done=False, question=result["question"], question_index=len(goal.questions))


@router.post("/{goal_id}/confirm")
async def confirm_goal(
    goal_id: uuid.UUID,
    body: GoalConfirmRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)

    goal.frequency_type = body.frequency.type
    goal.frequency_value = body.frequency.value

    await db.commit()
    return {"status": "ok"}


@router.get("", response_model=list[GoalResponse])
async def list_goals(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Goal)
        .where(Goal.user_id == user.id, Goal.is_active == True)
        .options(selectinload(Goal.entries), selectinload(Goal.metrics))
        .order_by(Goal.created_at)
    )
    goals = result.scalars().all()
    return [_enrich(g) for g in goals]


@router.get("/{goal_id}", response_model=GoalDetailResponse)
async def get_goal(
    goal_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)
    return {**_enrich(goal), "ai_context": goal.ai_context}


@router.post("/{goal_id}/adapt")
async def adapt_goal(
    goal_id: uuid.UUID,
    body: GoalAdaptRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)
    ctx = dict(goal.ai_context or {})

    if body.action == "accept":
        new_t = body.target
        if new_t is None:
            sugg = compute_suggestion(goal, goal.entries)
            new_t = sugg.get("suggested_target") if sugg else None
        if new_t is not None and new_t > 0:
            goal.target = float(new_t)
        ctx.pop("adapt_declined_target", None)
        ctx.pop("adapt_switch_dismissed_day", None)
    elif body.action == "decline":
        sugg = compute_suggestion(goal, goal.entries)
        if sugg and sugg["kind"] == "raise" and sugg.get("suggested_target") is not None:
            ctx["adapt_declined_target"] = sugg["suggested_target"]
        elif sugg and sugg["kind"] == "switch_metric":
            ctx["adapt_switch_dismissed_day"] = date.today().isoformat()

    goal.ai_context = ctx
    await db.commit()
    return {"status": "ok"}


@router.get("/{goal_id}/history")
async def goal_history(
    goal_id: uuid.UUID,
    days: int = 14,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from datetime import timedelta

    goal = await _load_goal(goal_id, user.id, db)
    days = max(1, min(days, 90))
    today = date.today()
    by_date = {e.date: e for e in goal.entries}
    out = []
    for i in range(days - 1, -1, -1):
        d = today - timedelta(days=i)
        e = by_date.get(d)
        out.append({
            "date": d.isoformat(),
            "completed": bool(e.completed) if e else False,
            "value": e.actual_value if e else None,
        })
    return out


@router.delete("/{goal_id}", status_code=204)
async def archive_goal(
    goal_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = await _load_goal(goal_id, user.id, db)
    goal.is_active = False
    await db.commit()


_CADENCE_TO_FREQUENCY = {"daily": "daily", "weekdays": "weekdays", "weekly": "times_per_week"}


def _save_structured_goal(goal: Goal, data: dict, qa_pairs: list[dict]) -> None:
    """Раскладывает структуру цели от ИИ по полям модели (см. docs/GOAL_DESIGN.md)."""
    goal.dialog_complete = True

    measure = data.get("measure", "fact")
    goal.measure = measure
    goal.horizon = data.get("horizon", "eternal")
    goal.direction = data.get("direction")
    goal.controllability = data.get("controllability")
    goal.baseline = data.get("baseline")
    goal.target = data.get("target")
    goal.unit = data.get("unit")
    goal.growing = bool(data.get("growing", False))
    goal.metric_has_ceiling = bool(data.get("metric_has_ceiling", False))
    goal.end_condition = data.get("end_condition")
    goal.horizon_days = data.get("horizon_days")
    goal.ai_summary = data.get("summary")
    goal.icon = data.get("icon")

    # Чистая формулировка, если ИИ её нормализовал
    if data.get("title"):
        goal.title = data["title"]

    # Обратная совместимость со старой аналитикой/трекингом
    goal.goal_type = "quantitative" if measure == "quantitative" else "binary"

    cadence = data.get("cadence", "daily")
    goal.frequency_type = _CADENCE_TO_FREQUENCY.get(cadence, "daily")

    goal.ai_effect_trajectory = {"effects": data.get("effects", [])}
    goal.daily_plan = []  # дневная цель теперь считается от факта, не зашивается заранее
    goal.ai_context = {"qa": qa_pairs, "goal": data}
