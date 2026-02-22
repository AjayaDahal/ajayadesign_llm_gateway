#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Cognitive Silo — Ollama Model Puller                       ║
# ║  Waits for Ollama to be ready, then pulls all LLM models    ║
# ║  Runs as a one-shot init container                          ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://ollama:11434}"

log() { echo "[ollama-init] $(date '+%H:%M:%S') $*"; }

# ── Wait for Ollama to be ready ──
log "Waiting for Ollama at $OLLAMA_HOST ..."
until curl -sf "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; do
  sleep 2
done
log "Ollama is ready"

# ── List of models to pull ──
MODELS=(
  "deepseek-r1:32b"
  "deepseek-v2:16b"
  "deepseek-r1:70b"
  "llama3.3:latest"
  "nomic-embed-text:latest"
)

# ── Pull each model (skip if already present) ──
EXISTING=$(curl -sf "$OLLAMA_HOST/api/tags" | python3 -c "
import json, sys
tags = json.load(sys.stdin).get('models', [])
for t in tags:
    print(t['name'])
" 2>/dev/null || echo "")

for model in "${MODELS[@]}"; do
  # Check if model already exists (handle tag normalization)
  base="${model%%:*}"
  if echo "$EXISTING" | grep -q "^${base}:"; then
    log "SKIP $model (already pulled)"
    continue
  fi
  log "PULLING $model ..."
  curl -sf "$OLLAMA_HOST/api/pull" -d "{\"name\": \"$model\"}" | while IFS= read -r line; do
    status=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)
    if [[ "$status" == *"success"* ]]; then
      log "DONE $model"
    fi
  done
done

log "=== All Ollama models ready ==="
curl -sf "$OLLAMA_HOST/api/tags" | python3 -c "
import json, sys
tags = json.load(sys.stdin).get('models', [])
for t in tags:
    size_gb = t.get('size', 0) / 1e9
    print(f\"  {t['name']:30s} {size_gb:.1f} GB\")
"
