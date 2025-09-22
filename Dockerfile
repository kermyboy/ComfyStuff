# CUDA 12.1 + cuDNN8 on Ubuntu 22.04
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
SHELL ["/bin/bash", "-lc"]

# --- Base env ---
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DEFAULT_TIMEOUT=120 \
    PIP_NO_INPUT=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128,expandable_segments:True \
    HF_HOME=/workspace/.cache/huggingface \
    INSIGHTFACE_HOME=/workspace/models/insightface

# --- System deps ---
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update -y && apt-get install -y --no-install-recommends \
      python3.10 python3.10-dev python3-pip python3.10-venv python-is-python3 \
      git git-lfs curl wget ffmpeg libgl1 libglib2.0-0 build-essential \
      cmake ninja-build cython3 ca-certificates rsync \
 && git lfs install \
 && rm -rf /var/lib/apt/lists/*

# --- Code under /opt (kept in image layers) ---
WORKDIR /opt
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
WORKDIR /opt/ComfyUI

# --- Python deps (system Python) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --upgrade pip setuptools wheel && \
    python3.10 -m pip install --no-cache-dir "numpy==1.26.4" "cython<3"

# --- Ensure Manager can use `python -m pip` and has all Manager deps ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir \
      gitpython>=3.1.43 \
      toml \
      rich \
      pygithub \
      matrix-client==0.4.0 \
      transformers \
      "huggingface-hub>0.20" \
      typer \
      typing-extensions \
      scikit-learn \
      numba \
    && ln -sf /usr/bin/pip3 /usr/bin/pip || true

# --- PyTorch CUDA 12.1 wheels ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir \
      "torch==2.3.1+cu121" "torchvision==0.18.1+cu121" \
      --index-url https://download.pytorch.org/whl/cu121

# --- ONNX + CV stack ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir \
      onnx==1.16.0 \
      onnxruntime-gpu==1.18.1 \
      opencv-python-headless==4.9.0.80 \
      "scikit-image<0.23" \
      "pillow<10.3" \
      "protobuf<5"

# --- InsightFace ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir insightface==0.7.3

# --- Extra deps needed by custom nodes ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir \
      segment-anything piexif requests safetensors einops

# --- (Optional) Repo requirements if present ---
RUN --mount=type=cache,target=/root/.cache/pip \
    if [ -f requirements.txt ]; then python3.10 -m pip install --no-cache-dir -r requirements.txt; fi

# --- Custom nodes (seeded into image) ---
WORKDIR /opt/ComfyUI/custom_nodes
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/Gourieff/ComfyUI-ReActor.git && \
    git clone --depth=1 https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth=1 https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth=1 https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git

# --- Create a seed copy we can expand into the volume on first run ---
RUN cp -a /opt/ComfyUI/custom_nodes /opt/_seed_custom_nodes

# ---- Disable ReActor SFW filter in the seed (intentional) ----
RUN set -eux; \
    f="/opt/_seed_custom_nodes/ComfyUI-ReActor/scripts/reactor_sfw.py"; \
    if [ -f "$f" ]; then \
      sed -i 's/return is_nsfw/return False/' "$f" || true; \
      sed -i 's/if nsfw_image.*:/if False:/' "$f" || true; \
    fi

# --- JupyterLab (optional) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir jupyterlab

# --- Ports ---
EXPOSE 8188 8888

# --- Declare persistent workspace ---
VOLUME ["/workspace"]

# --- Healthcheck (ComfyUI HTTP server) ---
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD curl -fsS http://localhost:8188/ || exit 1

# --- Startup ---
WORKDIR /workspace
COPY --chmod=755 start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh \
 && sed -i 's#/workspace/ComfyUI#/opt/ComfyUI#' /usr/local/bin/start.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
