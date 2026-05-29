from fastapi import APIRouter

from app.api.v1 import analytics, auth, checkin, devices, goals, profile

router = APIRouter(prefix="/api/v1")

router.include_router(auth.router)
router.include_router(profile.router)
router.include_router(goals.router)
router.include_router(checkin.router)
router.include_router(analytics.router)
router.include_router(devices.router)
