"""insights.kind + title (structured daily reactions)

Revision ID: 007
Revises: 006
Create Date: 2026-06-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "007"
down_revision: Union[str, None] = "006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("insights", sa.Column("kind", sa.String(20), nullable=True))
    op.add_column("insights", sa.Column("title", sa.String(120), nullable=True))


def downgrade() -> None:
    op.drop_column("insights", "title")
    op.drop_column("insights", "kind")
