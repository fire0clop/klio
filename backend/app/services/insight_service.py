from datetime import date, timedelta
from statistics import mean
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload

from app.models.models import DailyLog, Goal, Insight, User
from app.services.ai_service import generate_daily_reactions
from app.services.streak_service import calculate_streak, calculate_completion_rate

_WEEKDAYS_RU = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]
_KIND_ORDER = {"reaction": 0, "win": 1, "trend": 2, "watch": 3, "tip": 4}


async def build_user_data_snapshot(user: User, db: AsyncSession) -> dict:
    today = date.today()
    month_ago = today - timedelta(days=30)

    logs_result = await db.execute(
        select(DailyLog)
        .where(DailyLog.user_id == user.id, DailyLog.date >= month_ago)
        .order_by(DailyLog.date)
    )
    logs = logs_result.scalars().all()

    goals_result = await db.execute(
        select(Goal)
        .where(Goal.user_id == user.id, Goal.is_active == True)
        .options(selectinload(Goal.entries))
    )
    goals = goals_result.scalars().all()

    if not goals:
        return {}

    goal_summaries = []
    for g in goals:
        recent_entries = [e for e in g.entries if e.date >= month_ago]
        completed_dates = sorted({e.date for e in recent_entries if e.completed})
        streak_data = calculate_streak(g, g.entries)
        rate_30 = calculate_completion_rate(g, g.entries, 30)
        goal_summaries.append({
            "title": g.title,
            "goal_type": g.goal_type,
            "days_active": (today - g.started_at).days + 1,
            "current_streak": streak_data["current_streak"],
            "best_streak": streak_data["best_streak"],
            "completion_rate_30d": round(rate_30 * 100),
            "completed_days": len(completed_dates),
        })

    energy_full, energy_partial = [], []
    total_goals = len(goals)
    for log in logs:
        if log.energy is None:
            continue
        done_count = sum(
            1 for g in goals
            if any(e.date == log.date and e.completed for e in g.entries)
        )
        if total_goals > 0 and done_count == total_goals:
            energy_full.append(log.energy)
        else:
            energy_partial.append(log.energy)

    weights = [log.weight_kg for log in logs if log.weight_kg]
    profile = user.profile

    # Реакция на ВЧЕРАШНИЙ день: что выполнено/пропущено по каждой цели.
    yesterday = today - timedelta(days=1)
    yest_per_goal, yest_done = [], 0
    for g in goals:
        ent = next((e for e in g.entries if e.date == yesterday), None)
        if ent is None:
            status = "no_data"
        elif ent.completed:
            status = "done"; yest_done += 1
        else:
            status = "missed"
        yest_per_goal.append({
            "title": g.title,
            "status": status,
            "value": ent.actual_value if ent else None,
        })

    return {
        "profile": {
            "date_of_birth": str(profile.date_of_birth) if profile and profile.date_of_birth else None,
            "gender": profile.gender if profile else None,
            "weight_kg": profile.weight_kg if profile else None,
        },
        "today_weekday": _WEEKDAYS_RU[today.weekday()],
        "yesterday": {
            "date": str(yesterday),
            "weekday": _WEEKDAYS_RU[yesterday.weekday()],
            "goals_done": yest_done,
            "goals_total": total_goals,
            "per_goal": yest_per_goal,
        },
        "goals": goal_summaries,
        "daily_logs_count": len(logs),
        "avg_energy_all_goals_done": round(mean(energy_full), 1) if energy_full else None,
        "avg_energy_partial": round(mean(energy_partial), 1) if energy_partial else None,
        "weight_start": weights[0] if weights else None,
        "weight_latest": weights[-1] if weights else None,
    }


async def refresh_insights(user: User, db: AsyncSession) -> list[Insight]:
    snapshot = await build_user_data_snapshot(user, db)
    if not snapshot or not snapshot.get("goals"):
        return []

    lang = user.profile.language if user.profile else "ru"
    items = await generate_daily_reactions(snapshot, lang=lang)
    if not items:
        return []

    new_insights = [
        Insight(user_id=user.id, kind=it["kind"], title=it["title"], content=it["text"])
        for it in items
    ]
    for ins in new_insights:
        db.add(ins)
    await db.commit()
    return _sorted_batch(new_insights)


def _sorted_batch(rows: list[Insight]) -> list[Insight]:
    return sorted(rows, key=lambda r: _KIND_ORDER.get((r.kind or "tip"), 9))


async def get_latest_insights(user_id, db: AsyncSession) -> list[Insight]:
    """Возвращает самую свежую пачку инсайтов (за последний день генерации)."""
    result = await db.execute(
        select(Insight)
        .where(Insight.user_id == user_id)
        .order_by(Insight.generated_at.desc())
        .limit(20)
    )
    rows = result.scalars().all()
    if not rows:
        return []
    # Одна пачка пишется одним коммитом — таймстемпы в пределах секунд. Берём только
    # самую свежую пачку (окно 2 минуты), чтобы не смешивать с прошлыми генерациями.
    latest = rows[0].generated_at
    cutoff = latest - timedelta(minutes=2)
    return _sorted_batch([r for r in rows if r.generated_at >= cutoff])


async def ensure_today_insights(user: User, db: AsyncSession) -> list[Insight]:
    """Свежие реакции на сегодня: если пачки за сегодня ещё нет — генерируем."""
    batch = await get_latest_insights(user.id, db)
    if batch and batch[0].generated_at.date() == date.today():
        return batch
    new = await refresh_insights(user, db)
    return new if new else batch


async def refresh_insights_for_all_users(db: AsyncSession) -> int:
    """Вызывается планировщиком в полночь."""
    result = await db.execute(
        select(User).options(
            selectinload(User.profile),
            selectinload(User.goals).selectinload(Goal.entries),
        )
    )
    users = result.scalars().all()

    refreshed = 0
    for user in users:
        if not user.goals:
            continue
        try:
            insights = await refresh_insights(user, db)
            if insights:
                refreshed += 1
        except Exception:
            pass

    return refreshed
