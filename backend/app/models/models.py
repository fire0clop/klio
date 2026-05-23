import uuid
from datetime import date, datetime
from typing import List, Optional

from sqlalchemy import (
    Boolean, Date, DateTime, Float, ForeignKey,
    Integer, String, Text, UniqueConstraint, func,
)
from sqlalchemy.dialects.postgresql import JSON, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    # Nullable: social-only users (Apple/Google) have no password.
    password_hash: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    # Social-auth provider identifiers (Apple "sub" claim, Google "sub" claim).
    apple_sub: Mapped[Optional[str]] = mapped_column(String(255), unique=True, nullable=True)
    google_sub: Mapped[Optional[str]] = mapped_column(String(255), unique=True, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    profile: Mapped[Optional["UserProfile"]] = relationship(back_populates="user", uselist=False)
    goals: Mapped[List["Goal"]] = relationship(back_populates="user")
    daily_logs: Mapped[List["DailyLog"]] = relationship(back_populates="user")
    device_tokens: Mapped[List["DeviceToken"]] = relationship(back_populates="user")
    insights: Mapped[List["Insight"]] = relationship(back_populates="user")
    spheres: Mapped[List["Sphere"]] = relationship(back_populates="user")


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True)
    name: Mapped[Optional[str]] = mapped_column(String(100))
    date_of_birth: Mapped[Optional[date]] = mapped_column(Date)
    gender: Mapped[Optional[str]] = mapped_column(String(20))
    height_cm: Mapped[Optional[float]] = mapped_column(Float)
    weight_kg: Mapped[Optional[float]] = mapped_column(Float)
    language: Mapped[str] = mapped_column(String(5), default="ru", server_default="ru")
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    user: Mapped["User"] = relationship(back_populates="profile")


class Goal(Base):
    __tablename__ = "goals"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(Text, nullable=False)

    # daily | every_n_days | weekdays | times_per_week
    frequency_type: Mapped[str] = mapped_column(String(30), default="daily")
    # {"n": 2} | {"days": [0,2,4]} | {"times": 3} | null
    frequency_value: Mapped[Optional[dict]] = mapped_column(JSON)

    # Тип: binary (сделал/не сделал) | quantitative (есть лимит и факт)
    # Сохраняется для обратной совместимости; выводится из measure.
    goal_type: Mapped[str] = mapped_column(String(20), default="binary")

    # --- Таксономия цели (docs/GOAL_DESIGN.md) ---
    # horizon: eternal (вечная) | situational (ситуативная, с конечной точкой)
    horizon: Mapped[str] = mapped_column(String(20), default="eternal")
    # measure: fact (сделал/не сделал) | quantitative (числовая метрика)
    measure: Mapped[str] = mapped_column(String(20), default="fact")
    # direction (только quantitative): up | down | target
    direction: Mapped[Optional[str]] = mapped_column(String(10))
    # controllability (только quantitative): direct | indirect
    controllability: Mapped[Optional[str]] = mapped_column(String(10))
    # стартовая точка и цель (числовые)
    baseline: Mapped[Optional[float]] = mapped_column(Float)
    target: Mapped[Optional[float]] = mapped_column(Float)
    unit: Mapped[Optional[str]] = mapped_column(String(50))
    # имеет ли смысл наращивать метрику + есть ли у неё смысловой предел
    growing: Mapped[bool] = mapped_column(Boolean, default=False)
    metric_has_ceiling: Mapped[bool] = mapped_column(Boolean, default=False)
    # для ситуативных: условие окончания + реалистичный горизонт в днях
    end_condition: Mapped[Optional[str]] = mapped_column(Text)
    horizon_days: Mapped[Optional[int]] = mapped_column(Integer)
    # человекочитаемое резюме того, что ИИ понял
    ai_summary: Mapped[Optional[str]] = mapped_column(Text)
    # SF Symbol, выбранный ИИ при создании цели
    icon: Mapped[Optional[str]] = mapped_column(String(60))

    # Весь контекст диалога и сгенерированные AI данные
    ai_context: Mapped[Optional[dict]] = mapped_column(JSON)
    ai_effect_trajectory: Mapped[Optional[dict]] = mapped_column(JSON)
    ai_suggested_metrics: Mapped[Optional[list]] = mapped_column(JSON)
    # Ключи сфер развития, на которые влияет цель (реестр spheres)
    sphere_keys: Mapped[Optional[list]] = mapped_column(JSON)
    # Устаревшее: заранее зашитая лесенка. Новая логика считает дневную цель от факта.
    daily_plan: Mapped[Optional[list]] = mapped_column(JSON)

    dialog_complete: Mapped[bool] = mapped_column(Boolean, default=False)
    started_at: Mapped[date] = mapped_column(Date)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="goals")
    questions: Mapped[List["GoalQuestion"]] = relationship(back_populates="goal", order_by="GoalQuestion.order_index")
    entries: Mapped[List["GoalEntry"]] = relationship(back_populates="goal")
    metrics: Mapped[List["GoalMetric"]] = relationship(back_populates="goal")


class GoalQuestion(Base):
    __tablename__ = "goal_questions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    goal_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("goals.id", ondelete="CASCADE"))
    question_text: Mapped[str] = mapped_column(Text)
    answer_text: Mapped[Optional[str]] = mapped_column(Text)
    order_index: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    goal: Mapped["Goal"] = relationship(back_populates="questions")


class GoalEntry(Base):
    __tablename__ = "goal_entries"
    __table_args__ = (UniqueConstraint("goal_id", "date"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    goal_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("goals.id", ondelete="CASCADE"))
    date: Mapped[date] = mapped_column(Date)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    # Пользователь явно зафиксировал день (для quantitative «готово на сегодня»)
    confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    actual_value: Mapped[Optional[float]] = mapped_column(Float)  # для quantitative целей
    note: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    goal: Mapped["Goal"] = relationship(back_populates="entries")


class DailyLog(Base):
    __tablename__ = "daily_logs"
    __table_args__ = (UniqueConstraint("user_id", "date"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    date: Mapped[date] = mapped_column(Date)
    weight_kg: Mapped[Optional[float]] = mapped_column(Float)
    sleep_hours: Mapped[Optional[float]] = mapped_column(Float)
    energy: Mapped[Optional[int]] = mapped_column(Integer)
    mood: Mapped[Optional[int]] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="daily_logs")
    metric_entries: Mapped[List["GoalMetricEntry"]] = relationship(back_populates="daily_log")


class GoalMetric(Base):
    __tablename__ = "goal_metrics"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    goal_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("goals.id", ondelete="CASCADE"))
    metric_name: Mapped[str] = mapped_column(String(100))
    unit: Mapped[str] = mapped_column(String(50))
    prompt: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    goal: Mapped["Goal"] = relationship(back_populates="metrics")
    entries: Mapped[List["GoalMetricEntry"]] = relationship(back_populates="metric")


class GoalMetricEntry(Base):
    __tablename__ = "goal_metric_entries"
    __table_args__ = (UniqueConstraint("goal_metric_id", "daily_log_id"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    goal_metric_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("goal_metrics.id", ondelete="CASCADE"))
    daily_log_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("daily_logs.id", ondelete="CASCADE"))
    value: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    metric: Mapped["GoalMetric"] = relationship(back_populates="entries")
    daily_log: Mapped["DailyLog"] = relationship(back_populates="metric_entries")


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    token: Mapped[str] = mapped_column(String(500), unique=True)
    platform: Mapped[str] = mapped_column(String(20), default="ios")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="device_tokens")


class Insight(Base):
    __tablename__ = "insights"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    content: Mapped[str] = mapped_column(Text)
    kind: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    title: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    generated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="insights")


class Sphere(Base):
    """Сфера развития человека (лёгкие, ум, энергия…), значение ведёт ИИ."""
    __tablename__ = "spheres"
    __table_args__ = (UniqueConstraint("user_id", "key", name="uq_sphere_user_key"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    key: Mapped[str] = mapped_column(String(40))
    name: Mapped[str] = mapped_column(String(80))
    icon: Mapped[str] = mapped_column(String(40))
    value: Mapped[float] = mapped_column(Float, default=0)
    caption: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="spheres")
