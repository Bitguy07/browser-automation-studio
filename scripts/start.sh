#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# M8: Ollama startup for Qwen2.5-VL-7B-Instruct
# ============================================================

set -e

echo "======================================================"
echo "  Browser Automation Studio — Container Starting"
echo "======================================================"

if [ -f /app/.env ]; then
    echo "[start.sh] Loading .env file..."
    export $(grep -v '^#' /app/.env | grep -v '^$' | xargs)
fi

# ── Create required directories ───────────────────────────────
echo "[start.sh] Creating data directories..."
mkdir -p /data/cookies /data/outputs /data/downloads \
         /data/chrome-profile /data/ollama \
         /var/log/supervisor /var/run
chmod -R 777 /data 2>/dev/null || true
chmod -R 755 /var/log/supervisor 2>/dev/null || true

# ── Clean Chrome lock files ───────────────────────────────────
echo "[start.sh] Cleaning Chrome lock files from previous run..."
rm -f /data/chrome-profile/SingletonLock    2>/dev/null || true
rm -f /data/chrome-profile/SingletonSocket  2>/dev/null || true
rm -f /data/chrome-profile/SingletonCookie  2>/dev/null || true
rm -f /data/chrome-profile/Default/Cookies-journal 2>/dev/null || true
rm -f /root/.chrome-data/SingletonLock      2>/dev/null || true
rm -f /root/.chrome-data/SingletonSocket    2>/dev/null || true
echo "[start.sh] Chrome lock cleanup done."

# ── Start Ollama ──────────────────────────────────────────────
# Pipe to tee so output goes to BOTH the file AND stdout.
# Stdout is visible in HF Spaces Logs tab in real time —
# this is the equivalent of your local terminal.
echo "[start.sh] Starting Ollama LLM server..."
export OLLAMA_MODELS="${OLLAMA_MODELS:-/data/ollama}"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

ollama serve 2>&1 | tee /var/log/ollama.log &

# Wait for Ollama API to be ready (up to 60s)
echo "[start.sh] Waiting for Ollama to be ready..."
for i in $(seq 1 30); do
    if curl -s "http://${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; then
        echo "[start.sh] Ollama ready (attempt $i)."
        break
    fi
    [ "$i" = "30" ] && echo "[start.sh] WARNING: Ollama slow to start — continuing anyway."
    sleep 2
done

# ── Check if model is present, pull if needed ─────────────────
MODEL_TAG="${OLLAMA_MODEL:-qwen2.5vl:7b-instruct-q4_K_M}"
if ollama list 2>/dev/null | grep -q "qwen2.5vl"; then
    echo "[start.sh] Qwen2.5-VL model present — skipping pull."
else
    if [ "${PULL_MODEL_ON_STARTUP:-false}" = "true" ]; then
        echo "[start.sh] Pulling $MODEL_TAG (first-time, ~5-10 min)..."
        # Pull with output going to stdout so it shows in HF logs
        ollama pull "$MODEL_TAG" \
            && echo "[start.sh] Model pull complete." \
            || echo "[start.sh] WARNING: Model pull failed — API fallback will be used."
    else
        echo "[start.sh] Model not found. PULL_MODEL_ON_STARTUP=false — will use API fallback (Gemini/Groq)."
        echo "[start.sh] To enable startup pull: set PULL_MODEL_ON_STARTUP=true as HF Secret."
    fi
fi

# ── Verify binaries ───────────────────────────────────────────
echo "[start.sh] Checking required binaries..."
for bin in Xvfb chromium x11vnc websockify python3 supervisord; do
    command -v "$bin" &>/dev/null \
        && echo "  ✓ $bin at $(command -v $bin)" \
        || echo "  ✗ $bin NOT FOUND"
done

python3 -c "import fastapi; print('  ✓ fastapi', fastapi.__version__)" 2>/dev/null || echo "  ✗ fastapi missing"
python3 -c "import uvicorn; print('  ✓ uvicorn')" 2>/dev/null || echo "  ✗ uvicorn missing"

export DISPLAY=:99

echo ""
echo "======================================================"
echo "  Configuration:"
echo "  APP_PORT      = ${APP_PORT:-7860}"
echo "  DATA_DIR      = ${DATA_DIR:-/data}"
echo "  OLLAMA_HOST   = ${OLLAMA_HOST}"
echo "  OLLAMA_MODELS = ${OLLAMA_MODELS}"
echo "  PRIMARY_LLM   = ${PRIMARY_LLM:-qwen}"
echo "  DISPLAY       = $DISPLAY"
echo "======================================================"
echo ""
echo "[start.sh] Starting supervisord..."
echo ""

exec /usr/bin/supervisord -n -c /app/supervisord.conf