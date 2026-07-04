"""Реестр «сфер развития» человека, значения которого ведёт ИИ.

При создании цель привязывается к существующим/новым сферам (assign). Раз в день
ИИ пересчитывает значения сфер по реальному поведению пользователя (стабильность →
рост, срывы → откат), опираясь на доменное знание, а не на формулу в коде.
"""
from datetime import date, datetime
from typing import List

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.models.models import Goal, Sphere, User, UserProfile
from app.services.ai_service import assign_spheres, compute_sphere_updates
from app.services.streak_service import calculate_completion_rate, calculate_streak


async def _user_language(user_id, db: AsyncSession) -> str:
    """Язык профиля явным запросом: обращение к user.profile здесь — это
    ленивый sync-load в async-сессии (MissingGreenlet), который раньше молча
    гасился try/except вокруг ИИ-вызова и отключал всю логику сфер."""
    res = await db.execute(
        select(UserProfile.language).where(UserProfile.user_id == user_id)
    )
    return res.scalar_one_or_none() or "ru"


def _goal_adherence(goal: Goal, today: date) -> dict:
    entries = goal.entries
    streak = calculate_streak(goal, entries)["current_streak"]
    rate30 = round(calculate_completion_rate(goal, entries, 30) * 100)
    done7 = sum(1 for e in entries if (today - e.date).days < 7 and e.completed)
    missed = sorted({e.date for e in entries if not e.completed})
    return {
        "title": goal.title,
        "days_active": (today - goal.started_at).days + 1,
        "current_streak": streak,
        "done_last_7": done7,
        "rate_30d": rate30,
        "days_since_last_miss": (today - missed[-1]).days if missed else None,
    }


async def _existing_spheres(user_id, db: AsyncSession) -> list[Sphere]:
    res = await db.execute(select(Sphere).where(Sphere.user_id == user_id))
    return list(res.scalars().all())


async def assign_goal_spheres(user: User, goal: Goal, db: AsyncSession) -> None:
    """Спрашивает у ИИ, на какие сферы влияет цель; создаёт новые при необходимости."""
    existing = await _existing_spheres(user.id, db)
    existing_list = [{"key": s.key, "name": s.name, "icon": s.icon} for s in existing]
    goal_info = {
        "title": goal.title,
        "measure": goal.measure,
        "direction": goal.direction,
        "summary": goal.ai_summary,
        "end_condition": goal.end_condition,
    }
    lang = await _user_language(user.id, db)
    try:
        assigned = await assign_spheres(goal_info, existing_list, lang=lang)
    except Exception:
        assigned = []

    existing_keys = {s.key for s in existing}
    keys: list[str] = []
    for a in assigned:
        keys.append(a["key"])
        if a["key"] not in existing_keys:
            db.add(Sphere(user_id=user.id, key=a["key"], name=a["name"], icon=a["icon"], value=0))
            existing_keys.add(a["key"])
    goal.sphere_keys = keys


async def ensure_assignments(user: User, goals: List[Goal], db: AsyncSession) -> bool:
    changed = False
    for g in goals:
        if g.sphere_keys is None:
            await assign_goal_spheres(user, g, db)
            changed = True
    if changed:
        await db.flush()
    return changed


async def update_spheres(user: User, goals: List[Goal], db: AsyncSession) -> None:
    """Ежедневный ИИ-пересчёт значений всех сфер пользователя."""
    await ensure_assignments(user, goals, db)
    spheres = await _existing_spheres(user.id, db)
    if not spheres:
        return

    today = date.today()
    contrib: dict[str, list[Goal]] = {s.key: [] for s in spheres}
    for g in goals:
        for k in (g.sphere_keys or []):
            if k in contrib:
                contrib[k].append(g)

    payload = [{
        "key": s.key,
        "name": s.name,
        "current_value": round(s.value),
        "goals": [_goal_adherence(g, today) for g in contrib.get(s.key, [])],
    } for s in spheres]

    lang = await _user_language(user.id, db)
    try:
        updates = await compute_sphere_updates(payload, lang=lang)
    except Exception:
        updates = []
    by_key = {u["key"]: u for u in updates}

    now = datetime.utcnow()
    for s in spheres:
        u = by_key.get(s.key)
        if u:
            s.value = u["value"]
            if u["caption"]:
                s.caption = u["caption"]
        s.updated_at = now  # помечаем обработанной за сегодня
    await db.commit()


async def ensure_today_spheres(user: User, goals: List[Goal], db: AsyncSession) -> None:
    spheres = await _existing_spheres(user.id, db)
    unassigned = any(g.sphere_keys is None for g in goals)
    stale = (not spheres and bool(goals)) or any(
        s.updated_at is not None and s.updated_at.date() < date.today() for s in spheres
    )
    if unassigned or stale:
        await update_spheres(user, goals, db)


async def update_spheres_for_all_users(db: AsyncSession) -> int:
    """Ночной пересчёт сфер для всех пользователей (вызывается планировщиком)."""
    from sqlalchemy.orm import selectinload
    res = await db.execute(
        select(User).options(selectinload(User.goals).selectinload(Goal.entries))
    )
    users = res.scalars().all()
    updated = 0
    for user in users:
        active = [g for g in user.goals if g.is_active]
        if not active:
            continue
        try:
            await update_spheres(user, active, db)
            updated += 1
        except Exception:
            pass
    return updated


async def get_spheres_payload(user: User, goals: List[Goal], db: AsyncSession) -> list[dict]:
    res = await db.execute(
        select(Sphere).where(Sphere.user_id == user.id).order_by(Sphere.value.desc())
    )
    spheres = res.scalars().all()
    contrib: dict[str, list[str]] = {}
    for g in goals:
        for k in (g.sphere_keys or []):
            contrib.setdefault(k, []).append(g.title)
    return [{
        "icon": s.icon,
        "name": s.name,
        "percent": round(s.value),
        "goals": contrib.get(s.key, []),
        "caption": s.caption or "",
    } for s in spheres]
