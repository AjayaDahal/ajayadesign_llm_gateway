#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Cognitive Silo — HuggingFace Model Downloader              ║
# ║  Downloads all speech, image, and video models              ║
# ║  Run once before `docker compose up` or via init container  ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-/models}"
HF_TOKEN="${HF_TOKEN:-}"

log() { echo "[model-dl] $(date '+%H:%M:%S') $*"; }

# Use token if provided (needed for gated repos like fish-speech)
HF_AUTH=""
if [[ -n "$HF_TOKEN" ]]; then
  HF_AUTH="--token $HF_TOKEN"
  log "HF token provided — gated repos enabled"
fi

download_hf() {
  local repo="$1" dest="$2" extra="${3:-}"
  if [[ -d "$dest" ]] && [[ "$(ls -A "$dest" 2>/dev/null)" ]]; then
    log "SKIP $repo → $dest (already exists)"
    return 0
  fi
  log "DOWNLOADING $repo → $dest"
  mkdir -p "$dest"
  huggingface-cli download "$repo" --local-dir "$dest" $HF_AUTH $extra || {
    log "WARN: Failed to download $repo — continuing"
    return 0
  }
  log "DONE $repo"
}

# ── Speech Models ──
log "=== Speech Models ==="
download_hf "Systran/faster-whisper-large-v3-turbo"  "$MODELS_DIR/whisper-turbo"
download_hf "hexgrad/Kokoro-82M"                      "$MODELS_DIR/kokoro"
download_hf "fishaudio/openaudio-s1-mini"              "$MODELS_DIR/fish-speech"
download_hf "coqui/XTTS-v2"                            "$MODELS_DIR/xtts-v2"

# ── Creative Models ──
log "=== Creative Models ==="
download_hf "Comfy-Org/flux1-schnell"                  "$MODELS_DIR/flux-schnell" "--exclude *.md"
download_hf "THUDM/CogVideoX-2b"                      "$MODELS_DIR/cogvideox-2b" "--exclude *.md"

log "=== All model downloads complete ==="
ls -1 "$MODELS_DIR"/
