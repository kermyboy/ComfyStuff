# CUDA 12.1 + cuDNN8 on Ubuntu 22.04
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Use bash for RUN so `source` works if needed
SHELL ["/bin/bash", "-lc"]

# --- Base env ---
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DEFAULT_TIMEOUT=120 \
    PIP_NO_INPUT=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128,expandable_segments:True

# --- System deps ---
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update -y && apt-get install -y --no-install-recommends \
      python3.10 python3.10-venv python3.10-distutils python3.10-dev \
      git git-lfs curl wget ffmpeg libgl1 libglib2.0-0 build-essential \
      cmake ninja-build cython3 ca-certificates \
 && git lfs install \
 && rm -rf /var/lib/apt/lists/*

# --- Workdir & sources ---
WORKDIR /workspace
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git

# --- Create and verify the venv exactly where start.sh expects it ---
WORKDIR /workspace/ComfyUI
RUN python3.10 -m venv .venv \
 && . .venv/bin/activate \
 && python -V \
 && pip install --upgrade pip setuptools wheel

# Make the venv discoverable at runtime (even if shells change PATH)
ENV VIRTUAL_ENV=/workspace/ComfyUI/.venv
ENV PATH="$VIRTUAL_ENV/bin:${PATH}"

# --- Python deps (pre-pin numpy; cython <3 avoids ABI grief) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir "numpy==1.26.4" "cython<3"

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

# --- InsightFace ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir insightface==0.7.3

# --- (Optional but recommended) Install ComfyUI’s own Python requirements ---
# If the repo has requirements, install them into the same venv.
# This prevents runtime surprises where modules are missing.
RUN --mount=type=cache,target=/root/.cache/pip \
    if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

# --- Custom nodes ---
WORKDIR /workspace/ComfyUI/custom_nodes
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/Gourieff/ComfyUI-ReActor.git && \
    git clone --depth=1 https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth=1 https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git

# ---- Disable ReActor SFW filter ----
RUN set -eux; \
    f="/workspace/ComfyUI/custom_nodes/ComfyUI-ReActor/scripts/reactor_sfw.py"; \
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
             /workspace/ComfyUI/output

# --- Caches & runtime env ---
ENV INSIGHTFACE_HOME=/workspace/ComfyUI/models/insightface \
    HF_HOME=/workspace/.cache/huggingface

# --- JupyterLab (in same venv) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir jupyterlab

# --- Ports ---
EXPOSE 8188 8888

# --- Healthcheck (ComfyUI HTTP server) ---
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD curl -fsS http://localhost:8188/ || exit 1

# --- Startup ---
# Copy once; put it where PATH can find it
COPY --chmod=755 start.sh /usr/local/bin/start.sh
# Strip CRLF if edited on Windows
RUN sed -i 's/\r$//' /usr/local/bin/start.sh

# Final sanity check: ensure venv exists so start.sh doesn’t blow up
RUN test -f /workspace/ComfyUI/.venv/bin/activate

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/start.sh"]
