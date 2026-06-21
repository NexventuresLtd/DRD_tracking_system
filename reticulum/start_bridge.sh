#!/usr/bin/env bash
# DRD Reticulum Bridge — start script
# Usage:  ./start_bridge.sh [--config /path/to/.env]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Allow overriding the env file via --config flag
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) ENV_FILE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Validate environment ───────────────────────────────────────────────────────

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] .env file not found at $ENV_FILE"
  echo "        Copy .env.example to .env and fill in the required values."
  exit 1
fi

# Source env so we can check required vars
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${API_BASE_URL:?API_BASE_URL must be set in $ENV_FILE}"
: "${API_TOKEN:?API_TOKEN must be set in $ENV_FILE}"

# ── Python / venv check ───────────────────────────────────────────────────────

VENV_DIR="${SCRIPT_DIR}/.venv"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "[INFO] Creating Python virtual environment at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

PYTHON="${VENV_DIR}/bin/python"
PIP="${VENV_DIR}/bin/pip"

echo "[INFO] Installing / verifying dependencies…"
"$PIP" install --quiet -r "${SCRIPT_DIR}/requirements.txt"

# ── Reticulum config ──────────────────────────────────────────────────────────

RNS_CONFIG_DIR="${RNS_CONFIG_DIR:-$HOME/.reticulum}"
export RNS_CONFIG_DIR

if [[ ! -f "${RNS_CONFIG_DIR}/config" ]]; then
  echo "[INFO] Copying default Reticulum config to ${RNS_CONFIG_DIR}/config"
  mkdir -p "$RNS_CONFIG_DIR"
  cp "${SCRIPT_DIR}/reticulum.config" "${RNS_CONFIG_DIR}/config"
fi

# ── Launch bridge ─────────────────────────────────────────────────────────────

echo "[INFO] Starting DRD Reticulum Bridge"
echo "       API endpoint : ${API_BASE_URL}"
echo "       WS  endpoint : ${WS_URL:-ws://127.0.0.1:8000/ws/events}"
echo "       RNS config   : ${RNS_CONFIG_DIR}/config"
echo ""

exec "$PYTHON" "${SCRIPT_DIR}/bridge.py"
