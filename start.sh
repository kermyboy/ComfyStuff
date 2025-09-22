#!/usr/bin/env bash
set -Eeuo pipefail

: "${COMFY_PORT:=8188}"
: "${ENABLE_JUPYTER:=0}"
: "${JUPYTER_IP:=0.0.0.0}"
: "${JUPYTER_PORT:=8888}"
: "${COMFY_ARGS:=}"
umask 0002

export XDG_CACHE_HOME=/workspace/.cache
export HF_HOME=${HF_HOME:-/workspace/.cache/huggingface}
export INSIGHTFACE_HOME=${INSIGHTFACE_HOME:-/workspace/models/insightface}

# ---- ensure python/pip aliases for Manager -----------------------------------
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
if ! command -v python >/dev/null 2>&1; then
  [ -x /usr/bin/python3.10 ] && ln -sf /usr/bin/python3.10 /usr/bin/python
fi
if ! command -v pip >/dev/null 2>&1 && [ -x /usr/bin/pip3 ]; then
  ln -sf /usr/bin/pip3 /usr/bin/pip
fi
python - <<'PY' || { echo "[FATAL] Missing pip module in python runtime"; exit 13; }
import sys
import pip
try:
    import git, toml
except Exception as e:
    print(f"[WARN] Optional Manager deps missing: {e}", file=sys.stderr)
print("python OK:", sys.version)
PY

link_into_opt() {
  local name="$1"
  mkdir -p "/workspace/${name}"
  rm -rf "/opt/ComfyUI/${name}" 2>/dev/null || true
  ln -sfn "/workspace/${name}" "/opt/ComfyUI/${name}"
}

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

mkdir -p /workspace/{input,output,user/default/workflows,custom_nodes,reactor_models}
mkdir -p /workspace/models/{checkpoints,vae,clip,loras,controlnet,upscale_models,embeddings,wan,insightface/antelopev2,insightface/buffalo_l}
mkdir -p /workspace/.cache

if [[ -d /opt/_seed_custom_nodes ]] && [[ -z "$(ls -A /workspace/custom_nodes 2>/dev/null)" ]]; then
  echo "[init] Seeding custom_nodes into /workspace/custom_nodes"
  rsync -a /opt/_seed_custom_nodes/ /workspace/custom_nodes/
fi

if [[ -d /workspace/custom_nodes/ComfyUI-ReActor ]]; then
  ln -sfn /workspace/reactor_models /workspace/custom_nodes/ComfyUI-ReActor/models
fi

for d in models input output user custom_nodes; do
  link_into_opt "${d}"
done

# Optional: run Manager prestartup non-fatal (better logging)
if [ -f /opt/ComfyUI/custom_nodes/ComfyUI-Manager/prestartup_script.py ]; then
  echo "[info] Running ComfyUI-Manager prestartup..."
  python /opt/ComfyUI/custom_nodes/ComfyUI-Manager/prestartup_script.py || \
    echo "[warn] Manager prestartup failed (continuing)"
fi

cd /opt/ComfyUI
echo "Starting ComfyUI on 0.0.0.0:${COMFY_PORT} ${COMFY_ARGS}"
exec python3.10 main.py --listen 0.0.0.0 --port "${COMFY_PORT}" ${COMFY_ARGS}
