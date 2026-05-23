import uuid
from datetime import date
from typing import List, Optional

from pydantic import BaseModel


class StreakResponse(BaseModel):
    goal_id: uuid.UUID
    current_streak: int
    best_streak: int
    total_completed: int
    weekly_rate: float
    monthly_rate: float
    quarterly_rate: float


class EffectProgress(BaseModel):
    name: str
    icon: str
    current_percent: int
    description: str


class GoalEffectsResponse(BaseModel):
    goal_id: uuid.UUID
    title: str
    current_streak: int
    effects: List[EffectProgress]


class TimelineEntry(BaseModel):
    date: date
    completed: Optional[bool]
    is_planned: bool


class GoalTimelineResponse(BaseModel):
    goal_id: uuid.UUID
    entries: List[TimelineEntry]


class DailyLogPoint(BaseModel):
    date: date
    weight_kg: Optional[float]
    sleep_hours: Optional[float]
    energy: Optional[int]
    mood: Optional[int]


class DailyLogTimelineResponse(BaseModel):
    entries: List[DailyLogPoint]


class InsightResponse(BaseModel):
    id: uuid.UUID
    content: str
    kind: Optional[str] = None
    title: Optional[str] = None
    generated_at: str


class SphereResponse(BaseModel):
    icon: str
    name: str
    percent: int
    goals: List[str]
    caption: str = ""
