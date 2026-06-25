#!/usr/bin/env bash
# DRD Operations — start FastAPI backend + BLE bridge together
# Usage:  ./start.sh [port]
# Default port: 8000

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$ROOT/Server"
RETICULUM_DIR="$ROOT/reticulum"
PORT="${1:-8000}"
API_BASE="http://127.0.0.1:$PORT"

# ── JWT config (must match Server/app/config.py) ─────────────────────────────
JWT_SECRET="drd_field_ops_secret_key_2024_super_secure_random_string_here"
JWT_ALGORITHM="HS256"

# ── colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  DRD Operations  —  backend + BLE bridge${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ── environment check (conda or venv) ────────────────────────────────────────
if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
  echo -e "${GREEN}[✓] Conda env: $CONDA_DEFAULT_ENV${NC}"
elif [[ -n "$VIRTUAL_ENV" ]]; then
  echo -e "${GREEN}[✓] Virtualenv: $VIRTUAL_ENV${NC}"
else
  echo -e "${YELLOW}[!] No conda/venv active — using system Python${NC}"
fi

# ── cleanup on Ctrl+C ────────────────────────────────────────────────────────
cleanup() {
  echo ""
  echo -e "${RED}[↓] Shutting down…${NC}"
  [[ -n "$UVICORN_PID" ]] && kill "$UVICORN_PID" 2>/dev/null || true
  [[ -n "$BRIDGE_PID"  ]] && kill "$BRIDGE_PID"  2>/dev/null || true
  echo -e "${RED}[✓] Stopped.${NC}"
}
trap cleanup INT TERM EXIT

# ── 1. Start FastAPI ──────────────────────────────────────────────────────────
echo -e "${BLUE}[1/3] Starting FastAPI on port $PORT …${NC}"
cd "$SERVER_DIR"
uvicorn app.main:app --reload --host 0.0.0.0 --port "$PORT" &
UVICORN_PID=$!

# Wait until API is accepting connections (max 20 s)
echo -n "      Waiting for API "
for i in $(seq 1 20); do
  if curl -sf "$API_BASE/docs" > /dev/null 2>&1 || \
     curl -sf "$API_BASE/"    > /dev/null 2>&1 || \
     curl -sf "$API_BASE/api/v1/auth/login" -X POST \
          -H "Content-Type: application/json" \
          -d '{}' > /dev/null 2>&1; then
    echo -e " ${GREEN}ready ✓${NC}"
    break
  fi
  echo -n "."
  sleep 1
done
echo ""

# ── 2. Generate long-lived service token for BLE bridge ──────────────────────
echo -e "${BLUE}[2/3] Generating bridge service token …${NC}"

API_TOKEN=$(python - <<PYEOF
import sys
from datetime import datetime, timedelta, timezone
try:
    from jose import jwt
except ImportError:
    try:
        import jwt as pyjwt
        token = pyjwt.encode(
            {"sub": "ble-bridge-service", "exp": datetime.now(timezone.utc) + timedelta(days=365)},
            "$JWT_SECRET", algorithm="$JWT_ALGORITHM"
        )
        print(token if isinstance(token, str) else token.decode())
        sys.exit(0)
    except ImportError:
        sys.exit(1)

token = jwt.encode(
    {"sub": "ble-bridge-service", "exp": datetime.now(timezone.utc) + timedelta(days=365)},
    "$JWT_SECRET", algorithm="$JWT_ALGORITHM"
)
print(token)
PYEOF
)

if [[ -n "$API_TOKEN" ]]; then
  echo -e "      ${GREEN}Service token generated ✓${NC}"
else
  echo -e "      ${YELLOW}Warning: could not generate token (jose/PyJWT not installed?) — bridge runs without WS push${NC}"
fi

# ── 3. Start BLE bridge ───────────────────────────────────────────────────────
echo -e "${BLUE}[3/3] Starting BLE bridge (advertising as DRD-BRIDGE) …${NC}"
cd "$RETICULUM_DIR"
pip install bless aiohttp websockets --quiet 2>/dev/null || true

API_BASE_URL="$API_BASE" API_TOKEN="$API_TOKEN" python ble_bridge_server.py &
BRIDGE_PID=$!

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  FastAPI  →  $API_BASE${NC}"
echo -e "${GREEN}  BLE      →  advertising as DRD-BRIDGE${NC}"
echo -e "${GREEN}  Press Ctrl+C to stop both${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

wait
