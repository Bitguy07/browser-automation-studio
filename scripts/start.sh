#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# ============================================================
set -e

echo "======================================================"
echo "  Browser Automation Studio — Starting Up"
echo "======================================================"

if [ -f /app/.env ]; then
    export $(grep -v '^#' /app/.env | grep -v '^$' | xargs)
fi

mkdir -p /data/cookies /data/outputs /data/downloads \
         /data/chrome-profile /data/ollama /data/logs \
         /var/log/supervisor
chmod -R 777 /data 2>/dev/null || true
chmod -R 777 /var/log/supervisor 2>/dev/null || true

rm -f /data/chrome-profile/SingletonLock    2>/dev/null || true
rm -f /data/chrome-profile/SingletonSocket  2>/dev/null || true
rm -f /data/chrome-profile/SingletonCookie  2>/dev/null || true
rm -f /data/chrome-profile/Default/Cookies-journal 2>/dev/null || true
echo "[start.sh] Chrome lock cleanup done."

export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export CHROME_EXECUTABLE_PATH="/usr/bin/google-chrome-stable"
export OLLAMA_MODELS="${OLLAMA_MODELS:-/data/ollama}"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
OLLAMA_BIN="/usr/local/bin/ollama"

if [ ! -f "$OLLAMA_BIN" ]; then
    echo "[start.sh] Downloading Ollama binary (~80MB)..."
    if curl -L --max-time 180 --retry 3 --retry-delay 5 \
        "https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64" \
        -o /tmp/ollama 2>/dev/null; then
        install -m 755 /tmp/ollama "$OLLAMA_BIN"
        rm -f /tmp/ollama
        echo "[start.sh] Ollama installed."
    else
        echo "[start.sh] WARNING: Ollama download failed — using Gemini/Groq fallback."
    fi
else
    echo "[start.sh] Ollama already installed."
fi

if [ -f "$OLLAMA_BIN" ]; then
    echo "[start.sh] Starting Ollama server..."
    OLLAMA_MODELS="$OLLAMA_MODELS" ollama serve > /data/logs/ollama.log 2>&1 &
    for i in $(seq 1 30); do
        if curl -s "http://127.0.0.1:11434/api/tags" > /dev/null 2>&1; then
            echo "[start.sh] Ollama ready (attempt $i)."; break
        fi
        [ "$i" = "30" ] && echo "[start.sh] WARNING: Ollama slow — continuing."
        sleep 2
    done

    MODEL_TAG="${OLLAMA_MODEL:-qwen2.5vl:7b-instruct-q4_K_M}"
    if ollama list 2>/dev/null | grep -q "qwen2.5vl"; then
        echo "[start.sh] Qwen model already present."
    elif [ "${PULL_MODEL_ON_STARTUP:-false}" = "true" ]; then
        echo "[start.sh] Pulling $MODEL_TAG (~10-15 min first time)..."
        ollama pull "$MODEL_TAG" \
            && echo "[start.sh] Model pull complete." \
            || echo "[start.sh] WARNING: Pull failed — using API fallback."
    else
        echo "[start.sh] PULL_MODEL_ON_STARTUP=false — using Gemini/Groq."
    fi
else
    echo "[start.sh] No Ollama — using Gemini/Groq fallback."
fi

echo "[start.sh] Binary check:"
for bin in Xvfb google-chrome-stable x11vnc websockify python3 supervisord; do
    command -v "$bin" &>/dev/null && echo "  ✓ $bin" || echo "  ✗ $bin NOT FOUND"
done
python3 -c "import fastapi; print('  ✓ fastapi', fastapi.__version__)" 2>/dev/null || echo "  ✗ fastapi missing"
python3 -c "import browser_use; print('  ✓ browser_use')" 2>/dev/null || echo "  ✗ browser_use missing"

export DISPLAY=:99
echo ""
echo "  PRIMARY_LLM = ${PRIMARY_LLM:-gemini}"
echo "  CHROME      = $CHROME_EXECUTABLE_PATH"
echo "  APP_PORT    = ${APP_PORT:-7860}"
echo ""
echo "[start.sh] Starting supervisord..."
exec /usr/bin/supervisord -n -c /app/supervisord.conf
