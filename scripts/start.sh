#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# Runtime startup: installs Ollama if missing, pulls model,
# then launches all services via supervisord.
# ============================================================

set -e

echo "======================================================"
echo "  Browser Automation Studio — Container Starting"
echo "======================================================"

# ── Load .env if present ──────────────────────────────────────
if [ -f /app/.env ]; then
    echo "[start.sh] Loading .env file..."
    export $(grep -v '^#' /app/.env | grep -v '^$' | xargs)
fi

# ── Create required directories ───────────────────────────────
echo "[start.sh] Creating data directories..."
mkdir -p /data/cookies /data/outputs /data/downloads \
         /data/chrome-profile /data/ollama /data/logs \
         /var/log/supervisor
chmod -R 777 /data 2>/dev/null || true
chmod -R 777 /var/log/supervisor 2>/dev/null || true

# ── Clean Chrome lock files ───────────────────────────────────
echo "[start.sh] Cleaning Chrome lock files..."
rm -f /data/chrome-profile/SingletonLock    2>/dev/null || true
rm -f /data/chrome-profile/SingletonSocket  2>/dev/null || true
rm -f /data/chrome-profile/SingletonCookie  2>/dev/null || true
rm -f /data/chrome-profile/Default/Cookies-journal 2>/dev/null || true
echo "[start.sh] Chrome lock cleanup done."

# ── Install Ollama if not present ────────────────────────────
# Installed at runtime to avoid HF build timeouts.
# Binary persists in /usr/local/bin after first install.
export OLLAMA_MODELS="${OLLAMA_MODELS:-/data/ollama}"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

OLLAMA_BIN="/usr/local/bin/ollama"

if [ ! -f "$OLLAMA_BIN" ]; then
    echo "[start.sh] Ollama not found — downloading binary..."
    if curl -L --max-time 120 --retry 3 --retry-delay 5 \
        "https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64" \
        -o /tmp/ollama 2>/dev/null; then
        install -m 755 /tmp/ollama "$OLLAMA_BIN"
        rm -f /tmp/ollama
        echo "[start.sh] Ollama installed at $OLLAMA_BIN."
    else
        echo "[start.sh] WARNING: Could not download Ollama. API fallback (Gemini/Groq) will be used."
    fi
else
    echo "[start.sh] Ollama already installed."
fi

# ── Start Ollama server if binary exists ─────────────────────
if [ -f "$OLLAMA_BIN" ]; then
    echo "[start.sh] Starting Ollama server..."
    ollama serve > /data/logs/ollama.log 2>&1 &

    echo "[start.sh] Waiting for Ollama to be ready..."
    for i in $(seq 1 30); do
        if curl -s "http://127.0.0.1:11434/api/tags" > /dev/null 2>&1; then
            echo "[start.sh] Ollama ready (attempt $i)."
            break
        fi
        [ "$i" = "30" ] && echo "[start.sh] WARNING: Ollama slow to start — continuing."
        sleep 2
    done

    # ── Pull model if needed ──────────────────────────────────
    MODEL_TAG="${OLLAMA_MODEL:-qwen2.5vl:7b-instruct-q4_K_M}"
    if ollama list 2>/dev/null | grep -q "qwen2.5vl"; then
        echo "[start.sh] Qwen model already present — skipping pull."
    elif [ "${PULL_MODEL_ON_STARTUP:-false}" = "true" ]; then
        echo "[start.sh] Pulling $MODEL_TAG (~10-15 min first time)..."
        ollama pull "$MODEL_TAG" \
            && echo "[start.sh] Model pull complete." \
            || echo "[start.sh] WARNING: Model pull failed — using API fallback."
    else
        echo "[start.sh] PULL_MODEL_ON_STARTUP=false — using Gemini/Groq fallback."
    fi
else
    echo "[start.sh] No Ollama — all tasks will use Gemini/Groq fallback."
fi

# ── Verify binaries ───────────────────────────────────────────
echo "[start.sh] Checking required binaries..."
for bin in Xvfb chromium x11vnc websockify python3 supervisord; do
    command -v "$bin" &>/dev/null \
        && echo "  ✓ $bin" \
        || echo "  ✗ $bin NOT FOUND"
done
python3 -c "import fastapi; print('  ✓ fastapi', fastapi.__version__)" 2>/dev/null || echo "  ✗ fastapi missing"
python3 -c "import uvicorn; print('  ✓ uvicorn')" 2>/dev/null || echo "  ✗ uvicorn missing"

export DISPLAY=:99

echo ""
echo "======================================================"
echo "  PRIMARY_LLM   = ${PRIMARY_LLM:-qwen}"
echo "  OLLAMA_HOST   = ${OLLAMA_HOST}"
echo "  APP_PORT      = ${APP_PORT:-7860}"
echo "======================================================"
echo ""
echo "[start.sh] Launching supervisord..."

exec /usr/bin/supervisord -n -c /app/supervisord.conf
