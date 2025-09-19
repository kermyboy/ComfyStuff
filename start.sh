#!/usr/bin/env bash
set -Eeuo pipefail

# --- Optional JupyterLab (no auth, opt-in) ---
if [[ "${ENABLE_JUPYTER:-0}" == "1" ]]; then
  : "${JUPYTER_IP:=0.0.0.0}"
  : "${JUPYTER_PORT:=8888}"
  echo "Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT} (no auth, proxy-friendly)..."
  nohup jupyter lab \
    --ip="${JUPYTER_IP}" \
    --port="${JUPYTER_PORT}" \
    --no-browser --allow-root \
    --ServerApp.root_dir=/workspace \
    --ServerApp.base_url='/' \
    --ServerApp.trust_xheaders=True \
    --ServerApp.allow_remote_access=True \
    --ServerApp.allow_origin='*' \
    --ServerApp.disable_check_xsrf=True \
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

# --- Ensure default model subfolders exist (moved from Dockerfile) ---
mkdir -p /workspace/models/{insightface/antelopev2,insightface/buffalo_l,checkpoints,vae,clip,wan,loras,controlnet,upscale_models,embeddings}
mkdir -p /workspace/reactor_models
ln -sfn /workspace/reactor_models /opt/ComfyUI/custom_nodes/ComfyUI-ReActor/models

# --- Start ComfyUI ---
cd /opt/ComfyUI
exec python3.10 main.py --listen 0.0.0.0 --port "${COMFY_PORT:-8188}"
