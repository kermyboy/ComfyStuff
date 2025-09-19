@@
-FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
+FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
 
 # --- Base env ---
 ENV DEBIAN_FRONTEND=noninteractive \
     PIP_DEFAULT_TIMEOUT=120 \
     PIP_NO_INPUT=1 \
     PIP_DISABLE_PIP_VERSION_CHECK=1 \
+    PIP_ROOT_USER_ACTION=ignore \
     PYTHONUNBUFFERED=1 \
     # Optional: helps PyTorch memory fragmentation in long runs
     PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128,expandable_segments:True
 
 # --- System deps ---
-RUN apt-get update -y && apt-get install -y --no-install-recommends \
+RUN --mount=type=cache,target=/var/cache/apt \
+    --mount=type=cache,target=/var/lib/apt \
+    apt-get update -y && apt-get install -y --no-install-recommends \
       python3.10 python3.10-venv python3.10-distutils python3.10-dev \
       git git-lfs curl wget ffmpeg libgl1 libglib2.0-0 build-essential \
       cmake ninja-build cython3 \
  && git lfs install \
  && rm -rf /var/lib/apt/lists/*
 
 # --- Workdir & sources ---
 WORKDIR /workspace
-RUN git clone https://github.com/comfyanonymous/ComfyUI.git
+RUN --mount=type=cache,target=/root/.cache/git \
+    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git
 WORKDIR /workspace/ComfyUI
@@
 # --- InsightFace ---
-RUN --mount=type=cache,target=/root/.cache/pip \
-    pip install --no-cache-dir insightface==0.7.3
+RUN --mount=type=cache,target=/root/.cache/pip \
+    pip install --no-cache-dir insightface==0.7.3
@@
 # --- Custom nodes ---
 WORKDIR /workspace/ComfyUI/custom_nodes
-RUN git clone https://github.com/Gourieff/ComfyUI-ReActor.git && \
-    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
-    git clone https://github.com/rgthree/rgthree-comfy.git && \
-    git clone https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git
+RUN --mount=type=cache,target=/root/.cache/git \
+    git clone --depth=1 https://github.com/Gourieff/ComfyUI-ReActor.git && \
+    git clone --depth=1 https://github.com/cubiq/ComfyUI_IPAdapter_plus.git && \
+    git clone --depth=1 https://github.com/rgthree/rgthree-comfy.git && \
+    git clone --depth=1 https://github.com/stduhpf/ComfyUI--Wan22FirstLastFrameToVideoLatent.git
