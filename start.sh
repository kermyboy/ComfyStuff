#!/usr/bin/env bash
set -Eeuo pipefail

# Optional JupyterLab (opt-in)
if [[ "${ENABLE_JUPYTER:-0}" == "1" ]]; then
  : "${JUPYTER_IP:=0.0.0.0}"
  : "${JUPYTER_PORT:=8888}"
  # If JUPYTER_TOKEN is unset, Jupyter will generate a random token (safer).
  echo "Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT}..."
  nohup jupyter lab \
    --ip="$JUPYTER_IP" \
    --port="$JUPYTER_PORT" \
    --no-browser \
    --allow-root \
    >/var/log/jupyter.log 2>&1 &
fi

# Start ComfyUI
cd /workspace/ComfyUI
exec python3.10 main.py --listen 0.0.0.0 --port "${COMFY_PORT:-8188}"
