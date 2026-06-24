#!/bin/bash
# Load .env and run Flutter with dart-defines so the app picks up env vars.
# Edit .env to change the server IP. Then just run: ./run.sh

set -a
source "$(dirname "$0")/.env"
set +a

flutter run \
  --dart-define=API_BASE_URL="${API_BASE_URL:-http://192.168.1.73:8000}" \
  --dart-define=WS_BASE_URL="${WS_BASE_URL:-ws://192.168.1.73:8000}" \
  --dart-define=ENV="${ENV:-development}" \
  "$@"
