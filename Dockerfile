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
    XDG_CACHE_HOME=/workspace/.cache

# --- System deps ---
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update -y && apt-get install -y --no-install-recommends \
      software-properties-common ca-certificates git git-lfs curl wget \
      ffmpeg libgl1 libglib2.0-0 build-essential cmake ninja-build \
      rsync pkg-config \
      python3.11 python3.11-dev python3.11-venv python3-pip \
 && git lfs install \
 && ln -sf /usr/bin/python3.11 /usr/bin/python \
 && ln -sf /usr/bin/pip3 /usr/bin/pip \
 && rm -rf /var/lib/apt/lists/*

# --- ComfyUI code ---
WORKDIR /opt
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
WORKDIR /opt/ComfyUI

# --- Python bootstrap ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip setuptools wheel "cython<3"

# --- PyTorch CUDA 12.1 (needs >=2.4 for RMSNorm) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir \
      "torch==2.4.0+cu121" "torchvision==0.19.0+cu121" \
      --index-url https://download.pytorch.org/whl/cu121
      
# --- ComfyUI dependencies (install its requirements with a NumPy 1.x guard) ---
# Place this AFTER cloning /opt/ComfyUI and AFTER your PyTorch/cu121 install.
RUN --mount=type=cache,target=/root/.cache/pip bash -lc '\
  set -euo pipefail; \
  # 1) Ensure a compatible NumPy is present before resolution
  python -m pip install --no-cache-dir "numpy<2"; \
  \
  # 2) Install ComfyUI’s own requirements
  python -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt; \
  \
  # 3) Extras frequently requested at runtime (avoid Manager auto-installs)
  python -m pip install --no-cache-dir \
    "av>=12" \
    alembic \
    pydantic-settings \
    comfyui-workflow-templates \
    comfyui-embedded-docs \
    kornia spandrel matplotlib insightface; \
  \
  # 4) Belt-and-braces: keep NumPy on 1.x if anything tried to bump it
  python -m pip install --no-cache-dir --upgrade "numpy==1.26.4" --no-deps \
'

# --- Audio & SDE + Video I/O (fixes import errors / warnings) ---
# Use extra-index so PyPI remains primary (for torchsde/av), while PyTorch CUDA wheels are available.
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir \
      --extra-index-url https://download.pytorch.org/whl/cu121 \
      torchaudio==2.4.0+cu121 \
      torchsde==0.2.6 \
      "av>=12"

# --- Core scientific/video deps (pin NumPy < 2; headless OpenCV) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir \
      "numpy<2" \
      opencv-python-headless==4.9.0.80 \
      onnx==1.16.0 \
      onnxruntime-gpu==1.18.1 \
      "scikit-image<0.23" \
      "pillow<10.3" \
      "protobuf<5" \
      imageio imageio-ffmpeg

# --- Diffusers stack for Wan ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir \
      "diffusers>=0.33.0" \
      "accelerate>=0.30" \
      "transformers>=4.44" \
      "huggingface-hub>=0.20" \
      "peft>=0.17.0" \
      sentencepiece einops safetensors requests

# --- (Optional) JupyterLab ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir jupyterlab uv

# --- Reassert safe numeric stack (defend against accidental NumPy 2 upgrades) ---
# Place this AFTER all other pip installs that might pull numpy, so it "wins".
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir --upgrade \
      "numpy==1.26.4" \
      "opencv-python-headless==4.9.0.80" \
      "onnxruntime-gpu==1.18.1" --force-reinstall --no-deps

# --- Custom nodes (seeded into image) ---
WORKDIR /opt/ComfyUI/custom_nodes
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth=1 https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth=1 https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git && \
    git clone --depth=1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git

# --- ComfyUI-Manager dependencies ---
RUN --mount=type=cache,target=/root/.cache/pip bash -lc \
  REQ=/opt/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
  if [ -f "$REQ" ]; then \
    python -m pip install --no-cache-dir -r "$REQ"; \
  else \
    python -m pip install --no-cache-dir \
      gitpython>=3.1.43 toml rich \
      pygithub typer typing-extensions matrix-client==0.4.0; \
  fi

# --- Make package managers visible to Manager ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir uv && \
    ln -sf /usr/bin/pip3 /usr/local/bin/pip || true && \
    ln -sf /usr/bin/pip3 /usr/bin/pip || true && \
    ln -sf /usr/bin/python3.11 /usr/local/bin/python || true

# --- Install WanVideoWrapper requirements explicitly (future-proof) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    if [ -f /opt/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper/requirements.txt ]; then \
      python -m pip install --no-cache-dir -r /opt/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper/requirements.txt; \
    fi

# --- Create a seed copy of custom_nodes to populate volume on first run ---
RUN cp -a /opt/ComfyUI/custom_nodes /opt/_seed_custom_nodes

# --- Ports & workspace ---
EXPOSE 8188 8888
VOLUME ["/workspace"]

# --- Healthcheck (ComfyUI HTTP server) ---
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD curl -fsS http://localhost:8188/ || exit 1

# --- Keep uv quiet about hardlinks ---
ENV UV_LINK_MODE=copy

# --- Startup ---
WORKDIR /workspace
COPY --chmod=755 start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh \
 && sed -i 's#/workspace/ComfyUI#/opt/ComfyUI#' /usr/local/bin/start.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
