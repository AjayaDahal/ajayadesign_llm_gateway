FROM ghcr.io/ai-dock/comfyui:v2-rocm-6.0-runtime-22.04-v0.2.7

# Install CogVideoX custom nodes for video generation
RUN cd /opt/ComfyUI/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-CogVideoXWrapper.git

# Install Python dependencies (upgrade pip first to avoid AssertionError)
RUN /opt/environments/python/comfyui/bin/pip install --upgrade pip && \
    /opt/environments/python/comfyui/bin/pip install --no-cache-dir \
        huggingface_hub \
        diffusers>=0.33.1 \
        accelerate>=0.33.0 \
        einops \
        peft

# Download T5-XXL fp8 text encoder (4.6 GB, needed for CogVideoX text encoding)
RUN mkdir -p /opt/ComfyUI/models/clip/t5 && \
    /opt/environments/python/comfyui/bin/python3 -c "\
from huggingface_hub import hf_hub_download; \
hf_hub_download(repo_id='comfyanonymous/flux_text_encoders', \
                filename='t5xxl_fp8_e4m3fn.safetensors', \
                local_dir='/opt/ComfyUI/models/clip/t5')"
