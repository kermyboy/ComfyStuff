FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_DEFAULT_TIMEOUT=120 PIP_NO_INPUT=1

# --- System deps (ADDED python3.10-dev, cython3, cmake, ninja) ---
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3.10-distutils python3.10-dev \
    git curl wget ffmpeg libgl1 libglib2.0-0 build-essential \
    cmake ninja-build cython3 \
 && rm -rf /var/lib/apt/lists/*

# --- ComfyUI ---
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Python 3.10 venv
RUN python3.10 -m venv .venv
ENV PATH="/workspace/ComfyUI/.venv/bin:${PATH}"

# --- Python deps (split + pinned; PREPIN numpy, pin cython to <3) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir "numpy==1.26.4" "cython<3"

# Torch CUDA 12.1 wheels
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      "torch==2.3.1+cu121" "torchvision==0.18.1+cu121" \
      --index-url https://download.pytorch.org/whl/cu121

# ONNX + CV stack
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      onnx==1.16.0 \
      onnxruntime-gpu==1.18.1 \
      opencv-python-headless==4.9.0.80 \
      "scikit-image<0.23" \
      "pillow<10.3" \
      "protobuf<5"

# InsightFace (now it can compile if it must)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir insightface==0.7.3

# --- Custom nodes ---
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone https://github.com/Gourieff/ComfyUI-ReActor.git && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git

# ---- Disable ReActor SFW filter ----
RUN sed -i 's/return is_nsfw/return False/' /workspace/ComfyUI/custom_nodes/ComfyUI_ReActor/scripts/reactor_sfw.py || true && \
    sed -i 's/if nsfw_image.*:/if False:/' /workspace/ComfyUI/custom_nodes/ComfyUI_ReActor/scripts/reactor_sfw.py || true


# --- Model + IO dirs ---
RUN mkdir -p /workspace/ComfyUI/models/insightface/antelopev2 \
             /workspace/ComfyUI/models/insightface/buffalo_l \
             /workspace/ComfyUI/custom_nodes/ComfyUI_ReActor/models \
             /workspace/ComfyUI/models/checkpoints \
             /workspace/ComfyUI/models/vae \
             /workspace/ComfyUI/models/clip \
             /workspace/ComfyUI/models/wan \
             /workspace/ComfyUI/input \
             /workspace/ComfyUI/output

# --- Env & port ---
ENV INSIGHTFACE_HOME=/workspace/ComfyUI/models/insightface
ENV HF_HOME=/workspace/.cache/huggingface
EXPOSE 8188

# --- Entrypoint ---
RUN printf '%s\n' '#!/usr/bin/env bash' \
  'set -e' \
  'cd /workspace/ComfyUI' \
  'source .venv/bin/activate' \
  'export INSIGHTFACE_HOME="/workspace/ComfyUI/models/insightface"' \
  'exec python main.py --listen 0.0.0.0 --port 8188 "$@"' \
  > /workspace/start.sh && chmod +x /workspace/start.sh

ENTRYPOINT ["/workspace/start.sh"]
