FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
ENV DEBIAN_FRONTEND=noninteractive

# System deps
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3.10-distutils ca-certificates \
    git curl wget ffmpeg libgl1 build-essential \
 && rm -rf /var/lib/apt/lists/*

# ComfyUI
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Python 3.10 venv so InsightFace installs cleanly
RUN python3.10 -m venv .venv
ENV PATH="/workspace/ComfyUI/.venv/bin:${PATH}"

# Python deps
RUN python -m pip install --upgrade pip setuptools wheel && \
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121 && \
    pip install onnx==1.16.0 onnxruntime-gpu==1.18.1 opencv-python insightface==0.7.3

# Custom nodes
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone https://github.com/Gourieff/ComfyUI_ReActor.git && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git

# Model + IO dirs
RUN mkdir -p /workspace/ComfyUI/models/insightface/antelopev2 \
             /workspace/ComfyUI/models/insightface/buffalo_l \
             /workspace/ComfyUI/custom_nodes/ComfyUI_ReActor/models \
             /workspace/ComfyUI/models/checkpoints \
             /workspace/ComfyUI/models/vae \
             /workspace/ComfyUI/models/clip \
             /workspace/ComfyUI/models/wan \
             /workspace/ComfyUI/input \
             /workspace/ComfyUI/output

# Env
ENV INSIGHTFACE_HOME=/workspace/ComfyUI/models/insightface
ENV HF_HOME=/workspace/.cache/huggingface
EXPOSE 8188

# Entrypoint
RUN printf '%s\n' '#!/usr/bin/env bash' \
  'set -e' \
  'cd /workspace/ComfyUI' \
  'source .venv/bin/activate' \
  'export INSIGHTFACE_HOME="/workspace/ComfyUI/models/insightface"' \
  'exec python main.py --listen 0.0.0.0 --port 8188 "$@"' \
  > /workspace/start.sh && chmod +x /workspace/start.sh

ENTRYPOINT ["/workspace/start.sh"]
