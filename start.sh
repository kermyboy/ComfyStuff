#!/usr/bin/env bash
set -euo pipefail

# Start JupyterLab
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root &

# Start ComfyUI (adjust the path if your ComfyUI lives elsewhere)
cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188
