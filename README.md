# Cognitive Silo

Private AI infrastructure stack running on **AMD Radeon PRO W7900** (48 GB VRAM) with ROCm. One `docker compose up -d` deploys LLMs, speech services, image/video generation, and project memory — all behind a single OpenAI-compatible API gateway.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Apps / IDE                          │
│           (Continue.dev, Python SDK, curl, etc.)                │
└──────────────────────────┬──────────────────────────────────────┘
                           │ OpenAI-compatible API
                           ▼
              ┌────────────────────────┐
              │   LiteLLM Gateway :4000│  ← auth, routing, fallbacks
              └────┬───────┬───────┬───┘
                   │       │       │
        ┌──────────┘       │       └──────────┐
        ▼                  ▼                  ▼
 ┌─────────────┐   ┌─────────────┐   ┌──────────────┐
 │ Ollama :11434│   │Speaches:8000│   │ GitHub Models │
 │   (ROCm)    │   │ STT + TTS   │   │  (fallback)   │
 └──────┬──────┘   └─────────────┘   └──────────────┘
        │
        ├── deepseek-r1:32b
        ├── deepseek-v2:16b
        ├── deepseek-r1:70b
        ├── llama3.3
        └── nomic-embed-text

 ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
 │ Fish Speech  │  │  XTTS-v2    │  │  MusicGen    │  │   ComfyUI    │  │  Mem0 + Qdrant│
 │  TTS :8001   │  │  TTS :8002  │  │  Music :8003 │  │  :8188       │  │  Memory :8080 │
 └─────────────┘  └─────────────┘  └──────────────┘  └──────────────┘  └──────────────┘
```

---

## Services

| Service | Port | Image | Purpose |
|---------|------|-------|---------|
| **Open WebUI** | 3000 | `ghcr.io/open-webui/open-webui:main` | ChatGPT-style playground (chat, TTS, STT, image gen) |
| **LiteLLM** | 4000 | `ghcr.io/berriai/litellm:main-latest` | OpenAI-compatible API gateway with auth, routing, fallbacks |
| **Ollama** | 11434 | `ollama/ollama:rocm` | LLM inference on AMD GPU (ROCm) |
| **Speaches** | 8000 | `ghcr.io/speaches-ai/speaches:0.9.0-rc.3-cpu` | Whisper STT + Kokoro TTS (OpenAI-compatible) |
| **Fish Speech** | 8001 | `fishaudio/fish-speech:latest` | Expressive TTS via OpenAudio S1-Mini |
| **XTTS-v2** | 8002 | `ghcr.io/coqui-ai/xtts-streaming-server:latest-cpu` | Multilingual voice cloning TTS (58 speakers, 17 langs) |
| **MusicGen API** | 8003 | Custom build (`./musicgen-api`) | Text-to-music generation (Meta AudioCraft) |
| **MusicGen UI** | 8004 | Custom build (`./musicgen-ui`) | Gradio playground for music generation |
| **ComfyUI** | 8188 | Custom build (`./comfyui`) | Image gen (FLUX.1-schnell) + Video gen (CogVideoX-2b) |
| **Mem0** | 8080 | Custom build (`./mem0-api`) | Long-term project memory with per-user isolation |
| **Qdrant** | 6333 | `qdrant/qdrant:latest` | Vector database for Mem0 embeddings |
| **PostgreSQL** | 5432 | `postgres:16` | LiteLLM persistence / analytics |
| **Redis** | — | `redis:7-alpine` | Caching / rate limiting |

---

## Models

### LLMs (via Ollama, GPU-accelerated)

| Model | Gateway Name | VRAM | Use Case |
|-------|-------------|------|----------|
| DeepSeek-R1 32B | `deepseek-r1-32b` | ~20 GB | Reasoning, coding |
| DeepSeek-V2 16B | `deepseek-v2-16b` | ~10 GB | Fast general-purpose |
| DeepSeek-R1 70B | `deepseek-r1-70b` | ~42 GB | Heavy reasoning (exclusive) |
| Llama 3.3 | `llama3-8b` | ~42 GB | General / scripting |
| nomic-embed-text | `nomic-embed-text` | ~300 MB | Embeddings (768 dims) |

> `OLLAMA_MAX_LOADED_MODELS=2` — Ollama hot-swaps models that don't fit in VRAM simultaneously.

### Speech

| Model | Gateway Name | Type |
|-------|-------------|------|
| Whisper Large v3 Turbo | `whisper-turbo` | Speech-to-Text |
| Kokoro 82M | `kokoro-tts` | Text-to-Speech |
| OpenAudio S1-Mini | *(Fish Speech Gradio)* | Text-to-Speech |
| XTTS-v2 | *(direct API)* | Voice Cloning TTS |

### Music (via MusicGen API)

| Model | Type |
|-------|------|
| MusicGen Small (300M) | Text-to-music generation |

### Creative (via ComfyUI)

| Model | Type |
|-------|------|
| FLUX.1-schnell FP8 | Fast image generation |
| CogVideoX-2b | Video generation |

### Cloud Fallback

All LLM models fall back to **GPT-4o** via GitHub Models when the local GPU is busy (requires `GITHUB_TOKEN`).

---

## Quick Start

### 1. Clone & configure

```bash
git clone https://github.com/AjayaDahal/ajayadesign_llm_gateway.git
cd ajayadesign_llm_gateway/ai-stack

cp .env.example .env
# Edit .env with your secrets
```

### 2. Set environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `LITELLM_MASTER_KEY` | **Yes** | API key for gateway auth |
| `POSTGRES_PASSWORD` | **Yes** | PostgreSQL password |
| `HF_TOKEN` | Recommended | HuggingFace token for gated models (Fish Speech) |
| `DIRECT_ADDRESS` | Recommended | Tailscale IP for ComfyUI remote login redirects (default: `localhost`) |
| `GITHUB_TOKEN` | Optional | GitHub PAT for GPT-4o cloud fallback |
| `OPEN_WEBUI_SECRET_KEY` | Optional | Open WebUI session encryption key |
| `OPEN_WEBUI_AUTH` | Optional | Set `false` for single-user / LAN-only (default: `true`) |

### 3. Launch

```bash
docker compose up -d
```

This single command:
1. Downloads HuggingFace models (fish-speech, xtts-v2, flux-schnell, cogvideox-2b) via the `model-downloader` init container
2. Starts Ollama with ROCm GPU passthrough
3. Pulls all Ollama models (deepseek-r1:32b/70b, deepseek-v2:16b, llama3.3, nomic-embed-text) via the `ollama-init` init container
4. Starts Speaches and auto-installs the Whisper STT model via `speaches-init`
5. Launches Open WebUI playground on **http://localhost:3000**
6. Starts all services in dependency order with health checks

### 4. Open the Web UIs

Once everything is up:

| UI | URL | What you can do |
|----|-----|------------------|
| **Open WebUI** | [localhost:3000](http://localhost:3000) | Chat with LLMs, voice conversations (TTS/STT), image generation |
| **MusicGen Playground** | [localhost:8004](http://localhost:8004) | Generate music from text descriptions |
| **ComfyUI** | [localhost:8188](http://localhost:8188) | Node-based image/video generation workflows |
| **Fish Speech** | [localhost:8001](http://localhost:8001) | Expressive text-to-speech with voice cloning |

> **First time?** Open WebUI at `:3000` will ask you to create an admin account. After that you'll see all your local models ready to chat with.

### 5. Interactive setup (alternative)

```bash
chmod +x setup.sh
./setup.sh
```

The interactive installer prompts for API keys, checks prerequisites, downloads models, and verifies health.

---

## Usage

### Gateway endpoint

All services are accessible through the LiteLLM gateway at `http://<host>:4000/v1`.

### Chat completions

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1-32b",
    "messages": [{"role": "user", "content": "Explain quicksort in 3 sentences"}]
  }'
```

### Streaming

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1-32b",
    "messages": [{"role": "user", "content": "Write a haiku about GPUs"}],
    "stream": true
  }'
```

### Embeddings

```bash
curl http://localhost:4000/v1/embeddings \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-embed-text",
    "input": "The quick brown fox"
  }'
```

### Speech-to-Text (Whisper)

```bash
curl http://localhost:4000/v1/audio/transcriptions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -F "model=whisper-turbo" \
  -F "file=@recording.wav"
```

### Text-to-Speech (Kokoro)

```bash
curl http://localhost:4000/v1/audio/speech \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro-tts",
    "input": "Hello from Cognitive Silo!",
    "voice": "af_heart"
  }' --output speech.wav
```

### Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="your-litellm-master-key",
)

response = client.chat.completions.create(
    model="deepseek-r1-32b",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

### Mem0 (Project Memory)

```bash
# Add a memory
curl -X POST http://localhost:8080/add \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "The W7900 has 48GB VRAM"}],
    "user_id": "my-project"
  }'

# Search memories
curl -X POST http://localhost:8080/search \
  -H "Content-Type: application/json" \
  -d '{"query": "GPU memory", "user_id": "my-project"}'

# List all memories for a project
curl http://localhost:8080/memories/my-project
```

### Music Generation (MusicGen)

```bash
# Generate music from text prompt (returns WAV file)
curl -X POST http://localhost:8003/generate \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "upbeat electronic dance music with heavy bass and synth leads",
    "duration": 10.0
  }' --output music.wav

# Generate ambient background music
curl -X POST http://localhost:8003/generate \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "calm ambient piano with gentle strings, peaceful and relaxing",
    "duration": 15.0,
    "temperature": 0.8
  }' --output ambient.wav

# Check available models
curl http://localhost:8003/models
```

### Voice Cloning (XTTS-v2)

```bash
# List available studio speakers
curl http://localhost:8002/studio_speakers | python3 -m json.tool | head -20

# Generate speech with a studio voice
curl -X POST http://localhost:8002/tts_to_audio \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hello from Cognitive Silo!",
    "speaker_wav": "Claribel Dervla",
    "language": "en"
  }' --output cloned_voice.wav
```

### Video Generation (CogVideoX-2b via ComfyUI)

ComfyUI handles video generation through the CogVideoX-2b model (14 GB diffusers). Two workflow JSONs are provided in `workflows/`.

#### Browser (ComfyUI Web UI)

1. Open **http://localhost:8188** (or `http://100.104.29.113:8188` via Tailscale)
2. Login at the ai-dock auth page (user: `admin`, password: your `COMFYUI_PASSWORD`)
3. Click **Load** → select `cogvideox-2b-text-to-video.json` from `workflows/`
4. Edit the **Positive Prompt** node with your description
5. Click **Queue Prompt** — generates 17 frames in ~200 seconds on W7900

> **Tip:** The `SaveAnimatedWEBP` node outputs animated WEBP. For individual PNG frames, use the `cogvideox-2b-frames.json` workflow instead.

#### Workflow nodes (what the JSON contains)

```
DownloadAndLoadCogVideoModel (THUDM/CogVideoX-2b, fp16, cpu_offload)
    ↓ model + vae
CLIPLoader (t5/t5xxl_fp8_e4m3fn.safetensors, sd3)
    ↓ clip
CogVideoTextEncode (positive prompt) + CogVideoTextEncode (negative prompt)
    ↓ conditioning
EmptyLatentImage (480×320)
    ↓ latent
CogVideoSampler (17 frames, 20 steps, cfg 6.0, CogVideoXDDIM)
    ↓ samples
CogVideoDecode (vae_tiling=true)
    ↓ images
SaveAnimatedWEBP / SaveImage
```

#### API (curl)

```bash
# Queue a CogVideoX-2b video generation via ComfyUI API
curl -X POST http://localhost:8188/api/prompt \
  -H "Authorization: Bearer ${COMFYUI_API_TOKEN:-cognitive-silo-comfyui-token}" \
  -H "Content-Type: application/json" \
  -d @workflows/cogvideox-2b-text-to-video.json

# Check generation progress
curl http://localhost:8188/api/queue \
  -H "Authorization: Bearer ${COMFYUI_API_TOKEN:-cognitive-silo-comfyui-token}"
```

#### CogVideoX-2b settings reference

| Parameter | Default | Notes |
|-----------|---------|-------|
| Resolution | 480×320 | CogVideoX-2b native; higher = slower + more VRAM |
| Frames | 17 | Number of video frames |
| Steps | 20 | Sampling steps (higher = better quality, slower) |
| CFG | 6.0 | Classifier-free guidance scale |
| Scheduler | CogVideoXDDIM | Also try `DPM++`, `Euler` |
| Precision | fp16 | fp16 recommended for W7900 |
| CPU Offload | true | Moves unused layers to RAM to save VRAM |
| VAE Tiling | true | Reduces VRAM during decode |

---

## Remote Access

The gateway can be reached from other machines in two ways:

### Option A: Tailscale (recommended — works anywhere)

Tailscale creates a secure private network between your machines, accessible from anywhere (home, office, coffee shop) without port forwarding or firewall rules.

#### 1. Install Tailscale on the server (already done)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Server Tailscale IP: `100.104.29.113`

#### 2. Install Tailscale on your other machine(s)

```bash
# Linux
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# macOS
brew install tailscale
sudo tailscale up

# Windows — download from https://tailscale.com/download
```

Log in with the same Tailscale account (or accept a share invite). Run `tailscale status` to confirm both machines appear on the tailnet.

#### 3. Use the gateway from your other machine

```bash
# Verify connectivity
curl http://100.104.29.113:4000/health/liveliness

# List models
curl http://100.104.29.113:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Chat completion
curl http://100.104.29.113:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1-32b",
    "messages": [{"role": "user", "content": "Hello from my laptop!"}]
  }'
```

#### 4. Python (OpenAI SDK via Tailscale)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://100.104.29.113:4000/v1",
    api_key="your-litellm-master-key",
)

response = client.chat.completions.create(
    model="deepseek-r1-32b",
    messages=[{"role": "user", "content": "Hello from my laptop!"}],
)
print(response.choices[0].message.content)
```

#### 5. Continue.dev (VS Code on remote machine)

Add to `~/.continue/config.yaml` on the remote machine:

```yaml
models:
  - model: deepseek-r1-32b
    title: DeepSeek R1 32B
    provider: openai
    apiBase: http://100.104.29.113:4000/v1
    apiKey: your-litellm-master-key

  - model: deepseek-v2-16b
    title: DeepSeek V2 16B
    provider: openai
    apiBase: http://100.104.29.113:4000/v1
    apiKey: your-litellm-master-key

  - model: deepseek-r1-70b
    title: DeepSeek R1 70B (Heavy)
    provider: openai
    apiBase: http://100.104.29.113:4000/v1
    apiKey: your-litellm-master-key

tabAutocompleteModel:
  model: deepseek-v2-16b
  title: Autocomplete
  provider: openai
  apiBase: http://100.104.29.113:4000/v1
  apiKey: your-litellm-master-key

embeddingsProvider:
  model: nomic-embed-text
  provider: openai
  apiBase: http://100.104.29.113:4000/v1
  apiKey: your-litellm-master-key
```

#### 6. Environment variable (any OpenAI-compatible app)

```bash
export OPENAI_API_BASE=http://100.104.29.113:4000/v1
export OPENAI_API_KEY=your-litellm-master-key
```

This works with any tool that supports the OpenAI API: `aider`, `shell-gpt`, `llm`, Cursor, Windsurf, etc.

#### 7. Access other services via Tailscale

| Service | URL | Notes |
|---------|-----|-------|
| LiteLLM Gateway | `http://100.104.29.113:4000` | Main API (OpenAI-compatible) |
| Speaches STT/TTS | `http://100.104.29.113:8000` | Whisper + Kokoro (OpenAI-compatible) |
| Fish Speech TTS | `http://100.104.29.113:8001` | Gradio WebUI + API |
| XTTS-v2 TTS | `http://100.104.29.113:8002` | Voice cloning API (58 speakers) |
| MusicGen | `http://100.104.29.113:8003` | Text-to-music generation |
| Mem0 Memory | `http://100.104.29.113:8080` | Project memory REST API |
| ComfyUI | `http://100.104.29.113:8188` | Image/video generation UI |
| Ollama (direct) | `http://100.104.29.113:11434` | For debugging |

#### Tailscale tips

- **MagicDNS**: If enabled in Tailscale admin, use `http://ai-is-taking-over:4000` instead of the IP.
- **Tailscale SSH**: `tailscale ssh ai-is-taking-over` for passwordless SSH.
- **Share with others**: Use Tailscale node sharing to give teammates access without exposing ports.
- **Always-on**: The server stays on the tailnet as long as `tailscaled` is running (it starts on boot by default).

---

### Option B: LAN only (same network)

If both machines are on the same local network:

```bash
# Find server LAN IP
hostname -I | awk '{print $1}'
# → 192.168.1.185
```

```bash
curl http://192.168.1.185:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

Replace `100.104.29.113` with `192.168.1.185` in all examples above.

### Firewall

If `ufw` is active, allow access:

```bash
# Allow Tailscale (all traffic on tailnet is already encrypted)
sudo ufw allow in on tailscale0

# Or allow LAN only
sudo ufw allow from 192.168.1.0/24 to any port 4000
```

---

## Project Structure

```
ai-stack/
├── docker-compose.yml        # Full stack orchestration (15 services)
├── litellm_config.yaml       # Gateway model routing & fallbacks
├── .env.example              # Environment variable template
├── .env                      # Your secrets (git-ignored)
├── setup.sh                  # Interactive setup wizard
├── continue-config.yaml      # Continue.dev sample config
├── mem0-api/
│   ├── Dockerfile            # Python 3.12 slim + mem0ai + FastAPI
│   └── main.py               # REST wrapper: /add, /search, /memories
├── musicgen-api/
│   ├── Dockerfile            # Python 3.11 slim + transformers + torch
│   └── main.py               # REST wrapper: /generate, /health, /models
├── musicgen-ui/
│   ├── Dockerfile            # Python 3.11 slim + gradio
│   └── app.py                # Gradio playground for music generation
├── comfyui/
│   └── Dockerfile            # Custom ComfyUI image (CogVideoX nodes + T5-XXL)
├── workflows/
│   ├── cogvideox-2b-text-to-video.json   # CogVideoX animated WEBP output
│   └── cogvideox-2b-frames.json          # CogVideoX individual PNG frames
├── scripts/
│   ├── download-models.sh    # HuggingFace model downloader (init container)
│   ├── configure-openwebui-images.py  # FLUX workflow setup for Open WebUI
│   └── ollama-init.sh        # Ollama model puller (init container)
├── dashboard.html            # Single-page service portal with health checks
├── models/                   # Downloaded model weights (git-ignored)
│   ├── speaches-cache/       # Whisper + Kokoro (auto-managed by Speaches)
│   ├── fish-speech/
│   ├── xtts-v2/
│   ├── flux-schnell/
│   ├── cogvideox-2b/
│   ├── musicgen-cache/
│   └── ollama/               # Ollama model blobs
└── prompts/                  # System prompt templates
```

---

## Health & Monitoring

```bash
# Gateway liveness
curl http://localhost:4000/health/liveliness

# List all available models
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Container status
docker compose ps

# GPU utilization (inside Ollama container)
docker exec ollama-w7900 rocm-smi

# Mem0 health
curl http://localhost:8080/health
```

---

## Key Design Decisions

- **Single gateway** — All LLM/STT/TTS traffic routes through LiteLLM on port 4000 with unified auth.
- **Init containers** — `model-downloader` and `ollama-init` run once on first deploy, then exit. Models are cached in volumes, so subsequent `docker compose up` starts instantly.
- **Named volumes** — Persistent data (Ollama models, Postgres, Qdrant, Redis) lives in Docker named volumes, not bind mounts. Survives `docker compose down`.
- **Health checks everywhere** — Every service has a health check. Dependent services wait via `condition: service_healthy`.
- **Memory isolation** — Mem0 uses `user_id` as a namespace key. Each project gets its own memory silo.
- **Cloud fallback** — When the local GPU is saturated, LiteLLM automatically falls back to GPT-4o via GitHub Models.
- **No curl in containers** — Health checks use `bash /dev/tcp` or `python3 urllib` since most images don't ship curl.

---

## Hardware Requirements

| Resource | Minimum | This Setup |
|----------|---------|------------|
| GPU VRAM | 16 GB (for smallest models) | 48 GB (W7900) |
| RAM | 32 GB | 62 GB |
| CPU Cores | 8 | 32 |
| Disk | 100 GB (models) | 500 GB+ recommended |
| GPU Driver | ROCm 5.x+ | ROCm via container |

---

## License

Private project. Not for redistribution.
