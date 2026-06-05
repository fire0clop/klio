"""goal taxonomy: horizon, measure, direction, controllability, baseline, target, ...

Revision ID: 004
Revises: 003
Create Date: 2026-06-02
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("goals", sa.Column("horizon", sa.String(20), server_default="eternal", nullable=False))
    op.add_column("goals", sa.Column("measure", sa.String(20), server_default="fact", nullable=False))
    op.add_column("goals", sa.Column("direction", sa.String(10), nullable=True))
    op.add_column("goals", sa.Column("controllability", sa.String(10), nullable=True))
    op.add_column("goals", sa.Column("baseline", sa.Float, nullable=True))
    op.add_column("goals", sa.Column("target", sa.Float, nullable=True))
    op.add_column("goals", sa.Column("unit", sa.String(50), nullable=True))
    op.add_column("goals", sa.Column("growing", sa.Boolean, server_default=sa.false(), nullable=False))
    op.add_column("goals", sa.Column("metric_has_ceiling", sa.Boolean, server_default=sa.false(), nullable=False))
    op.add_column("goals", sa.Column("end_condition", sa.Text, nullable=True))
    op.add_column("goals", sa.Column("horizon_days", sa.Integer, nullable=True))
    op.add_column("goals", sa.Column("ai_summary", sa.Text, nullable=True))


def downgrade() -> None:
    op.drop_column("goals", "ai_summary")
    op.drop_column("goals", "horizon_days")
    op.drop_column("goals", "end_condition")
    op.drop_column("goals", "metric_has_ceiling")
    op.drop_column("goals", "growing")
    op.drop_column("goals", "unit")
    op.drop_column("goals", "target")
    op.drop_column("goals", "baseline")
    op.drop_column("goals", "controllability")
    op.drop_column("goals", "direction")
    op.drop_column("goals", "measure")
    op.drop_column("goals", "horizon")
