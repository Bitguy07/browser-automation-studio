#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# Entrypoint for HF Spaces Docker container.
#
# DESIGN:
#   1. Create /data dirs and fix permissions (runs as root)
#   2. Start supervisord in the background
#   3. Tail key log files to stdout so HF can display them
#   4. Wait for supervisord (keeps container alive)
# ============================================================

echo "======================================================"
echo "  Browser Automation Studio — Starting Up"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "======================================================"

# ── Load environment from .env ────────────────────────────────
if [ -f /app/.env ]; then
    export $(grep -v '^#' /app/.env | grep -v '^$' | xargs) 2>/dev/null || true
fi

# ── Create directories (must happen BEFORE supervisord) ───────
echo "[start.sh] Creating data directories..."
mkdir -p /data/cookies /data/outputs /data/downloads \
         /data/chrome-profile /data/ollama /data/logs \
         /var/log/supervisor

# Touch all log files so tail -f doesn't fail
touch /data/logs/fastapi.log /data/logs/fastapi.err \
      /data/logs/ollama.log /data/logs/ollama-pull.log \
      /data/logs/delayed-start.log /data/logs/chromium.log \
      /data/logs/xvfb.log /data/logs/x11vnc.log \
      /data/logs/websockify.log /data/logs/telegram.log \
      /data/logs/hf_fr_agent.log /data/logs/hf_fr_agent.err \
      /data/logs/hf_flight_recorder_metrics.jsonl /data/logs/hf_fr_heartbeat.jsonl

# Fix ownership (we start as root, HF mounts /data as root)
chown -R appuser:appuser /data 2>/dev/null || true
chmod -R 777 /data 2>/dev/null || true
chmod -R 777 /var/log/supervisor 2>/dev/null || true
chmod -R 777 /tmp 2>/dev/null || true
echo "[start.sh] Directories and permissions OK."

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
    command -v "$bin" &>/dev/null && echo "  OK $bin" || echo "  MISSING $bin"
done
/opt/venv/bin/python -c "import fastapi; print('  OK fastapi', fastapi.__version__)" 2>/dev/null || echo "  MISSING fastapi"
/opt/venv/bin/python -c "import browser_use; print('  OK browser_use')" 2>/dev/null || echo "  MISSING browser_use"

echo ""
echo "  PRIMARY_LLM = ${PRIMARY_LLM:-qwen}"
echo "  CHROME      = $CHROME_EXECUTABLE_PATH"
echo "  APP_PORT    = ${APP_PORT:-7860}"
echo ""

# ── Start supervisord in the BACKGROUND ───────────────────────
echo "[start.sh] Starting supervisord..."
/usr/bin/supervisord -n -c /app/supervisord.conf &
SUPERVISOR_PID=$!
echo "[start.sh] supervisord started (PID $SUPERVISOR_PID)"

# ── Wait for log files to be populated ────────────────────────
sleep 3

# ── Tail key logs to stdout so HF displays them ──────────────
echo "[start.sh] Tailing logs to stdout for HF display..."
tail -f /data/logs/fastapi.log \
       /data/logs/fastapi.err \
       /data/logs/delayed-start.log \
       /data/logs/ollama-pull.log \
       2>/dev/null &
TAIL_PID=$!

# ── Wait for supervisord (keeps container alive) ──────────────
wait $SUPERVISOR_PID
EXIT_CODE=$?
echo "[start.sh] supervisord exited with code $EXIT_CODE"

# Cleanup tail
kill $TAIL_PID 2>/dev/null || true
exit $EXIT_CODE
