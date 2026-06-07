"""spheres registry (AI-maintained development points) + goals.sphere_keys

Revision ID: 008
Revises: 007
Create Date: 2026-06-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "008"
down_revision: Union[str, None] = "007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "spheres",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("key", sa.String(40), nullable=False),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("icon", sa.String(40), nullable=False),
        sa.Column("value", sa.Float, nullable=False, server_default="0"),
        sa.Column("caption", sa.Text, nullable=True),
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "key", name="uq_sphere_user_key"),
    )
    op.add_column("goals", sa.Column("sphere_keys", sa.JSON, nullable=True))


def downgrade() -> None:
    op.drop_column("goals", "sphere_keys")
    op.drop_table("spheres")
