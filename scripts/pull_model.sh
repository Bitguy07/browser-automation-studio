#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/pull_model.sh
# One-shot script: pulls the Qwen model after Ollama is ready.
# Managed by supervisord (autorestart=false).
# If model is already on persistent storage, exits immediately.
# ============================================================

MODEL_TAG="${OLLAMA_MODEL:-qwen2.5vl:7b}"

echo "[pull_model.sh] Waiting for Ollama server to be ready..."
for i in $(seq 1 60); do
    if curl -s "http://127.0.0.1:11434/api/tags" > /dev/null 2>&1; then
        echo "[pull_model.sh] Ollama ready (attempt $i)."
        break
    fi
    if [ "$i" = "60" ]; then
        echo "[pull_model.sh] ERROR: Ollama not ready after 120s. Exiting."
        exit 1
    fi
    sleep 2
done

# Check if model already exists (survives restarts via persistent storage)
if ollama list 2>/dev/null | grep -q "qwen2.5vl"; then
    echo "[pull_model.sh] ✓ Model already present on persistent storage. Skipping pull."
    exit 0
fi

echo "[pull_model.sh] Model not found. Pulling $MODEL_TAG (~4.7GB, first time only)..."
echo "[pull_model.sh] This may take 10-15 minutes. The app is already running."
echo "[pull_model.sh] Tasks will use API fallback until the model is ready."

if ollama pull "$MODEL_TAG"; then
    echo "[pull_model.sh] ✓ Model pull complete! Qwen2.5-VL is ready."
    echo "[pull_model.sh] Future restarts will skip this step (persistent storage)."
else
    echo "[pull_model.sh] ✗ Model pull failed. Will retry on next container restart."
    echo "[pull_model.sh] Check /data/logs/ollama-pull.log for details."
    exit 1
fi
