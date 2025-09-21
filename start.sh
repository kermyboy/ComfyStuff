#!/usr/bin/env bash
set -Eeuo pipefail

# ---- Defaults / knobs --------------------------------------------------------
: "${COMFY_PORT:=8188}"
: "${ENABLE_JUPYTER:=0}"
: "${JUPYTER_IP:=0.0.0.0}"
: "${JUPYTER_PORT:=8888}"
: "${COMFY_ARGS:=}"             # e.g. "--gpu-only --auto-launch"
umask 0002                      # friendlier perms when volumes are reused

# Persist common caches in the volume (avoids re-downloads on new pods)
export XDG_CACHE_HOME=/workspace/.cache
export HF_HOME=${HF_HOME:-/workspace/.cache/huggingface}
export INSIGHTFACE_HOME=${INSIGHTFACE_HOME:-/workspace/models/insightface}

# ---- Helpers -----------------------------------------------------------------
link_into_opt() {
  # link_into_opt <name>  (links /workspace/<name> -> /opt/ComfyUI/<name>)
  local name="$1"
  mkdir -p "/workspace/${name}"
  rm -rf "/opt/ComfyUI/${name}" 2>/dev/null || true
  ln -sfn "/workspace/${name}" "/opt/ComfyUI/${name}"
}

# ---- Optional JupyterLab (no auth; proxy-friendly) ---------------------------
if [[ "${ENABLE_JUPYTER}" == "1" ]]; then
  echo "Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT} (no auth)..."
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

# ---- Ensure persistent dirs ---------------------------------------------------
mkdir -p /workspace/{input,output,user/default/workflows,custom_nodes,reactor_models}
mkdir -p /workspace/models/{checkpoints,vae,clip,loras,controlnet,upscale_models,embeddings,wan,insightface/antelopev2,insightface/buffalo_l}
mkdir -p /workspace/.cache

# Seed custom_nodes only on first run
if [[ -d /opt/_seed_custom_nodes ]] && [[ -z "$(ls -A /workspace/custom_nodes 2>/dev/null)" ]]; then
  echo "[init] Seeding custom_nodes into /workspace/custom_nodes"
  rsync -a /opt/_seed_custom_nodes/ /workspace/custom_nodes/
fi

# ReActor expects a models dir; keep it persistent
if [[ -d /workspace/custom_nodes/ComfyUI-ReActor ]]; then
  ln -sfn /workspace/reactor_models /workspace/custom_nodes/ComfyUI-ReActor/models
fi

# ---- Link ComfyUI paths back into /opt (idempotent) --------------------------
for d in models input output user custom_nodes; do
  link_into_opt "${d}"
done

# ---- Start ComfyUI -----------------------------------------------------------
cd /opt/ComfyUI
echo "Starting ComfyUI on 0.0.0.0:${COMFY_PORT} ${COMFY_ARGS}"
exec python3.10 main.py --listen 0.0.0.0 --port "${COMFY_PORT}" ${COMFY_ARGS}
