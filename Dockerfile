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
      python3.11 python3.11-dev python3.11-venv python3-pip python-is-python3 \
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

# Optional: torchaudio in the same index
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir \
      "torchaudio==2.4.0+cu121" \
      --index-url https://download.pytorch.org/whl/cu121

# --- Global guard-rails for resolution (tiny constraints, not a lockfile) ---
RUN printf '%s\n' \
  'numpy<2' \
  'av>=12' \
  'torch==2.4.0+cu121' \
  'torchvision==0.19.0+cu121' \
  'torchaudio==2.4.0+cu121' \
  > /etc/pip-constraints.txt
ENV PIP_CONSTRAINT=/etc/pip-constraints.txt

ENV PIP_CONSTRAINT=/etc/pip-constraints.txt

# --- Install ComfyUI dependencies from its requirements (requirements-first) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt

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
# --- Extras for custom nodes that failed in logs ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir \
      "matplotlib==3.8.*" \        
      "scikit-image==0.24.*" \     
      "numba==0.59.*" \            
      "onnx==1.16.*" \             
      "onnxruntime-gpu==1.19.*" \  
      "insightface>=0.7,<0.8" \    
      "imageio-ffmpeg>=0.4.9"      
      
# --- ComfyUI-Manager dependencies (if it ships requirements) ---
RUN --mount=type=cache,target=/root/.cache/pip bash -lc '\
  REQ=/opt/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
  if [ -f "$REQ" ]; then \
    python -m pip install --no-cache-dir -r "$REQ"; \
  else \
    python -m pip install --no-cache-dir \
      "gitpython>=3.1.43" toml rich \
      pygithub typer typing-extensions "matrix-client==0.4.0"; \
  fi'

# --- Auto-install each custom node's requirements*.txt (requirements-first) ---
RUN --mount=type=cache,target=/root/.cache/pip bash -lc '\
  shopt -s nullglob; \
  files=(/opt/ComfyUI/custom_nodes/*/requirements*.txt); \
  if (( ${#files[@]} )); then \
    echo "Installing custom node requirements:"; \
    for f in "${files[@]}"; do echo "  -> $f"; python -m pip install --no-cache-dir -r "$f"; done; \
  else \
    echo "No custom node requirements found."; \
  fi'

# --- Extras occasionally missing upstream (tiny) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir torchsde==0.2.6

# --- Seed copy of custom_nodes to populate volume on first run ---
RUN cp -a /opt/ComfyUI/custom_nodes /opt/_seed_custom_nodes

# --- (Optional) JupyterLab & uv (single install) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir jupyterlab uv

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
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh \
    && sed -i 's/\r$//' /usr/local/bin/start.sh \
    && sed -i 's#/workspace/ComfyUI#/opt/ComfyUI#' /usr/local/bin/start.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
