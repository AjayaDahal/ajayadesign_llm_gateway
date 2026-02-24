"""
MusicGen API — Text-to-Music Generation Service
Uses Meta's MusicGen model via transformers.
Provides a simple REST API for generating music from text prompts.

Endpoints:
  POST /generate       — Generate music from text prompt
  GET  /health         — Health check
  GET  /models         — List available models
"""

import io
import os
import time
import wave
import logging
from typing import Optional

import numpy as np
import torch
import scipy.io.wavfile
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field
from transformers import AutoProcessor, MusicgenForConditionalGeneration

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("musicgen-api")

# ── Configuration ──────────────────────────────────────────────
MODEL_NAME = os.environ.get("MUSICGEN_MODEL", "facebook/musicgen-small")
CACHE_DIR = os.environ.get("HF_HOME", "/app/models")
DEVICE = "cpu"  # MusicGen works well on CPU; GPU offload available if needed
MAX_DURATION_SECONDS = int(os.environ.get("MAX_DURATION_SECONDS", "30"))

app = FastAPI(
    title="MusicGen API",
    description="Text-to-Music generation powered by Meta's MusicGen",
    version="1.0.0",
)

# ── Global model state ─────────────────────────────────────────
processor = None
model = None
model_loaded = False


class GenerateRequest(BaseModel):
    prompt: str = Field(..., description="Text description of the music to generate", examples=["upbeat electronic dance music with heavy bass"])
    duration: Optional[float] = Field(default=8.0, description="Duration in seconds (max 30)", ge=1.0, le=30.0)
    temperature: Optional[float] = Field(default=1.0, description="Sampling temperature", ge=0.1, le=2.0)
    top_k: Optional[int] = Field(default=250, description="Top-k sampling", ge=1, le=1000)
    top_p: Optional[float] = Field(default=0.0, description="Top-p (nucleus) sampling", ge=0.0, le=1.0)
    format: Optional[str] = Field(default="wav", description="Output format: wav or mp3")


def load_model():
    """Load MusicGen model and processor."""
    global processor, model, model_loaded
    if model_loaded:
        return

    logger.info(f"Loading MusicGen model: {MODEL_NAME}")
    start = time.time()

    processor = AutoProcessor.from_pretrained(
        MODEL_NAME,
        cache_dir=CACHE_DIR,
    )
    model = MusicgenForConditionalGeneration.from_pretrained(
        MODEL_NAME,
        cache_dir=CACHE_DIR,
        torch_dtype=torch.float32,
    )
    model.to(DEVICE)
    model.eval()

    elapsed = time.time() - start
    logger.info(f"MusicGen loaded in {elapsed:.1f}s ({MODEL_NAME})")
    model_loaded = True


@app.on_event("startup")
async def startup():
    """Load model on startup."""
    try:
        load_model()
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        # Allow the server to start; model can be loaded lazily
        logger.info("Server started without model — will retry on first request")


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "healthy" if model_loaded else "loading",
        "model": MODEL_NAME,
        "model_loaded": model_loaded,
        "max_duration_seconds": MAX_DURATION_SECONDS,
        "device": DEVICE,
    }


@app.get("/models")
async def list_models():
    """List available models."""
    return {
        "models": [
            {
                "id": "facebook/musicgen-small",
                "name": "MusicGen Small",
                "params": "300M",
                "description": "Fast music generation, good quality",
            },
            {
                "id": "facebook/musicgen-medium",
                "name": "MusicGen Medium",
                "params": "1.5B",
                "description": "Better quality, slower generation",
            },
            {
                "id": "facebook/musicgen-large",
                "name": "MusicGen Large",
                "params": "3.3B",
                "description": "Best quality, slowest generation",
            },
        ],
        "active_model": MODEL_NAME,
    }


@app.post("/generate")
async def generate_music(req: GenerateRequest):
    """Generate music from a text prompt."""
    global model, processor, model_loaded

    # Lazy load if startup failed
    if not model_loaded:
        try:
            load_model()
        except Exception as e:
            raise HTTPException(status_code=503, detail=f"Model not loaded: {e}")

    duration = min(req.duration, MAX_DURATION_SECONDS)

    logger.info(f"Generating {duration}s of music: '{req.prompt[:80]}'")
    start = time.time()

    try:
        # Tokenize the prompt
        inputs = processor(
            text=[req.prompt],
            padding=True,
            return_tensors="pt",
        ).to(DEVICE)

        # MusicGen generates at 32kHz, calculate max tokens
        # ~50 tokens per second of audio for musicgen
        max_new_tokens = int(duration * 50)

        # Generate
        with torch.no_grad():
            audio_values = model.generate(
                **inputs,
                max_new_tokens=max_new_tokens,
                temperature=req.temperature,
                do_sample=True,
                top_k=req.top_k if req.top_k > 0 else None,
                top_p=req.top_p if req.top_p > 0 else None,
            )

        # Convert to numpy
        audio_data = audio_values[0, 0].cpu().numpy()
        sample_rate = model.config.audio_encoder.sampling_rate

        elapsed = time.time() - start
        logger.info(f"Generated {len(audio_data)/sample_rate:.1f}s audio in {elapsed:.1f}s")

        # Encode to WAV
        buf = io.BytesIO()
        scipy.io.wavfile.write(buf, sample_rate, (audio_data * 32767).astype(np.int16))
        buf.seek(0)

        return StreamingResponse(
            buf,
            media_type="audio/wav",
            headers={
                "Content-Disposition": f'attachment; filename="musicgen_{int(time.time())}.wav"',
                "X-Duration-Seconds": f"{len(audio_data)/sample_rate:.1f}",
                "X-Generation-Time": f"{elapsed:.1f}",
            },
        )

    except Exception as e:
        logger.error(f"Generation failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
