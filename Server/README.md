# DRD Tracking Server

FastAPI backend for the DRD Tracking System.

## Overview

The server provides REST APIs, authentication, database access, WebSocket streams, and background task support.

Key features:

- FastAPI web server
- PostgreSQL access via SQLAlchemy and asyncpg
- Alembic database migrations
- WebSocket endpoints for real-time events and location streaming
- Redis and Celery support for async task processing
- Environment-based configuration via `.env`

## Setup

### Recommended environment

- Python 3.11+
- PostgreSQL
- Redis (if Celery or pub/sub features are required)
- Optional: `conda`

### Install dependencies

```bash
cd Server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Run migrations

```bash
cd Server
alembic upgrade head
```

### Run the API server

```bash
cd Server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Or use the included helper script:

```bash
cd Server
./run.sh
```

## Structure

- `alembic/` - database migration definitions
- `alembic.ini` - Alembic config
- `app/` - FastAPI application package
  - `config.py` - configuration and env handling
  - `main.py` - app initialization and routes
  - `database.py` - database connectivity
  - `models/` - ORM models
  - `schemas/` - Pydantic request/response models
  - `services/` - business logic and helpers
  - `websocket/` - WebSocket route handlers
- `requirements.txt` - Python dependencies
- `run.sh` - bootstrap script for migrations and app startup

## Useful commands

```bash
python -m pip install -r requirements.txt
alembic revision --autogenerate -m "message"
alembic upgrade head
uvicorn app.main:app --reload
```

## Notes

- The project currently uses a `conda` environment in `run.sh`, but a plain Python venv also works.
- Make sure database credentials and Redis configuration are set before launch.
