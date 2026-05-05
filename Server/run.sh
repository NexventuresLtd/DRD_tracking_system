#!/bin/bash
conda init bash
# Activate virtual environment
conda activate fastapi_setup

# # Install dependencies
# echo "Installing dependencies..."
# pip install -r requirements.txt

# # Create database
# echo "Creating database..."
# psql -U postgres -f create_database.sql

# Run migrations
echo "Running database migrations..."
alembic revision --autogenerate -m "Initial migration"
alembic upgrade head

# Run the application
echo "Starting server..."
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000