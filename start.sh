#!/usr/bin/env bash
set -euo pipefail

# Activate ComfyUI venv
source /workspace/ComfyUI/.venv/bin/activate

# Optionally start JupyterLab (toggle via env)
if [[ "${ENABLE_JUPYTER:-0}" == "1" ]]; then
  echo "Starting JupyterLab on :8888..."
  jupyter lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --allow-root &
fi

# Start ComfyUI (PID 1 will be this process, so signals work)
cd /workspace/ComfyUI
exec python main.py --listen 0.0.0.0 --port 8188
