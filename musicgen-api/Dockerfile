FROM python:3.11-slim

WORKDIR /app

# Install system deps
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps (torch from CPU wheel, rest from PyPI)
RUN pip install --no-cache-dir \
    torch==2.5.* --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir \
    fastapi[standard]==0.115.* \
    uvicorn[standard]==0.34.* \
    transformers==4.48.* \
    scipy==1.15.* \
    numpy==1.26.* \
    sentencepiece==0.2.* \
    protobuf==5.29.*

COPY main.py .

ENV HF_HOME=/app/models
ENV MUSICGEN_MODEL=facebook/musicgen-small
ENV MAX_DURATION_SECONDS=30

EXPOSE 8003

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=120s \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8003/health')"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003", "--workers", "1"]
