#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "Running Alembic migrations..."
alembic upgrade head

echo "Starting DRD Field Coordination Server on port ${PORT:-1104}..."
uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-1104}" --reload --log-level info