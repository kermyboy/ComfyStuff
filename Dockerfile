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
    HF_HOME=/workspace/.cache/huggingface

# --- System deps (runtime-only; no compilers) ---
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update -y && apt-get install -y --no-install-recommends \
      python3.10 python3.10-venv python3.10-distutils python3.10-dev \
      git-lfs curl wget ffmpeg libgl1 libglib2.0-0 ca-certificates \
    && git lfs install \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# --- Pin refs (branch | tag | commit SHA all work) ---
ARG COMFYUI_REF=master
ARG REACTOR_REF=master
ARG IPAP_REF=master
ARG RG3_REF=master
ARG WAN_REF=master

# --- Fetch ComfyUI via archive (no .git, smaller & reliable) ---
RUN set -eux; \
    mkdir -p /workspace/ComfyUI; \
    curl -L "https://codeload.github.com/comfyanonymous/ComfyUI/tar.gz/${COMFYUI_REF}" \
      | tar -xz --strip-components=1 -C /workspace/ComfyUI

# --- Python venv ---
WORKDIR /workspace/ComfyUI
RUN python3.10 -m venv .venv
ENV PATH="/workspace/ComfyUI/.venv/bin:${PATH}"
RUN python -m pip install --upgrade pip setuptools wheel

# --- Core Python pins (keep wheels only; speed + stability) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir "numpy==1.26.4"

# --- PyTorch CUDA 12.1 wheels ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      "torch==2.3.1+cu121" "torchvision==0.18.1+cu121" \
      --index-url https://download.pytorch.org/whl/cu121

# --- ONNX + CV stack ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      onnx==1.16.0 \
      onnxruntime-gpu==1.18.1 \
      opencv-python-headless==4.9.0.80 \
      "scikit-image<0.23" \
      "pillow<10.3" \
      "protobuf<5"

# --- InsightFace deps first (prevent resolver fights), then InsightFace w/o deps ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      "scipy==1.11.4" \
      "easydict==1.13" \
      "prettytable==3.10.0" \
      "tqdm==4.66.5"

# Install InsightFace but keep our ORT/OpenCV pins intact
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --no-deps insightface==0.7.3
# If you hit a wheel availability issue, drop to:
# RUN pip install --no-cache-dir --no-deps insightface==0.7.2.post0

# --- Custom nodes via archives (fast; cacheable; no .git) ---
WORKDIR /workspace/ComfyUI/custom_nodes
RUN set -eux; \
    mkdir -p ComfyUI-ReActor && \
    curl -L "https://codeload.github.com/Gourieff/ComfyUI-ReActor/tar.gz/${REACTOR_REF}" \
      | tar -xz --strip-components=1 -C ComfyUI-ReActor && \
    mkdir -p ComfyUI_IPAdapter_plus && \
    curl -L "https://codeload.github.com/cubiq/ComfyUI_IPAdapter_plus/tar.gz/${IPAP_REF}" \
      | tar -xz --strip-components=1 -C ComfyUI_IPAdapter_plus && \
    mkdir -p rgthree-comfy && \
    curl -L "https://codeload.github.com/rgthree/rgthree-comfy/tar.gz/${RG3_REF}" \
      | tar -xz --strip-components=1 -C rgthree-comfy && \
    mkdir -p ComfyUI--Wan22FirstLastFrameToVideoLatent && \
    curl -L "https://codeload.github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent/tar.gz/${WAN_REF}" \
      | tar -xz --strip-components=1 -C ComfyUI--Wan22FirstLastFrameToVideoLatent

# ---- Disable ReActor SFW filter (non-fatal) ----
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

# --- JupyterLab (optional) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir jupyterlab

# --- Ports ---
EXPOSE 8188 8888

# --- Healthcheck ---
HEALTHCHECK --interval=60s --timeout=5s --start-period=60s --retries=5 \
  CMD curl -fsS http://localhost:8188/ || exit 1

# --- Startup ---
WORKDIR /workspace
COPY start.sh /workspace/start.sh
RUN chmod +x /workspace/start.sh
ENTRYPOINT ["/workspace/start.sh"]
