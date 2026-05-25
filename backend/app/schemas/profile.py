from datetime import date
from typing import Optional
from pydantic import BaseModel


class ProfileUpdate(BaseModel):
    name: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    height_cm: Optional[float] = None
    weight_kg: Optional[float] = None
    language: Optional[str] = None
    onboarding_completed: Optional[bool] = None


class ProfileResponse(BaseModel):
    name: Optional[str]
    date_of_birth: Optional[date]
    gender: Optional[str]
    height_cm: Optional[float]
    weight_kg: Optional[float]
    language: str = "ru"
    onboarding_completed: bool

    model_config = {"from_attributes": True}
