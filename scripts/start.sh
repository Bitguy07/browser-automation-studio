#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# Restructured: supervisord starts FIRST so health check works.
# Ollama + model pull are managed by supervisord programs.
# ============================================================
# No 'set -e' — graceful degradation if any step fails.

echo "======================================================"
echo "  Browser Automation Studio — Starting Up"
echo "======================================================"

# ── Load environment from .env ────────────────────────────────
if [ -f /app/.env ]; then
    export $(grep -v '^#' /app/.env | grep -v '^$' | xargs)
fi

# ── Create directories ────────────────────────────────────────
mkdir -p /data/cookies /data/outputs /data/downloads \
         /data/chrome-profile /data/ollama /data/logs \
         /var/log/supervisor
# Fix permissions (start.sh runs as root now, so this will succeed on the HF volume)
chown -R appuser:appuser /data 2>/dev/null || true
chmod -R 777 /data 2>/dev/null || true
chmod -R 777 /var/log/supervisor 2>/dev/null || true

# ── Chrome lock cleanup (stale locks from previous runs) ──────
rm -f /data/chrome-profile/SingletonLock    2>/dev/null || true
rm -f /data/chrome-profile/SingletonSocket  2>/dev/null || true
rm -f /data/chrome-profile/SingletonCookie  2>/dev/null || true
rm -f /data/chrome-profile/Default/Cookies-journal 2>/dev/null || true
echo "[start.sh] Chrome lock cleanup done."

# ── Export runtime environment ────────────────────────────────
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export CHROME_EXECUTABLE_PATH="/usr/bin/google-chrome-stable"
export OLLAMA_MODELS="${OLLAMA_MODELS:-/data/ollama}"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
export DISPLAY=:99

# ── Binary check ──────────────────────────────────────────────
echo "[start.sh] Binary check:"
for bin in Xvfb google-chrome-stable x11vnc websockify python3 supervisord ollama; do
    command -v "$bin" &>/dev/null && echo "  ✓ $bin" || echo "  ✗ $bin NOT FOUND"
done
python3 -c "import fastapi; print('  ✓ fastapi', fastapi.__version__)" 2>/dev/null || echo "  ✗ fastapi missing"
python3 -c "import browser_use; print('  ✓ browser_use')" 2>/dev/null || echo "  ✗ browser_use missing"

echo ""
echo "  PRIMARY_LLM = ${PRIMARY_LLM:-qwen}"
echo "  CHROME      = $CHROME_EXECUTABLE_PATH"
echo "  APP_PORT    = ${APP_PORT:-7860}"
echo ""

# ── Start supervisord (manages ALL processes including Ollama) ─
# FastAPI starts immediately → health check responds → HF sees "Running"
# Ollama server starts in parallel → model pull runs after Ollama is ready
echo "[start.sh] Starting supervisord..."
echo "[start.sh] FastAPI will respond to health checks immediately."
echo "[start.sh] Ollama model pull runs in background (check /data/logs/ollama-pull.log)."
exec /usr/bin/supervisord -n -c /app/supervisord.conf
