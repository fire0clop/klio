import logging
from datetime import datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.database import AsyncSessionLocal

logger = logging.getLogger(__name__)

scheduler = AsyncIOScheduler(timezone="Europe/Moscow")


async def _nightly_insight_refresh() -> None:
    logger.info("Nightly insight refresh started at %s", datetime.now())
    from app.services.insight_service import refresh_insights_for_all_users
    from app.services.sphere_service import update_spheres_for_all_users

    async with AsyncSessionLocal() as db:
        try:
            count = await refresh_insights_for_all_users(db)
            logger.info("Nightly refresh complete: %d users updated", count)
        except Exception as e:
            logger.error("Nightly refresh failed: %s", e)
        try:
            sc = await update_spheres_for_all_users(db)
            logger.info("Nightly sphere update complete: %d users", sc)
        except Exception as e:
            logger.error("Nightly sphere update failed: %s", e)


def start_scheduler() -> None:
    scheduler.add_job(
        _nightly_insight_refresh,
        trigger=CronTrigger(hour=0, minute=5),
        id="nightly_insights",
        replace_existing=True,
    )
    scheduler.start()
    logger.info("Scheduler started — nightly insights at 00:05 MSK")


def stop_scheduler() -> None:
    scheduler.shutdown(wait=False)
