#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/delayed_start.sh
# One-shot: waits for FastAPI to be healthy, then starts the
# heavy services (Chrome, VNC chain, Telegram bot).
# This prevents memory spikes that cause HF to pause/kill.
# ============================================================

echo "[delayed_start.sh] Waiting 20s for FastAPI to stabilize..."
sleep 20

# Wait for FastAPI health endpoint (up to 60s more)
for i in $(seq 1 30); do
    if curl -sf http://localhost:7860/health > /dev/null 2>&1; then
        echo "[delayed_start.sh] FastAPI is healthy. Starting heavy services..."
        break
    fi
    if [ "$i" = "30" ]; then
        echo "[delayed_start.sh] WARNING: FastAPI not healthy after 80s. Starting services anyway."
    fi
    sleep 2
done

# Start Chrome → x11vnc → websockify chain
supervisorctl start chromium
sleep 3
supervisorctl start x11vnc
sleep 2
supervisorctl start websockify

echo "[delayed_start.sh] ✓ All services started successfully."
