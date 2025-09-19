#!/usr/bin/env bash
set -Eeuo pipefail

VENV=/workspace/ComfyUI/.venv

# Ensure the venv is present (or optionally create it)
if [[ ! -f "$VENV/bin/activate" ]]; then
  if [[ "${CREATE_VENV_IF_MISSING:-0}" == "1" ]]; then
    echo "Venv missing; creating at $VENV..."
    python3.10 -m venv "$VENV"
    "$VENV/bin/pip" install --upgrade pip setuptools wheel
  else
    echo "ERROR: $VENV not found. Build must create it. Exiting." >&2
    exit 1
  fi
fi

# Activate venv and make it obvious to child processes
source "$VENV/bin/activate"
export VIRTUAL_ENV="$VENV"
export PATH="$VENV/bin:$PATH"

# Optional JupyterLab
if [[ "${ENABLE_JUPYTER:-0}" == "1" ]]; then
  : "${JUPYTER_IP:=0.0.0.0}"
  : "${JUPYTER_PORT:=8888}"
  : "${JUPYTER_TOKEN:=}"   # empty = no token (be careful if exposed)
  echo "Starting JupyterLab on :${JUPYTER_PORT}..."
  nohup jupyter lab \
    --ip="$JUPYTER_IP" \
    --port="$JUPYTER_PORT" \
    --no-browser \
    --allow-root \
    --ServerApp.token="$JUPYTER_TOKEN" \
    >/var/log/jupyter.log 2>&1 &
fi

# Start ComfyUI (PID 1 = this process)
cd /workspace/ComfyUI
exec python main.py --listen 0.0.0.0 --port "${COMFY_PORT:-8188}"
