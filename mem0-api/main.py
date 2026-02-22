"""
Cognitive Silo — Mem0 Memory API
Thin REST wrapper around mem0ai that uses Ollama for LLM + Qdrant for vectors.
Each project gets its own user_id namespace → memory isolation ("silo").
"""

import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
from mem0 import Memory

app = FastAPI(title="Cognitive Silo Memory API", version="0.1.0")

# ── Mem0 config: use Ollama (local LLM) + Qdrant (vector store) ──
config = {
    "llm": {
        "provider": "ollama",
        "config": {
            "model": os.getenv("MEM0_LLM_MODEL", "deepseek-r1:32b"),
            "ollama_base_url": os.getenv("OLLAMA_BASE_URL", "http://ollama:11434"),
        },
    },
    "vector_store": {
        "provider": "qdrant",
        "config": {
            "host": os.getenv("QDRANT_HOST", "qdrant"),
            "port": int(os.getenv("QDRANT_PORT", "6333")),
            "embedding_model_dims": 768,
        },
    },
    "embedder": {
        "provider": "ollama",
        "config": {
            "model": os.getenv("MEM0_EMBED_MODEL", "nomic-embed-text"),
            "ollama_base_url": os.getenv("OLLAMA_BASE_URL", "http://ollama:11434"),
        },
    },
}

memory = Memory.from_config(config)


# ── Request / Response Models ──
class AddMemoryRequest(BaseModel):
    messages: list[dict]          # [{"role": "user", "content": "..."}]
    user_id: str                  # project silo key, e.g. "silicon-trace"
    metadata: Optional[dict] = None


class SearchMemoryRequest(BaseModel):
    query: str
    user_id: str
    limit: int = 5


# ── Endpoints ──
@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/add")
def add_memory(req: AddMemoryRequest):
    try:
        result = memory.add(req.messages, user_id=req.user_id, metadata=req.metadata)
        return {"status": "ok", "result": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/search")
def search_memory(req: SearchMemoryRequest):
    try:
        results = memory.search(query=req.query, user_id=req.user_id, limit=req.limit)
        return {"status": "ok", "results": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/memories/{user_id}")
def get_all_memories(user_id: str):
    try:
        results = memory.get_all(user_id=user_id)
        return {"status": "ok", "memories": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories/{user_id}/{memory_id}")
def delete_memory(user_id: str, memory_id: str):
    try:
        memory.delete(memory_id)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
