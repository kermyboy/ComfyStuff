#!/usr/bin/env bash
set -Eeuo pipefail

# --- Optional JupyterLab (no auth, opt-in) ---
if [[ "${ENABLE_JUPYTER:-0}" == "1" ]]; then
  : "${JUPYTER_IP:=0.0.0.0}"
  : "${JUPYTER_PORT:=8888}"
  echo "Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT} (no auth)..."
nohup jupyter lab \
  --ip="${JUPYTER_IP:-0.0.0.0}" \
  --port="${JUPYTER_PORT:-8888}" \
  --no-browser --allow-root \
  --ServerApp.root_dir=/workspace \
  --ServerApp.base_url='/' \
  --ServerApp.token='' --ServerApp.password='' \
  >/var/log/jupyter.log 2>&1 &
fi

# --- Ensure symlinks point to persistent volume every start ---
mkdir -p /workspace/{input,output,models}
for d in models input output; do
  if [[ ! -L "/opt/ComfyUI/${d}" ]]; then
    rm -rf "/opt/ComfyUI/${d}" || true
    ln -s "/workspace/${d}" "/opt/ComfyUI/${d}"
  fi
done

# --- Start ComfyUI ---
cd /opt/ComfyUI
exec python3.10 main.py --listen 0.0.0.0 --port "${COMFY_PORT:-8188}"
