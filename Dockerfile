# CUDA 12.1 + cuDNN8 on Ubuntu 22.04
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# --- Base env ---
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DEFAULT_TIMEOUT=120 \
    PIP_NO_INPUT=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128,expandable_segments:True \
    INSIGHTFACE_HOME=/workspace/ComfyUI/models/insightface \
    HF_HOME=/workspace/.cache/huggingface \
    VIRTUAL_ENV=/workspace/ComfyUI/.venv \
    PATH="/workspace/ComfyUI/.venv/bin:${PATH}"

# --- System deps (with APT cache mounts) ---
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update -y && apt-get install -y --no-install-recommends \
      python3.10 python3.10-venv python3.10-distutils python3.10-dev \
      git git-lfs curl wget ffmpeg libgl1 libglib2.0-0 \
      # keep ONLY what you actually need at runtime; drop toolchains
      && git lfs install \
      && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# --- Pin the exact ComfyUI commit so layer caches stick ---
ARG COMFYUI_REF=07f9b2c0a6b1b0c942f1c6d0f2e0d6e2c21f8d77
RUN git clone --depth 1 --branch master https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && git fetch --depth 1 origin ${COMFYUI_REF} && git checkout ${COMFYUI_REF}

WORKDIR /workspace/ComfyUI

# --- Python 3.10 venv ---
RUN python3.10 -m venv .venv && . .venv/bin/activate && \
    python -m pip install --upgrade pip setuptools wheel

# --- Python deps (pre-pin numpy; cython not installed unless you truly need it) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir "numpy==1.26.4"

# --- PyTorch CUDA 12.1 wheels ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      "torch==2.3.1+cu121" "torchvision==0.18.1+cu121" \
      --index-url https://download.pytorch.org/whl/cu121

# --- ONNX + CV stack (all wheels; no build toolchain needed) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      onnx==1.16.0 \
      onnxruntime-gpu==1.18.1 \
      opencv-python-headless==4.9.0.80 \
      "scikit-image<0.23" \
      "pillow<10.3" \
      "protobuf<5"

# --- InsightFace (wheel only) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir insightface==0.7.3

# --- Custom nodes (shallow clones, pinned for caching) ---
WORKDIR /workspace/ComfyUI/custom_nodes
ARG REACTOR_REF=master
ARG IPAP_REF=master
ARG RG3_REF=master
ARG WAN_REF=master
RUN git clone --depth 1 --branch ${REACTOR_REF} https://github.com/Gourieff/ComfyUI-ReActor.git && \
    git clone --depth 1 --branch ${IPAP_REF} https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone --depth 1 --branch ${RG3_REF} https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 --branch ${WAN_REF} https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git

# ---- Disable ReActor SFW filter (leave as-is but make it non-fatal) ----
RUN set -eux; f="/workspace/ComfyUI/custom_nodes/ComfyUI-ReActor/scripts/reactor_sfw.py"; \
    if [ -f "$f" ]; then \
      sed -i 's/return is_nsfw/return False/' "$f" || true; \
      sed -i 's/if nsfw_image.*:/if False:/' "$f" || true; \
    fi

# --- Model + IO dirs ---
RUN mkdir -p /workspace/ComfyUI/models/insightface/antelopev2 \
             /workspace/ComfyUI/models/insightface/buffalo_l \
             /workspace/ComfyUI/custom_nodes/ComfyUI-ReActor/models \
             /workspace/ComfyUI/models/checkpoints \
             /workspace/ComfyUI/models/vae \
             /workspace/ComfyUI/models/clip \
             /workspace/ComfyUI/models/wan \
             /workspace/ComfyUI/input \
             /workspace/ComfyUI/output \
             /workspace/.cache/huggingface

# --- (Optional) Pre-fetch minimal InsightFace model so first run isn’t slow ---
# Skips if you mount a populated persistent volume at /workspace
# RUN python - <<'PY'\nfrom insightface.app import FaceAnalysis\napp=FaceAnalysis(name='buffalo_l', root='/workspace/ComfyUI/models/insightface'); app.prepare(ctx_id=0)\nPY

# --- JupyterLab (same venv) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir jupyterlab

# --- Ports ---
EXPOSE 8188 8888

# --- Healthcheck (less aggressive; avoids flapping during cold start) ---
HEALTHCHECK --interval=60s --timeout=5s --start-period=60s --retries=5 \
  CMD curl -fsS http://localhost:8188/ || exit 1

# --- Startup ---
WORKDIR /workspace
COPY start.sh /workspace/start.sh
RUN chmod +x /workspace/start.sh

ENTRYPOINT ["/workspace/start.sh"]
