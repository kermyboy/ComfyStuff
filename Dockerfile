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
      python3.10 python3.10-dev python3-pip \
      git git-lfs curl wget ffmpeg libgl1 libglib2.0-0 build-essential \
      cmake ninja-build cython3 ca-certificates \
 && git lfs install \
 && rm -rf /var/lib/apt/lists/*

# --- Code lives OUTSIDE the /workspace mount to avoid being clobbered ---
WORKDIR /opt
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
WORKDIR /opt/ComfyUI

# --- Python deps into system Python (RunPod-friendly, no venv) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --upgrade pip setuptools wheel && \
    python3.10 -m pip install --no-cache-dir \
      "numpy==1.26.4" "cython<3"

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

# --- Extra deps needed by your custom nodes ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir \
      segment-anything piexif requests safetensors einops

# --- (Optional) Repo requirements if present ---
RUN --mount=type=cache,target=/root/.cache/pip \
    if [ -f requirements.txt ]; then python3.10 -m pip install --no-cache-dir -r requirements.txt; fi

# --- Custom nodes (baked into image under /opt) ---
WORKDIR /opt/ComfyUI/custom_nodes
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 https://github.com/Gourieff/ComfyUI-ReActor.git && \
    git clone --depth=1 https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
    git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth=1 https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth=1 https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git

# Persist custom_nodes on /workspace
RUN mkdir -p /workspace/custom_nodes && \
    rsync -a /opt/ComfyUI/custom_nodes/ /workspace/custom_nodes/ || true && \
    rm -rf /opt/ComfyUI/custom_nodes && \
    ln -s /workspace/custom_nodes /opt/ComfyUI/custom_nodes


# ---- Disable ReActor SFW filter (intentional) ----
RUN set -eux; \
    f="/opt/ComfyUI/custom_nodes/ComfyUI-ReActor/scripts/reactor_sfw.py"; \
    if [ -f "$f" ]; then \
      sed -i 's/return is_nsfw/return False/' "$f" || true; \
      sed -i 's/if nsfw_image.*:/if False:/' "$f" || true; \
    fi

# --- Persistent dirs: models, io, user (on volume) ---
RUN mkdir -p /workspace/models/{checkpoints,vae,clip,loras,controlnet,upscale_models,embeddings,wan,insightface/antelopev2,insightface/buffalo_l} \
           /workspace/{input,output} \
           /workspace/user/default/workflows && \
    # link ReActor models to persistent store
    mkdir -p /workspace/reactor_models && \
    ln -sfn /workspace/reactor_models /opt/ComfyUI/custom_nodes/ComfyUI-ReActor/models && \
    # link ComfyUI paths to persistent volume
    rm -rf /opt/ComfyUI/models /opt/ComfyUI/input /opt/ComfyUI/output /opt/ComfyUI/user && \
    ln -s /workspace/models /opt/ComfyUI/models && \
    ln -s /workspace/input  /opt/ComfyUI/input  && \
    ln -s /workspace/output /opt/ComfyUI/output && \
    ln -s /workspace/user   /opt/ComfyUI/user

# --- JupyterLab (optional) ---
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.10 -m pip install --no-cache-dir jupyterlab

# --- Ports ---
EXPOSE 8188 8888

# --- Healthcheck (ComfyUI HTTP server) ---
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD curl -fsS http://localhost:8188/ || exit 1

# --- Startup ---
WORKDIR /workspace
COPY --chmod=755 start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh \
 && sed -i 's#/workspace/ComfyUI#/opt/ComfyUI#' /usr/local/bin/start.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
