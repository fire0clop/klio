"""initial schema

Revision ID: 001
Revises:
Create Date: 2026-05-19
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSON, UUID

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
    )

    op.create_table(
        "user_profiles",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), unique=True),
        sa.Column("name", sa.String(100)),
        sa.Column("age", sa.Integer),
        sa.Column("gender", sa.String(20)),
        sa.Column("height_cm", sa.Float),
        sa.Column("weight_kg", sa.Float),
        sa.Column("onboarding_completed", sa.Boolean, server_default="false"),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now()),
    )

    op.create_table(
        "goals",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("title", sa.Text, nullable=False),
        sa.Column("frequency_type", sa.String(30), server_default="daily"),
        sa.Column("frequency_value", JSON),
        sa.Column("ai_context", JSON),
        sa.Column("ai_effect_trajectory", JSON),
        sa.Column("ai_suggested_metrics", JSON),
        sa.Column("dialog_complete", sa.Boolean, server_default="false"),
        sa.Column("started_at", sa.Date, nullable=False),
        sa.Column("is_active", sa.Boolean, server_default="true"),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
    )

    op.create_table(
        "goal_questions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("goal_id", UUID(as_uuid=True), sa.ForeignKey("goals.id", ondelete="CASCADE")),
        sa.Column("question_text", sa.Text, nullable=False),
        sa.Column("answer_text", sa.Text),
        sa.Column("order_index", sa.Integer, nullable=False),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
    )

    op.create_table(
        "goal_entries",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("goal_id", UUID(as_uuid=True), sa.ForeignKey("goals.id", ondelete="CASCADE")),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("completed", sa.Boolean, server_default="false"),
        sa.Column("note", sa.Text),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
        sa.UniqueConstraint("goal_id", "date"),
    )

    op.create_table(
        "daily_logs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("weight_kg", sa.Float),
        sa.Column("sleep_hours", sa.Float),
        sa.Column("energy", sa.Integer),
        sa.Column("mood", sa.Integer),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "date"),
    )

    op.create_table(
        "goal_metrics",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("goal_id", UUID(as_uuid=True), sa.ForeignKey("goals.id", ondelete="CASCADE")),
        sa.Column("metric_name", sa.String(100), nullable=False),
        sa.Column("unit", sa.String(50), nullable=False),
        sa.Column("prompt", sa.Text, nullable=False),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
    )

    op.create_table(
        "goal_metric_entries",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("goal_metric_id", UUID(as_uuid=True), sa.ForeignKey("goal_metrics.id", ondelete="CASCADE")),
        sa.Column("daily_log_id", UUID(as_uuid=True), sa.ForeignKey("daily_logs.id", ondelete="CASCADE")),
        sa.Column("value", sa.String(100), nullable=False),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
        sa.UniqueConstraint("goal_metric_id", "daily_log_id"),
    )

    op.create_table(
        "device_tokens",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token", sa.String(500), nullable=False, unique=True),
        sa.Column("platform", sa.String(20), server_default="ios"),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
    )

    op.create_table(
        "insights",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("content", sa.Text, nullable=False),
        sa.Column("generated_at", sa.DateTime, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("insights")
    op.drop_table("device_tokens")
    op.drop_table("goal_metric_entries")
    op.drop_table("goal_metrics")
    op.drop_table("daily_logs")
    op.drop_table("goal_entries")
    op.drop_table("goal_questions")
    op.drop_table("goals")
    op.drop_table("user_profiles")
    op.drop_table("users")
