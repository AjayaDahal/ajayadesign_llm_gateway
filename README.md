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

 ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐
 │ Fish Speech  │  │  XTTS-v2    │  │   ComfyUI    │  │  Mem0 + Qdrant│
 │  TTS :8001   │  │  TTS :8002  │  │  :8188       │  │  Memory :8080 │
 └─────────────┘  └─────────────┘  └──────────────┘  └──────────────┘
```

---

## Services

| Service | Port | Image | Purpose |
|---------|------|-------|---------|
| **LiteLLM** | 4000 | `ghcr.io/berriai/litellm:main-latest` | OpenAI-compatible API gateway with auth, routing, fallbacks |
| **Ollama** | 11434 | `ollama/ollama:rocm` | LLM inference on AMD GPU (ROCm) |
| **Speaches** | 8000 | `ghcr.io/speaches-ai/speaches:0.9.0-rc.3-cpu` | Whisper STT + Kokoro TTS (OpenAI-compatible) |
| **Fish Speech** | 8001 | `fishaudio/fish-speech:latest` | Expressive TTS via OpenAudio S1-Mini |
| **XTTS-v2** | 8002 | `ghcr.io/coqui-ai/xtts-streaming-server:latest-cpu` | Multilingual voice cloning TTS |
| **ComfyUI** | 8188 | `ghcr.io/ai-dock/comfyui:v2-rocm-6.0` | Image gen (FLUX.1-schnell) + Video gen (CogVideoX-2b) |
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
| `GITHUB_TOKEN` | Optional | GitHub PAT for GPT-4o cloud fallback |

### 3. Launch

```bash
docker compose up -d
```

This single command:
1. Downloads all HuggingFace models (whisper, kokoro, fish-speech, xtts-v2, flux-schnell, cogvideox-2b) via the `model-downloader` init container
2. Starts Ollama with ROCm GPU passthrough
3. Pulls all Ollama models (deepseek-r1:32b/70b, deepseek-v2:16b, llama3.3, nomic-embed-text) via the `ollama-init` init container
4. Starts all services in dependency order with health checks

### 4. Interactive setup (alternative)

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

---

## Remote Access (LAN)

Find the server's IP:

```bash
hostname -I | awk '{print $1}'
```

From any machine on the same network, point clients to `http://<server-ip>:4000/v1`:

```bash
# Test from remote machine
curl http://192.168.1.185:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

### Continue.dev (VS Code)

Add to your Continue config (`~/.continue/config.yaml`):

```yaml
models:
  - model: deepseek-r1-32b
    title: DeepSeek R1 32B
    provider: openai
    apiBase: http://192.168.1.185:4000/v1
    apiKey: your-litellm-master-key

  - model: deepseek-v2-16b
    title: DeepSeek V2 16B
    provider: openai
    apiBase: http://192.168.1.185:4000/v1
    apiKey: your-litellm-master-key
```

### Environment variable (any OpenAI-compatible app)

```bash
export OPENAI_API_BASE=http://192.168.1.185:4000/v1
export OPENAI_API_KEY=your-litellm-master-key
```

### Firewall

If `ufw` is active, allow the gateway port:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 4000
```

---

## Project Structure

```
ai-stack/
├── docker-compose.yml        # Full stack orchestration (12 services)
├── litellm_config.yaml       # Gateway model routing & fallbacks
├── .env.example              # Environment variable template
├── .env                      # Your secrets (git-ignored)
├── setup.sh                  # Interactive setup wizard
├── continue-config.yaml      # Continue.dev sample config
├── mem0-api/
│   ├── Dockerfile            # Python 3.12 slim + mem0ai + FastAPI
│   └── main.py               # REST wrapper: /add, /search, /memories
├── scripts/
│   ├── download-models.sh    # HuggingFace model downloader (init container)
│   └── ollama-init.sh        # Ollama model puller (init container)
├── models/                   # Downloaded model weights (git-ignored)
│   ├── whisper-turbo/
│   ├── kokoro/
│   ├── fish-speech/
│   ├── xtts-v2/
│   ├── flux-schnell/
│   └── cogvideox-2b/
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
