#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# Container entrypoint script
# Runs when Docker container starts
# ============================================================

set -e  # Exit on any error

echo "======================================================"
echo "  Browser Automation Studio — Container Starting"
echo "======================================================"

# ── Load environment variables ────────────────────────────────
if [ -f /app/.env ]; then
    echo "[start.sh] Loading .env file..."
    export $(grep -v '^#' /app/.env | xargs)
else
    echo "[start.sh] No .env file found — using environment variables only"
fi

# ── Create required directories ───────────────────────────────
echo "[start.sh] Creating data directories..."
mkdir -p /data/cookies
mkdir -p /data/outputs
mkdir -p /var/log/supervisor
mkdir -p /var/run

# ── Set correct permissions ───────────────────────────────────
chmod -R 777 /data
chmod -R 755 /var/log/supervisor

# ── Verify critical binaries exist ───────────────────────────
echo "[start.sh] Checking required binaries..."

check_binary() {
    if command -v "$1" &> /dev/null; then
        echo "  ✓ $1 found at $(command -v $1)"
    else
        echo "  ✗ $1 NOT FOUND — this will cause issues"
    fi
}

check_binary Xvfb
check_binary chromium
check_binary x11vnc
check_binary websockify
check_binary python3
check_binary supervisord

# ── Check Python packages ─────────────────────────────────────
echo "[start.sh] Checking Python packages..."
python3 -c "import fastapi; print('  ✓ fastapi', fastapi.__version__)" 2>/dev/null || echo "  ✗ fastapi missing"
python3 -c "import uvicorn; print('  ✓ uvicorn')" 2>/dev/null || echo "  ✗ uvicorn missing"

# ── Set display environment variable ─────────────────────────
export DISPLAY=:99
echo "[start.sh] DISPLAY set to :99"

# ── Print startup info ────────────────────────────────────────
echo ""
echo "======================================================"
echo "  Configuration:"
echo "  APP_PORT  = ${APP_PORT:-7860}"
echo "  VNC_PORT  = ${VNC_PORT:-6080}"
echo "  DATA_DIR  = ${DATA_DIR:-/data}"
echo "  DISPLAY   = $DISPLAY"
echo "======================================================"
echo ""
echo "[start.sh] Starting supervisord..."
echo ""

# ── Start supervisord ─────────────────────────────────────────
# -n: nodaemon (run in foreground, required for Docker)
# -c: config file location

# ── Clean Chrome lock files from previous run ─────────────────
# When /root/.chrome-data is volume-mounted, Chrome leaves behind
# SingletonLock / SingletonSocket on shutdown. Chrome refuses to
# start if it finds these stale files. Delete them before Chrome
# starts so it launches cleanly with the persisted profile.
echo "[start.sh] Cleaning Chrome lock files from previous run..."
rm -f /root/.chrome-data/SingletonLock
rm -f /root/.chrome-data/SingletonSocket
rm -f /root/.chrome-data/SingletonCookie
rm -f /root/.chrome-data/Default/Cookies-journal
rm -f /root/.chrome-data/Default/.org.chromium.Chromium.*
echo "[start.sh] Chrome lock cleanup done."

exec /usr/bin/supervisord -n -c /app/supervisord.conf