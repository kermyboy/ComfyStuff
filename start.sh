#!/usr/bin/env bash
set -Eeuo pipefail

: "${COMFY_PORT:=8188}"
: "${ENABLE_JUPYTER:=0}"
: "${JUPYTER_IP:=0.0.0.0}"
: "${JUPYTER_PORT:=8888}"
: "${COMFY_ARGS:=}"
umask 0002

export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export XDG_CACHE_HOME=/workspace/.cache
export HF_HOME=${HF_HOME:-/workspace/.cache/huggingface}

# Ensure python/pip are resolvable (python=3.11)
command -v python >/dev/null || ln -sf /usr/bin/python3.11 /usr/bin/python
command -v pip >/dev/null || ln -sf /usr/bin/pip3 /usr/bin/pip

# Workspace structure (Wan-focused)
mkdir -p /workspace/{input,output,user/default/workflows,custom_nodes}
mkdir -p /workspace/models/{diffusion_models,vae,clip,clip_vision,text_encoders,wan}
mkdir -p /workspace/.cache

# Seed custom_nodes on first run
if [[ -d /opt/_seed_custom_nodes ]] && [[ -z "$(ls -A /workspace/custom_nodes 2>/dev/null)" ]]; then
  echo "[init] Seeding custom_nodes into /workspace/custom_nodes"
  rsync -a /opt/_seed_custom_nodes/ /workspace/custom_nodes/
fi

# Link runtime dirs into /opt/ComfyUI
link_into_opt() { local name="$1"; mkdir -p "/workspace/${name}"; rm -rf "/opt/ComfyUI/${name}" 2>/dev/null || true; ln -sfn "/workspace/${name}" "/opt/ComfyUI/${name}"; }
for d in models input output user custom_nodes; do link_into_opt "${d}"; done

# Optional Jupyter
if [[ "${ENABLE_JUPYTER}" == "1" ]]; then
  echo "Starting JupyterLab on ${JUPYTER_IP}:${JUPYTER_PORT} (no auth)..."
  nohup jupyter lab --ip="${JUPYTER_IP}" --port="${JUPYTER_PORT}" --no-browser --allow-root \
    --ServerApp.root_dir=/workspace --ServerApp.base_url='/' \
    --ServerApp.trust_xheaders=True --ServerApp.allow_remote_access=True \
    --ServerApp.allow_origin='*' --ServerApp.disable_check_xsrf=True \
    --ServerApp.token='' --ServerApp.password='' \
    >/var/log/jupyter.log 2>&1 &
fi

cd /opt/ComfyUI
echo "Starting ComfyUI on 0.0.0.0:${COMFY_PORT} ${COMFY_ARGS}"
exec /usr/bin/python3.11 main.py --listen 0.0.0.0 --port "${COMFY_PORT}" ${COMFY_ARGS}
