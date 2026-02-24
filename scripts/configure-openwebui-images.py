#!/usr/bin/env python3
"""Configure Open WebUI image generation settings for FLUX via ComfyUI."""

import json
import urllib.request
import jwt

# Generate admin JWT
token = jwt.encode(
    {"id": "4c4cedf3-50ac-4ce6-aa35-9da67f25cf02"},
    "cognitive-silo-secret-2026",
    algorithm="HS256",
)

BASE = "http://localhost:8080/api/v1"
HEADERS = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
}

# FLUX-optimized ComfyUI workflow (API format)
workflow = {
    "3": {
        "inputs": {
            "seed": 0,
            "steps": 4,
            "cfg": 1.0,
            "sampler_name": "euler",
            "scheduler": "simple",
            "denoise": 1,
            "model": ["4", 0],
            "positive": ["6", 0],
            "negative": ["7", 0],
            "latent_image": ["5", 0],
        },
        "class_type": "KSampler",
        "_meta": {"title": "KSampler"},
    },
    "4": {
        "inputs": {"ckpt_name": "flux1-schnell-fp8.safetensors"},
        "class_type": "CheckpointLoaderSimple",
        "_meta": {"title": "Load Checkpoint"},
    },
    "5": {
        "inputs": {"width": 1024, "height": 1024, "batch_size": 1},
        "class_type": "EmptyLatentImage",
        "_meta": {"title": "Empty Latent Image"},
    },
    "6": {
        "inputs": {"text": "Prompt", "clip": ["4", 1]},
        "class_type": "CLIPTextEncode",
        "_meta": {"title": "CLIP Text Encode (Prompt)"},
    },
    "7": {
        "inputs": {"text": "", "clip": ["4", 1]},
        "class_type": "CLIPTextEncode",
        "_meta": {"title": "CLIP Text Encode (Negative)"},
    },
    "8": {
        "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
        "class_type": "VAEDecode",
        "_meta": {"title": "VAE Decode"},
    },
    "9": {
        "inputs": {"filename_prefix": "ComfyUI", "images": ["8", 0]},
        "class_type": "SaveImage",
        "_meta": {"title": "Save Image"},
    },
}

# Node mapping tells Open WebUI which nodes to patch at runtime
workflow_nodes = [
    {"type": "model", "node_ids": ["4"], "key": "ckpt_name"},
    {"type": "prompt", "node_ids": ["6"], "key": "text"},
    {"type": "negative_prompt", "node_ids": ["7"], "key": "text"},
    {"type": "width", "node_ids": ["5"], "key": "width"},
    {"type": "height", "node_ids": ["5"], "key": "height"},
    {"type": "steps", "node_ids": ["3"], "key": "steps"},
    {"type": "seed", "node_ids": ["3"], "key": "seed"},
    {"type": "n", "node_ids": ["5"], "key": "batch_size"},
]

config_update = {
    "ENABLE_IMAGE_GENERATION": True,
    "ENABLE_IMAGE_PROMPT_GENERATION": True,
    "IMAGE_GENERATION_ENGINE": "comfyui",
    "IMAGE_GENERATION_MODEL": "flux1-schnell-fp8.safetensors",
    "IMAGE_SIZE": "1024x1024",
    "IMAGE_STEPS": 4,
    "IMAGES_OPENAI_API_BASE_URL": "https://api.openai.com/v1",
    "IMAGES_OPENAI_API_KEY": "",
    "IMAGES_OPENAI_API_VERSION": "",
    "IMAGES_OPENAI_API_PARAMS": {},
    "AUTOMATIC1111_BASE_URL": "",
    "AUTOMATIC1111_API_AUTH": "",
    "AUTOMATIC1111_PARAMS": {},
    "COMFYUI_BASE_URL": "http://comfyui:8188",
    "COMFYUI_API_KEY": "cognitive-silo-comfyui-token",
    "COMFYUI_WORKFLOW": json.dumps(workflow),
    "COMFYUI_WORKFLOW_NODES": workflow_nodes,
    "IMAGES_GEMINI_API_BASE_URL": "",
    "IMAGES_GEMINI_API_KEY": "",
    "IMAGES_GEMINI_ENDPOINT_METHOD": "",
    "ENABLE_IMAGE_EDIT": False,
    "IMAGE_EDIT_ENGINE": "openai",
    "IMAGE_EDIT_MODEL": "",
    "IMAGE_EDIT_SIZE": "",
    "IMAGES_EDIT_OPENAI_API_BASE_URL": "https://api.openai.com/v1",
    "IMAGES_EDIT_OPENAI_API_KEY": "",
    "IMAGES_EDIT_OPENAI_API_VERSION": "",
    "IMAGES_EDIT_GEMINI_API_BASE_URL": "",
    "IMAGES_EDIT_GEMINI_API_KEY": "",
    "IMAGES_EDIT_COMFYUI_BASE_URL": "",
    "IMAGES_EDIT_COMFYUI_API_KEY": "",
    "IMAGES_EDIT_COMFYUI_WORKFLOW": "",
    "IMAGES_EDIT_COMFYUI_WORKFLOW_NODES": [],
}

print("Updating Open WebUI image config...")
print(f"  Model: {config_update['IMAGE_GENERATION_MODEL']}")
print(f"  Size: {config_update['IMAGE_SIZE']}")
print(f"  Steps: {config_update['IMAGE_STEPS']}")
print(f"  Workflow nodes: {len(workflow_nodes)} mappings")

req = urllib.request.Request(
    f"{BASE}/images/config/update",
    data=json.dumps(config_update).encode(),
    headers=HEADERS,
    method="POST",
)

try:
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
        print(f"\nSuccess! HTTP {resp.status}")
        print(f"  Engine: {result.get('IMAGE_GENERATION_ENGINE')}")
        print(f"  Model: {result.get('IMAGE_GENERATION_MODEL')}")
        print(f"  Steps: {result.get('IMAGE_STEPS')}")
        print(f"  Size: {result.get('IMAGE_SIZE')}")
        nodes = result.get("COMFYUI_WORKFLOW_NODES", [])
        print(f"  Workflow nodes: {len(nodes)} mappings")
except urllib.error.HTTPError as e:
    print(f"Error: HTTP {e.code}")
    print(e.read().decode())
