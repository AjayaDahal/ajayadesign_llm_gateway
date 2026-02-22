#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  Cognitive Silo — Interactive Setup                             ║
# ║  One command to go from fresh clone → fully running AI stack    ║
# ║  Prompts for API keys, skips already-downloaded models,         ║
# ║  builds containers, pulls Ollama models, verifies health.       ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║              🧠  Cognitive Silo Setup                       ║"
  echo "║     Private AI Infrastructure — AMD Radeon PRO W7900        ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

log()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[error]${NC} $*"; }
ask()  { echo -en "${BOLD}$*${NC}"; }

# ── Prompt helper: ask for a value, show current/default, allow skip ──
prompt_value() {
  local varname="$1" prompt="$2" default="${3:-}" is_secret="${4:-false}"
  local current="${!varname:-$default}"

  if [[ -n "$current" && "$current" != "your_"* && "$current" != "changeme"* ]]; then
    if [[ "$is_secret" == "true" ]]; then
      echo -e "  ${varname}: ${GREEN}[already set]${NC}"
    else
      echo -e "  ${varname}: ${GREEN}${current}${NC}"
    fi
    ask "  Keep this value? [Y/n]: "
    read -r keep
    if [[ "${keep,,}" != "n" ]]; then
      return 0
    fi
  fi

  if [[ "$is_secret" == "true" ]]; then
    ask "  $prompt: "
    read -rs val
    echo ""
  else
    ask "  $prompt [$default]: "
    read -r val
  fi

  val="${val:-$default}"
  eval "$varname=\"$val\""
}

# ═══════════════════════════════════════════════════════════════
# PHASE 0: Prerequisites
# ═══════════════════════════════════════════════════════════════
check_prerequisites() {
  log "Checking prerequisites..."
  local missing=0

  # Docker
  if command -v docker &>/dev/null; then
    log "  Docker: $(docker --version | head -1)"
  else
    err "  Docker not found. Install: https://docs.docker.com/engine/install/"
    missing=1
  fi

  # Docker Compose
  if docker compose version &>/dev/null 2>&1; then
    log "  Compose: $(docker compose version --short 2>/dev/null || echo 'available')"
  else
    err "  Docker Compose not found."
    missing=1
  fi

  # Docker group
  if ! groups | grep -q docker; then
    warn "  User not in docker group. Running: newgrp docker"
    warn "  If this fails, run: sudo usermod -aG docker \$USER && newgrp docker"
  fi

  # GPU
  if [[ -e /dev/kfd && -d /dev/dri ]]; then
    log "  AMD GPU: /dev/kfd + /dev/dri detected"
  else
    warn "  AMD GPU devices not found — Ollama will run on CPU"
  fi

  # HuggingFace CLI
  if command -v huggingface-cli &>/dev/null; then
    HF_CLI="huggingface-cli"
    log "  HF CLI: huggingface-cli"
  elif command -v hf &>/dev/null; then
    HF_CLI="hf"
    log "  HF CLI: hf"
  else
    warn "  HuggingFace CLI not found — will install via pip"
    HF_CLI=""
  fi

  if [[ $missing -eq 1 ]]; then
    err "Missing prerequisites. Fix the above and re-run."
    exit 1
  fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 1: Interactive API Key Configuration
# ═══════════════════════════════════════════════════════════════
configure_keys() {
  echo ""
  log "═══ API Key Configuration ═══"
  echo ""

  # Load existing .env if present
  if [[ -f .env ]]; then
    log "Found existing .env — loading current values"
    set -a; source .env 2>/dev/null || true; set +a
  fi

  # HuggingFace Token (needed for gated models like Fish Speech)
  echo -e "\n${BOLD}1. HuggingFace Token${NC} (needed for gated models like Fish Speech)"
  echo "   Get yours at: https://huggingface.co/settings/tokens"
  HF_TOKEN="${HF_TOKEN:-}"
  prompt_value HF_TOKEN "HuggingFace token (hf_...)" "" true

  # LiteLLM Master Key
  echo -e "\n${BOLD}2. LiteLLM Master Key${NC} (admin key for your AI gateway)"
  LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-master-$(openssl rand -hex 8)}"
  prompt_value LITELLM_MASTER_KEY "Master key" "$LITELLM_MASTER_KEY" true

  # Postgres Password
  echo -e "\n${BOLD}3. Postgres Password${NC} (LiteLLM analytics DB)"
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 12)}"
  prompt_value POSTGRES_PASSWORD "Password" "$POSTGRES_PASSWORD" true

  # GitHub Token (optional — cloud fallback)
  echo -e "\n${BOLD}4. GitHub Token${NC} (optional — for GPT-4o cloud fallback)"
  echo "   Skip if you only want local models."
  GITHUB_TOKEN="${GITHUB_TOKEN:-}"
  prompt_value GITHUB_TOKEN "GitHub PAT" "" true

  # Write .env
  log "Writing .env file..."
  cat > .env <<EOF
# ─── Cognitive Silo — Environment Secrets ───
# Auto-generated by setup.sh on $(date -Iseconds)
# Never commit this file.

LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
GITHUB_TOKEN=${GITHUB_TOKEN}
HF_TOKEN=${HF_TOKEN}
EOF
  chmod 600 .env
  log ".env written (chmod 600)"
}

# ═══════════════════════════════════════════════════════════════
# PHASE 2: Install HuggingFace CLI if missing
# ═══════════════════════════════════════════════════════════════
ensure_hf_cli() {
  if [[ -n "$HF_CLI" ]]; then
    return 0
  fi

  log "Installing HuggingFace Hub CLI..."
  if [[ -d ".venv" ]]; then
    source .venv/bin/activate
  else
    python3 -m venv .venv
    source .venv/bin/activate
  fi
  pip install -q "huggingface_hub[cli]"

  if command -v hf &>/dev/null; then
    HF_CLI="hf"
  elif command -v huggingface-cli &>/dev/null; then
    HF_CLI="huggingface-cli"
  else
    HF_CLI="python3 -m huggingface_hub.cli"
  fi
  log "HF CLI ready: $HF_CLI"
}

# HF login if token provided
hf_login() {
  if [[ -n "${HF_TOKEN:-}" ]]; then
    log "Logging into HuggingFace..."
    $HF_CLI login --token "$HF_TOKEN" 2>/dev/null || true
  fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 3: Download HuggingFace Models (skip if present)
# ═══════════════════════════════════════════════════════════════
download_hf_model() {
  local repo="$1" dest="$2" extra="${3:-}"

  if [[ -d "$dest" ]] && [[ "$(find "$dest" -maxdepth 1 -type f 2>/dev/null | head -1)" ]]; then
    local size
    size=$(du -sh "$dest" 2>/dev/null | cut -f1)
    log "  SKIP ${CYAN}${repo}${NC} → $dest (${size}, already downloaded)"
    return 0
  fi

  log "  DOWNLOADING ${CYAN}${repo}${NC} → $dest"
  mkdir -p "$dest"

  local auth_flag=""
  [[ -n "${HF_TOKEN:-}" ]] && auth_flag="--token $HF_TOKEN"

  if $HF_CLI download "$repo" --local-dir "$dest" $auth_flag $extra 2>&1; then
    local size
    size=$(du -sh "$dest" 2>/dev/null | cut -f1)
    log "  DONE ${GREEN}${repo}${NC} (${size})"
  else
    warn "  FAILED ${repo} — skipping (you can retry later)"
  fi
}

download_models() {
  echo ""
  log "═══ Model Downloads ═══"
  echo ""

  # Ask which model groups to download
  echo -e "${BOLD}Which model groups do you want to download?${NC}"
  echo ""

  # Speech models
  ask "  [1] Speech models (whisper-turbo, kokoro, fish-speech, xtts-v2) ~6GB? [Y/n]: "
  read -r dl_speech
  dl_speech="${dl_speech:-y}"

  # Creative models
  ask "  [2] Creative models (FLUX.1-schnell 17GB, CogVideoX-2b 14GB) ~31GB? [Y/n]: "
  read -r dl_creative
  dl_creative="${dl_creative:-y}"

  echo ""
  mkdir -p models

  if [[ "${dl_speech,,}" != "n" ]]; then
    log "── Speech Models ──"
    download_hf_model "Systran/faster-whisper-large-v3-turbo"  "models/whisper-turbo"
    download_hf_model "hexgrad/Kokoro-82M"                      "models/kokoro"
    download_hf_model "fishaudio/openaudio-s1-mini"             "models/fish-speech"
    download_hf_model "coqui/XTTS-v2"                           "models/xtts-v2"
  else
    warn "Skipping speech model downloads"
  fi

  if [[ "${dl_creative,,}" != "n" ]]; then
    log "── Creative Models ──"
    download_hf_model "Comfy-Org/flux1-schnell"  "models/flux-schnell"  "--exclude *.md"
    download_hf_model "THUDM/CogVideoX-2b"      "models/cogvideox-2b"  "--exclude *.md"
  else
    warn "Skipping creative model downloads"
  fi

  echo ""
  log "Model directory contents:"
  if [[ -d models ]] && [[ "$(ls models 2>/dev/null)" ]]; then
    for d in models/*/; do
      [[ -d "$d" ]] && echo "  $(du -sh "$d" | cut -f1)  ${d}"
    done
  else
    warn "  (empty)"
  fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 4: Build & Start Docker Containers
# ═══════════════════════════════════════════════════════════════
start_stack() {
  echo ""
  log "═══ Starting Docker Stack ═══"
  echo ""

  # Pull images first
  log "Pulling Docker images (this may take a while on first run)..."
  docker compose pull --ignore-pull-failures 2>&1 | grep -E "Pulling|Downloaded|exists" || true

  # Build custom images
  log "Building custom images (mem0-api)..."
  docker compose build --no-cache mem0 2>&1 | tail -3

  # Start core services first
  log "Starting core services (ollama, db, qdrant, redis)..."
  docker compose up -d ollama db qdrant redis 2>&1

  # Wait for Ollama to be healthy
  log "Waiting for Ollama to be ready..."
  local retries=0
  until curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [[ $retries -gt 60 ]]; then
      err "Ollama failed to start after 120s"
      docker compose logs ollama --tail 20
      exit 1
    fi
    sleep 2
    echo -n "."
  done
  echo ""
  log "Ollama is ready"

  # Pull Ollama models
  pull_ollama_models

  # Start remaining services
  log "Starting gateway, memory, and media services..."
  docker compose up -d 2>&1

  # Wait for LiteLLM
  log "Waiting for LiteLLM gateway..."
  retries=0
  until curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" http://localhost:4000/health > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [[ $retries -gt 30 ]]; then
      warn "LiteLLM not responding yet — check: docker compose logs litellm"
      break
    fi
    sleep 2
    echo -n "."
  done
  echo ""
}

# ═══════════════════════════════════════════════════════════════
# PHASE 5: Pull Ollama Models (skip if present)
# ═══════════════════════════════════════════════════════════════
pull_ollama_models() {
  echo ""
  log "═══ Ollama Model Pulls ═══"
  echo ""

  local OLLAMA_URL="http://localhost:11434"

  # Get existing models
  local existing
  existing=$(curl -sf "$OLLAMA_URL/api/tags" | python3 -c "
import json, sys
tags = json.load(sys.stdin).get('models', [])
for t in tags:
    print(t['name'])
" 2>/dev/null || echo "")

  # Models to pull
  declare -A MODELS=(
    ["deepseek-r1:32b"]="19.9GB — primary coding agent"
    ["deepseek-v2:16b"]="8.9GB — fast code + autocomplete"
    ["deepseek-r1:70b"]="42.5GB — deep reasoning (swaps with others)"
    ["llama3.3:latest"]="42.5GB — general purpose"
    ["nomic-embed-text:latest"]="0.3GB — embeddings for @codebase"
  )

  echo -e "${BOLD}Ollama LLM models to pull:${NC}"
  for model in "${!MODELS[@]}"; do
    local desc="${MODELS[$model]}"
    local base="${model%%:*}"
    if echo "$existing" | grep -q "^${base}:"; then
      echo -e "  ${GREEN}✓${NC} $model ($desc) — ${GREEN}already pulled${NC}"
    else
      echo -e "  ○ $model ($desc)"
    fi
  done

  echo ""
  ask "Pull missing Ollama models? [Y/n]: "
  read -r do_pull
  do_pull="${do_pull:-y}"

  if [[ "${do_pull,,}" == "n" ]]; then
    warn "Skipping Ollama model pulls"
    return 0
  fi

  for model in "${!MODELS[@]}"; do
    local base="${model%%:*}"
    if echo "$existing" | grep -q "^${base}:"; then
      log "  SKIP $model (already pulled)"
      continue
    fi

    log "  PULLING $model ..."
    curl -sf "$OLLAMA_URL/api/pull" -d "{\"name\": \"$model\"}" | while IFS= read -r line; do
      local status
      status=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || true)
      if [[ "$status" == *"pulling"* ]]; then
        local pct
        pct=$(echo "$line" | python3 -c "
import json,sys
d=json.load(sys.stdin)
t=d.get('total',1); c=d.get('completed',0)
print(f'{c*100//t}%' if t > 0 else '')
" 2>/dev/null || true)
        echo -ne "\r    $status $pct   "
      elif [[ "$status" == *"success"* ]]; then
        echo ""
        log "  DONE ${GREEN}$model${NC}"
      fi
    done
  done

  echo ""
  log "Ollama models:"
  curl -sf "$OLLAMA_URL/api/tags" | python3 -c "
import json, sys
tags = json.load(sys.stdin).get('models', [])
for t in tags:
    size_gb = t.get('size', 0) / 1e9
    print(f'  {t[\"name\"]:30s} {size_gb:.1f} GB')
" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════
# PHASE 6: Health Check & Summary
# ═══════════════════════════════════════════════════════════════
health_check() {
  echo ""
  log "═══ Health Check ═══"
  echo ""

  local all_ok=true

  # Container status
  echo -e "${BOLD}Container Status:${NC}"
  docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | while IFS= read -r line; do
    if echo "$line" | grep -q "Up"; then
      echo -e "  ${GREEN}✓${NC} $line"
    else
      echo -e "  ${RED}✗${NC} $line"
      all_ok=false
    fi
  done

  echo ""

  # Service endpoints
  echo -e "${BOLD}Service Endpoints:${NC}"
  local -A ENDPOINTS=(
    ["Ollama LLM"]="http://localhost:11434/api/tags"
    ["LiteLLM Gateway"]="http://localhost:4000/health"
    ["Mem0 Memory"]="http://localhost:8080/health"
    ["Qdrant Vectors"]="http://localhost:6333/collections"
    ["Speaches STT/TTS"]="http://localhost:8000/health"
    ["Fish Speech TTS"]="http://localhost:8001/"
    ["XTTS-v2 TTS"]="http://localhost:8002/languages"
    ["ComfyUI"]="http://localhost:8188/"
  )

  for svc in "${!ENDPOINTS[@]}"; do
    local url="${ENDPOINTS[$svc]}"
    local port="${url#*localhost:}"
    port="${port%%/*}"
    if curl -sf -o /dev/null --max-time 3 "$url" 2>/dev/null || \
       curl -sf -o /dev/null --max-time 3 -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" "$url" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} ${svc:30s} → localhost:${port}"
    else
      echo -e "  ${YELLOW}○${NC} ${svc:30s} → localhost:${port} (not ready yet)"
    fi
  done

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}Cognitive Silo is running!${NC}                                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  LiteLLM API:    http://localhost:4000                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  API Key:        \$LITELLM_MASTER_KEY (in .env)                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Ollama Direct:  http://localhost:11434                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Memory API:     http://localhost:8080                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Speaches:       http://localhost:8000                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Fish Speech:    http://localhost:8001                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  XTTS-v2:        http://localhost:8002                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ComfyUI:        http://localhost:8188                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Manage:  docker compose ps / logs / down                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Re-run:  ./setup.sh                                         ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════
main() {
  banner

  # Parse flags
  SKIP_DOWNLOADS=false
  SKIP_KEYS=false
  for arg in "$@"; do
    case "$arg" in
      --skip-downloads) SKIP_DOWNLOADS=true ;;
      --skip-keys)      SKIP_KEYS=true ;;
      --help|-h)
        echo "Usage: ./setup.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --skip-downloads   Skip HuggingFace model downloads"
        echo "  --skip-keys        Skip API key configuration (use existing .env)"
        echo "  --help, -h         Show this help"
        exit 0
        ;;
    esac
  done

  check_prerequisites

  if [[ "$SKIP_KEYS" != "true" ]]; then
    configure_keys
  else
    if [[ -f .env ]]; then
      set -a; source .env 2>/dev/null || true; set +a
      log "Using existing .env"
    else
      err "No .env found and --skip-keys specified"
      exit 1
    fi
  fi

  if [[ "$SKIP_DOWNLOADS" != "true" ]]; then
    ensure_hf_cli
    hf_login
    download_models
  else
    log "Skipping model downloads (--skip-downloads)"
  fi

  start_stack
  health_check
}

main "$@"
