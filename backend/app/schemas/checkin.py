import uuid
from datetime import date
from typing import List, Optional

from pydantic import BaseModel


class GoalEntryInput(BaseModel):
    goal_id: uuid.UUID
    completed: bool
    confirmed: bool = False
    actual_value: Optional[float] = None  # для quantitative целей
    note: Optional[str] = None
    metrics: List["MetricEntryInput"] = []


class MetricEntryInput(BaseModel):
    goal_metric_id: uuid.UUID
    value: str


class DailyLogInput(BaseModel):
    weight_kg: Optional[float] = None
    sleep_hours: Optional[float] = None
    energy: Optional[int] = None
    mood: Optional[int] = None


class CheckInRequest(BaseModel):
    date: date
    entries: List[GoalEntryInput]
    daily_log: Optional[DailyLogInput] = None


class PlanStepInfo(BaseModel):
    day_number: int       # какой это день цели (с 1)
    limit: Optional[float]  # лимит на сегодня
    unit: Optional[str]   # единица измерения


class MetricItem(BaseModel):
    goal_metric_id: uuid.UUID
    metric_name: str
    unit: str
    prompt: str
    value_today: Optional[str]


class GoalSuggestion(BaseModel):
    kind: str                          # raise | switch_metric
    suggested_target: Optional[float] = None
    unit: Optional[str] = None
    message: str


class GoalCheckInItem(BaseModel):
    goal_id: uuid.UUID
    title: str
    goal_type: str          # binary | quantitative
    frequency_type: str
    icon: Optional[str] = None
    suggestion: Optional[GoalSuggestion] = None
    # таксономия — чтобы фронт выбирал тип контрола
    direction: Optional[str] = None        # up | down | target
    controllability: Optional[str] = None  # direct | indirect
    unit: Optional[str] = None
    baseline: Optional[float] = None
    target: Optional[float] = None
    current_streak: int
    completed_today: Optional[bool]
    confirmed_today: bool = False
    actual_value_today: Optional[float]   # для quantitative
    note: Optional[str]
    plan: Optional[PlanStepInfo]          # текущий шаг плана
    metrics: List[MetricItem]


class CheckInTodayResponse(BaseModel):
    date: date
    goals: List[GoalCheckInItem]
    daily_log: Optional[DailyLogInput]
    all_done: bool
