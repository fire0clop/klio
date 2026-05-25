import uuid
from datetime import date
from typing import Any, Dict, List, Optional

from pydantic import BaseModel


class GoalStartRequest(BaseModel):
    title: str


class GoalStartResponse(BaseModel):
    goal_id: uuid.UUID
    question: str
    question_index: int
    summary: Optional[str] = None


class GoalAnswerRequest(BaseModel):
    answer: str


class GoalAnswerResponse(BaseModel):
    done: bool
    question: Optional[str] = None
    question_index: Optional[int] = None
    summary: Optional[str] = None


class FrequencyConfig(BaseModel):
    type: str  # daily | every_n_days | weekdays | times_per_week
    value: Optional[Dict[str, Any]] = None


class GoalConfirmRequest(BaseModel):
    frequency: FrequencyConfig


class GoalAdaptRequest(BaseModel):
    action: str                       # accept | decline
    target: Optional[float] = None    # своё значение при accept


class GoalMetricSchema(BaseModel):
    id: uuid.UUID
    metric_name: str
    unit: str
    prompt: str

    model_config = {"from_attributes": True}


class EffectMilestone(BaseModel):
    day: int
    percent: int
    description: str


class Effect(BaseModel):
    name: str
    icon: str
    milestones: List[EffectMilestone]


class GoalResponse(BaseModel):
    id: uuid.UUID
    title: str
    goal_type: str = "binary"
    # Таксономия (docs/GOAL_DESIGN.md)
    horizon: str = "eternal"
    measure: str = "fact"
    direction: Optional[str] = None
    controllability: Optional[str] = None
    baseline: Optional[float] = None
    target: Optional[float] = None
    unit: Optional[str] = None
    growing: bool = False
    metric_has_ceiling: bool = False
    end_condition: Optional[str] = None
    horizon_days: Optional[int] = None
    ai_summary: Optional[str] = None
    frequency_type: str
    frequency_value: Optional[Dict[str, Any]]
    ai_effect_trajectory: Optional[Dict[str, Any]]
    dialog_complete: bool
    started_at: date
    is_active: bool
    current_streak: int = 0
    completion_rate: float = 0.0
    metrics: List[GoalMetricSchema] = []

    model_config = {"from_attributes": True}


class GoalDetailResponse(GoalResponse):
    ai_context: Optional[Dict[str, Any]]
