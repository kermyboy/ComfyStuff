#!/usr/bin/env bash
set -Eeuo pipefail

# --- Optional JupyterLab (no auth, proxy-friendly) ---
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

# --- Ensure persistent dirs exist on the mounted volume ---
mkdir -p /workspace/models/{checkpoints,vae,clip,loras,controlnet,upscale_models,embeddings,wan,insightface/antelopev2,insightface/buffalo_l}
mkdir -p /workspace/{input,output}
mkdir -p /workspace/user/default/workflows

# --- Re-point ComfyUI paths to persistent volume (idempotent) ---
for d in models input output; do
  if [[ ! -L "/opt/ComfyUI/${d}" ]]; then
    rm -rf "/opt/ComfyUI/${d}" || true
    ln -s "/workspace/${d}" "/opt/ComfyUI/${d}"
  fi
done

# user dir (where workflows/config live)
if [[ ! -L /opt/ComfyUI/user ]]; then
  rm -rf /opt/ComfyUI/user || true
  ln -s /workspace/user /opt/ComfyUI/user
fi
# Ensure custom_nodes persists and link exists
mkdir -p /workspace/custom_nodes
if [[ ! -L /opt/ComfyUI/custom_nodes ]]; then
  # seed from image if a real dir somehow still exists
  if [[ -d /opt/ComfyUI/custom_nodes ]]; then
    rsync -a /opt/ComfyUI/custom_nodes/ /workspace/custom_nodes/ || true
    rm -rf /opt/ComfyUI/custom_nodes
  fi
  ln -s /workspace/custom_nodes /opt/ComfyUI/custom_nodes
fi
# --- Start ComfyUI ---
cd /opt/ComfyUI
exec python3.10 main.py --listen 0.0.0.0 --port "${COMFY_PORT:-8188}"
