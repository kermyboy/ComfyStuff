#!/usr/bin/env bash
set -euo pipefail

# Activate ComfyUI venv
source /workspace/ComfyUI/.venv/bin/activate

# Start JupyterLab (in background)
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root &

# Start ComfyUI
cd /workspace/ComfyUI
exec python main.py --listen 0.0.0.0 --port 8188
