"""goal_type, daily_plan, actual_value, date_of_birth

Revision ID: 002
Revises: 001
Create Date: 2026-05-19
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # UserProfile: заменяем age на date_of_birth
    op.add_column("user_profiles", sa.Column("date_of_birth", sa.Date, nullable=True))
    op.drop_column("user_profiles", "age")

    # Goal: добавляем goal_type и daily_plan
    op.add_column("goals", sa.Column("goal_type", sa.String(20), server_default="binary", nullable=False))
    op.add_column("goals", sa.Column("daily_plan", sa.dialects.postgresql.JSON, nullable=True))

    # GoalEntry: добавляем actual_value
    op.add_column("goal_entries", sa.Column("actual_value", sa.Float, nullable=True))


def downgrade() -> None:
    op.drop_column("goal_entries", "actual_value")
    op.drop_column("goals", "daily_plan")
    op.drop_column("goals", "goal_type")
    op.drop_column("user_profiles", "date_of_birth")
    op.add_column("user_profiles", sa.Column("age", sa.Integer, nullable=True))
