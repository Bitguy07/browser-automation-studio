#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# HF Spaces Free Tier + Storage Bucket edition
#
# Execution order:
#   1. Source .env
#   2. Create /data subdirs (bucket is already mounted by HF here)
#   3. Clean Chrome lock files
#   4. Optionally install Ollama binary INTO /data/bin (persistent!)
#      and pull model into /data/ollama (persistent!)
#   5. Sanity check binaries
#   6. Hand off to supervisord
#
# All Python calls use /opt/venv/bin/python to match what
# supervisord.conf uses — never bare "python" or "python3"
# which would hit the read-only system Python.
# ============================================================
set -e

echo "======================================================"
echo "  Browser Automation Studio — Starting Up"
echo "======================================================"

# ── Load .env ─────────────────────────────────────────────────
if [ -f /app/.env ]; then
    set -o allexport
    # shellcheck disable=SC1091
    source /app/.env
    set +o allexport
fi

# ── Create /data subdirs ──────────────────────────────────────
# At this point HF has already mounted the storage bucket at /data.
# We create subdirs if they don't exist yet (first boot).
mkdir -p /data/cookies /data/outputs /data/downloads \
         /data/chrome-profile /data/ollama /data/logs \
         /data/.huggingface /data/bin \
         /var/log/supervisor

chmod -R 777 /data 2>/dev/null || true
chmod -R 777 /var/log/supervisor 2>/dev/null || true

# ── Chrome lock cleanup ───────────────────────────────────────
for f in SingletonLock SingletonSocket SingletonCookie; do
    rm -f "/data/chrome-profile/$f" 2>/dev/null || true
done
rm -f /data/chrome-profile/Default/Cookies-journal 2>/dev/null || true
echo "[start.sh] Chrome lock cleanup done."

# ── Environment ───────────────────────────────────────────────
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export CHROME_EXECUTABLE_PATH="/usr/bin/google-chrome-stable"
export OLLAMA_MODELS="${OLLAMA_MODELS:-/data/ollama}"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
export HF_HOME="${HF_HOME:-/data/.huggingface}"
export DISPLAY=:99

# Ollama binary stored in /data/bin so it persists across restarts
# and doesn't need to be re-downloaded every cold start
OLLAMA_BIN="/data/bin/ollama"

# ── Ollama (bucket-persistent, opt-in) ───────────────────────
# ENABLE_OLLAMA=true → install binary + pull model (first time only)
# ENABLE_OLLAMA=false (default) → use Gemini/Groq API, skip everything
#
# Because the binary lives in /data/bin (bucket-mounted), after the
# first startup it's already there and this section runs in ~1 second.
# The model in /data/ollama also persists — no re-download needed.
if [ "${ENABLE_OLLAMA:-false}" = "true" ]; then
    if [ ! -f "$OLLAMA_BIN" ]; then
        echo "[start.sh] Downloading Ollama binary to /data/bin (~80MB, one-time)..."
        if curl -L --max-time 300 --retry 3 --retry-delay 10 \
            "https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64" \
            -o /tmp/ollama_dl 2>&1; then
            install -m 755 /tmp/ollama_dl "$OLLAMA_BIN"
            rm -f /tmp/ollama_dl
            echo "[start.sh] Ollama binary saved to $OLLAMA_BIN (will persist in bucket)."
        else
            echo "[start.sh] WARNING: Ollama download failed — using Gemini/Groq fallback."
        fi
    else
        echo "[start.sh] Ollama binary already in bucket at $OLLAMA_BIN."
    fi

    if [ -f "$OLLAMA_BIN" ]; then
        echo "[start.sh] Starting Ollama server..."
        OLLAMA_MODELS="$OLLAMA_MODELS" "$OLLAMA_BIN" serve > /data/logs/ollama.log 2>&1 &

        echo "[start.sh] Waiting for Ollama to be ready..."
        for i in $(seq 1 30); do
            if curl -s "http://127.0.0.1:11434/api/tags" > /dev/null 2>&1; then
                echo "[start.sh] Ollama ready (attempt $i)."
                break
            fi
            [ "$i" = "30" ] && echo "[start.sh] WARNING: Ollama slow to start — continuing anyway."
            sleep 2
        done

        MODEL_TAG="${OLLAMA_MODEL:-qwen2.5vl:7b-instruct-q4_K_M}"

        # Check if model already pulled (will be in /data/ollama on bucket)
        if "$OLLAMA_BIN" list 2>/dev/null | grep -q "qwen2.5vl"; then
            echo "[start.sh] Qwen model already in bucket — no download needed."
        elif [ "${PULL_MODEL_ON_STARTUP:-false}" = "true" ]; then
            echo "[start.sh] Pulling $MODEL_TAG into /data/ollama (~4.5GB, one-time)..."
            echo "[start.sh] This will take 15–30 min on first boot. Subsequent starts skip this."
            OLLAMA_MODELS="$OLLAMA_MODELS" "$OLLAMA_BIN" pull "$MODEL_TAG" \
                && echo "[start.sh] Model pull complete. Saved to bucket." \
                || echo "[start.sh] WARNING: Pull failed — falling back to Gemini/Groq."
        else
            echo "[start.sh] PULL_MODEL_ON_STARTUP=false — model not pulled. Set true to enable."
        fi
    fi
else
    echo "[start.sh] ENABLE_OLLAMA=false — Skipping Ollama (using Gemini/Groq API)."
fi

# ── Binary sanity check ───────────────────────────────────────
echo ""
echo "[start.sh] Binary check:"
for bin in Xvfb google-chrome-stable x11vnc supervisord; do
    command -v "$bin" &>/dev/null \
        && echo "  ✓ $bin" \
        || echo "  ✗ $bin NOT FOUND — check Dockerfile"
done

# All Python checks use venv python explicitly
VENV_PY="/opt/venv/bin/python"
"$VENV_PY" -m websockify --help > /dev/null 2>&1 \
    && echo "  ✓ websockify (venv)" \
    || echo "  ✗ websockify missing from venv"
"$VENV_PY" -c "import fastapi; print('  ✓ fastapi', fastapi.__version__)" 2>/dev/null \
    || echo "  ✗ fastapi missing from venv"
"$VENV_PY" -c "import browser_use; print('  ✓ browser_use')" 2>/dev/null \
    || echo "  ✗ browser_use missing from venv"
"$VENV_PY" -c "import uvicorn; print('  ✓ uvicorn')" 2>/dev/null \
    || echo "  ✗ uvicorn missing from venv"

echo ""
echo "  PRIMARY_LLM   = ${PRIMARY_LLM:-gemini}"
echo "  ENABLE_OLLAMA = ${ENABLE_OLLAMA:-false}"
echo "  CHROME        = $CHROME_EXECUTABLE_PATH"
echo "  APP_PORT      = ${APP_PORT:-7860}"
echo "  /data/bin/ollama exists: $([ -f $OLLAMA_BIN ] && echo YES || echo NO)"
echo ""
echo "[start.sh] Starting supervisord..."
exec /usr/bin/supervisord -n -c /app/supervisord.conf