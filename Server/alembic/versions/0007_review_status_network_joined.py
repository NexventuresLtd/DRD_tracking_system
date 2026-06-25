"""Add review_status to routes/zones, network_joined to users

Revision ID: 0007
Revises: 0006
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade():
    # users: network_joined flag (existing users are already on the network)
    op.add_column("users", sa.Column("network_joined", sa.Boolean(), nullable=False, server_default="true"))

    # routes: review workflow
    op.add_column("routes", sa.Column("review_status", sa.String(20), nullable=False, server_default="approved"))

    # zones: review workflow
    op.add_column("zones", sa.Column("review_status", sa.String(20), nullable=False, server_default="approved"))


def downgrade():
    op.drop_column("users", "network_joined")
    op.drop_column("routes", "review_status")
    op.drop_column("zones", "review_status")
