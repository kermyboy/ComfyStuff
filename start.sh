#!/usr/bin/env bash
set -Eeuo pipefail

# --- Optional JupyterLab (no-auth, opt-in) ---
if [[ "${ENABLE_JUPYTER:-0}" == "1" ]]; then
  : "${JUPYTER_IP:=0.0.0.0}"
  : "${JUPYTER_PORT:=8888}"
  echo "Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT} (no auth)..."
  nohup jupyter lab \
    --ip="${JUPYTER_IP}" \
    --port="${JUPYTER_PORT}" \
    --no-browser \
    --allow-root \
    --ServerApp.token='' \
    --ServerApp.password='' \
    >/var/log/jupyter.log 2>&1 &
fi

# --- ComfyUI (code is under /opt now) ---
# Make sure models/input/output point to the persistent volume
if [[ ! -L /opt/ComfyUI/models ]]; then
  rm -rf /opt/ComfyUI/models /opt/ComfyUI/input /opt/ComfyUI/output || true
  ln -s /workspace/models /opt/ComfyUI/models
  ln -s /workspace/input  /opt/ComfyUI/input
  ln -s /workspace/output /opt/ComfyUI/output
fi

cd /opt/ComfyUI
exec python3.10 main.py --listen 0.0.0.0 --port "${COMFY_PORT:-8188}"
