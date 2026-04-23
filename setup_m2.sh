#!/bin/bash
# ============================================================
# Browser Automation Studio — setup_m2.sh
# Applies M2 file changes to your existing project.
#
# Run from the PARENT directory:
#   cd ~/Documents/studies/Development/BrowserAutomaionStudio
#   bash setup_m2.sh
#
# What this does:
#   1. Updates Dockerfile  (adds scrot, google-chrome)
#   2. Updates requirements.txt  (adds websocket-client)
#   3. Updates supervisord.conf  (single-line commands, fixes)
#   4. Updates backend/main.py  (screenshot + vnc status endpoints)
#   5. Writes guide_m2.md
#   6. Verifies all files are present
#   Does NOT touch: .env, frontend/, data/, scripts/
# ============================================================

set -e

echo "======================================================"
echo "  Browser Automation Studio — M2 Setup"
echo "======================================================"

# Works whether you run from INSIDE or OUTSIDE the project directory
if [ -f "Dockerfile" ] && [ -d "backend" ]; then
    echo "Running from inside project directory: $(pwd)"
elif [ -d "browser-automation-studio" ]; then
    cd "browser-automation-studio"
    echo "Entered project directory: $(pwd)"
else
    echo "ERROR: Cannot find project."
    echo "Run from inside browser-automation-studio/ or its parent directory."
    exit 1
fi
echo ""

# ==============================================================
# FILE: Dockerfile
# ==============================================================
echo "Writing Dockerfile..."
cat > Dockerfile << 'DOCKERFILE_EOF'
# ============================================================
# Browser Automation Studio — Dockerfile
# M2: Added scrot (screenshot tool)
# Base: Ubuntu 22.04 | Compatible with Hugging Face Spaces
# Primary port: 7860 (FastAPI) | VNC port: 6080
# ============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

# ── System locale ─────────────────────────────────────────────
RUN apt-get update && apt-get install -y locales && \
    locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ── Core system packages ──────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git unzip ca-certificates gnupg \
    software-properties-common build-essential \
    libssl-dev libffi-dev \
    xvfb x11vnc \
    websockify \
    supervisor \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps htop nano \
    scrot \
    && rm -rf /var/lib/apt/lists/*

# ── Python 3.11 ───────────────────────────────────────────────
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && apt-get install -y \
    python3.11 python3.11-dev python3.11-distutils python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

# ── Node.js 18 ────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Google Chrome (real binary, not Ubuntu snap stub) ─────────
# Ubuntu 22.04's chromium-browser is a snap stub that fails in Docker.
# Google Chrome stable provides a real binary at /usr/bin/google-chrome-stable
RUN apt-get update && apt-get install -y \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 \
    libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2 \
    libcairo2 libpango-1.0-0 libgtk-3-0 libvulkan1 xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /tmp/google-chrome.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/google-chrome.deb && \
    rm /tmp/google-chrome.deb && \
    rm -rf /var/lib/apt/lists/*

# Symlink so supervisord uses /usr/bin/chromium
RUN ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium

# ── noVNC ─────────────────────────────────────────────────────
RUN git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth=1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify

RUN ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

WORKDIR /app

# ── Python dependencies ───────────────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Node/React dependencies ───────────────────────────────────
COPY frontend/package.json ./frontend/
RUN cd frontend && npm install

# ── Copy all application code ─────────────────────────────────
COPY . .

# ── Build React frontend ──────────────────────────────────────
RUN cd frontend && npm run build

# ── Persistent data directory ─────────────────────────────────
RUN mkdir -p /data/cookies /data/outputs && \
    chmod -R 777 /data

RUN chmod +x /app/scripts/start.sh

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]
DOCKERFILE_EOF

# ==============================================================
# FILE: requirements.txt
# ==============================================================
echo "Writing requirements.txt..."
cat > requirements.txt << 'REQ_EOF'
# ============================================================
# Browser Automation Studio — requirements.txt
# M2: Added websocket-client for Chrome DevTools Protocol
# ============================================================

# Web Framework
fastapi>=0.111.0
uvicorn[standard]>=0.29.0
python-multipart>=0.0.9
aiofiles>=23.2.1

# Authentication
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4

# Database
sqlalchemy>=2.0.30
aiosqlite>=0.20.0

# Browser Automation
selenium>=4.21.0
webdriver-manager>=4.0.1

# AI / LLM
browser-use>=0.1.40
groq>=0.8.0
langchain>=0.2.3
langchain-groq>=0.1.6

# Telegram Bot
python-telegram-bot>=21.2

# Utilities
python-dotenv>=1.0.1
pydantic>=2.7.1
pydantic-settings>=2.2.1
httpx>=0.27.2
Pillow>=10.3.0
websockets>=12.0
structlog>=24.1.0

# M2: Chrome DevTools Protocol screenshot support
websocket-client>=1.7.0
REQ_EOF

# ==============================================================
# FILE: supervisord.conf
# ==============================================================
echo "Writing supervisord.conf..."
cat > supervisord.conf << 'SUPERVISOR_EOF'
# ============================================================
# Browser Automation Studio — supervisord.conf
# M2: All commands single-line, correct chromium path
# ============================================================

[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=50MB
logfile_backups=3
loglevel=info
pidfile=/var/run/supervisord.pid
user=root

[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

# ── 1. Log directory setup ────────────────────────────────────
[program:log-setup]
command=/bin/bash -c "mkdir -p /var/log/supervisor && echo 'Log dirs ready'"
autostart=true
autorestart=false
startsecs=0
priority=50
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

# ── 2. Xvfb ──────────────────────────────────────────────────
[program:xvfb]
command=/usr/bin/Xvfb :99 -screen 0 1280x720x24 -ac +extension GLX +render -noreset
autostart=true
autorestart=true
startsecs=2
priority=100
stdout_logfile=/var/log/supervisor/xvfb.log
stderr_logfile=/var/log/supervisor/xvfb.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
environment=HOME="/root"

# ── 3. Chromium ───────────────────────────────────────────────
[program:chromium]
command=/usr/bin/chromium --no-sandbox --disable-dev-shm-usage --disable-gpu --remote-debugging-port=9222 --window-size=1280,720 --disable-notifications --disable-popup-blocking --start-maximized about:blank
autostart=true
autorestart=true
startsecs=5
priority=200
stdout_logfile=/var/log/supervisor/chromium.log
stderr_logfile=/var/log/supervisor/chromium.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
environment=DISPLAY=":99",HOME="/root"
startretries=5

# ── 4. x11vnc ─────────────────────────────────────────────────
[program:x11vnc]
command=/usr/bin/x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -listen 127.0.0.1 -xkb
autostart=true
autorestart=true
startsecs=3
priority=300
stdout_logfile=/var/log/supervisor/x11vnc.log
stderr_logfile=/var/log/supervisor/x11vnc.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
environment=DISPLAY=":99",HOME="/root"
startretries=5

# ── 5. websockify ─────────────────────────────────────────────
[program:websockify]
command=/usr/bin/python3 -m websockify --web=/opt/novnc 6080 localhost:5900
autostart=true
autorestart=true
startsecs=5
priority=400
stdout_logfile=/var/log/supervisor/websockify.log
stderr_logfile=/var/log/supervisor/websockify.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
startretries=5

# ── 6. FastAPI ────────────────────────────────────────────────
[program:fastapi]
command=/usr/bin/python3 -m uvicorn backend.main:app --host 0.0.0.0 --port 7860 --log-level info --reload
directory=/app
autostart=true
autorestart=true
startsecs=5
priority=500
stdout_logfile=/var/log/supervisor/fastapi.log
stderr_logfile=/var/log/supervisor/fastapi.err
stdout_logfile_maxbytes=20MB
stderr_logfile_maxbytes=20MB
environment=PYTHONPATH="/app",DISPLAY=":99"
startretries=5

# ── 7. Telegram Bot (stub until M6) ──────────────────────────
[program:telegram-bot]
command=/usr/bin/python3 /app/backend/telegram_bot.py
directory=/app
autostart=true
autorestart=false
startsecs=0
priority=600
stdout_logfile=/var/log/supervisor/telegram.log
stderr_logfile=/var/log/supervisor/telegram.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
environment=PYTHONPATH="/app"
SUPERVISOR_EOF

# ==============================================================
# FILE: backend/main.py
# ==============================================================
echo "Writing backend/main.py..."
cat > backend/main.py << 'MAIN_EOF'
# ============================================================
# Browser Automation Studio — backend/main.py
# M2: Added /api/browser/screenshot endpoint
#     Added /api/vnc/status endpoint
#     noVNC served at /vnc via FastAPI static mount
# ============================================================

import os
import base64
import subprocess
import socket
import tempfile
from datetime import datetime, timezone
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from dotenv import load_dotenv

load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("=" * 60)
    print("  Browser Automation Studio — Starting Up (M2)")
    print(f"  Port: {os.getenv('APP_PORT', '7860')}")
    print(f"  Running in: {'Docker' if os.path.exists('/.dockerenv') else 'Local'}")
    print("=" * 60)
    for path in ["/data", "/data/cookies", "/data/outputs"]:
        os.makedirs(path, exist_ok=True)
    yield
    print("Browser Automation Studio — Shutting down.")


app = FastAPI(
    title="Browser Automation Studio",
    description="Self-hosted browser automation platform with AI",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:7860", "https://*.hf.space", "*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def is_process_running(name: str) -> bool:
    try:
        result = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
        return result.returncode == 0
    except Exception:
        return False


def is_port_open(port: int) -> bool:
    try:
        with socket.create_connection(("localhost", port), timeout=1):
            return True
    except (ConnectionRefusedError, OSError):
        return False


def take_screenshot_scrot() -> str:
    """Capture virtual display :99 using scrot. Returns base64 PNG."""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmppath = tmp.name
    try:
        env = {**os.environ, "DISPLAY": ":99"}
        result = subprocess.run(
            ["scrot", "--display", ":99", tmppath],
            capture_output=True, text=True, timeout=10, env=env
        )
        if result.returncode != 0:
            raise RuntimeError(f"scrot error: {result.stderr.strip()}")
        with open(tmppath, "rb") as f:
            return base64.b64encode(f.read()).decode("utf-8")
    finally:
        if os.path.exists(tmppath):
            os.unlink(tmppath)


def take_screenshot_cdp() -> str:
    """Capture Chrome content via DevTools Protocol. Returns base64 PNG."""
    import urllib.request
    import json
    import websocket

    try:
        with urllib.request.urlopen("http://localhost:9222/json", timeout=3) as resp:
            pages = json.loads(resp.read())
    except Exception as e:
        raise RuntimeError(f"Cannot reach Chrome DevTools :9222 — {e}")

    page = next((p for p in pages if p.get("type") == "page"), None)
    if not page:
        raise RuntimeError("No Chrome page tab found")

    ws_url = page.get("webSocketDebuggerUrl")
    if not ws_url:
        raise RuntimeError("No WebSocket debugger URL")

    ws = websocket.create_connection(ws_url, timeout=5)
    try:
        ws.send(json.dumps({"id": 1, "method": "Page.captureScreenshot",
                            "params": {"format": "png", "quality": 80}}))
        response = json.loads(ws.recv())
        if "result" in response and "data" in response["result"]:
            return response["result"]["data"]
        raise RuntimeError(f"CDP had no data: {response}")
    finally:
        ws.close()


@app.get("/health")
async def health_check():
    return JSONResponse(status_code=200, content={
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": "2.0.0",
        "module": "M2 — Chrome + noVNC",
        "components": {
            "fastapi": "ok",
            "xvfb": "ok" if is_process_running("Xvfb") else "not_running",
            "chromium": "ok" if is_process_running("chrome") else "not_running",
            "x11vnc": "ok" if is_process_running("x11vnc") else "not_running",
            "websockify": "ok" if is_port_open(6080) else "not_ready",
            "chrome_devtools": "ok" if is_port_open(9222) else "not_ready",
            "database": "ok" if os.path.exists("/data") else "no_data_dir",
        },
    })


@app.post("/api/browser/screenshot")
@app.get("/api/browser/screenshot")
async def browser_screenshot():
    """
    Capture Chrome screen as base64 PNG.
    Tries Chrome DevTools Protocol first, falls back to scrot.
    Use the returned img_src directly in an <img> tag.
    """
    screenshot_b64 = None
    method_used = None

    try:
        screenshot_b64 = take_screenshot_cdp()
        method_used = "chrome_devtools_protocol"
    except Exception as cdp_err:
        try:
            screenshot_b64 = take_screenshot_scrot()
            method_used = "scrot_virtual_display"
        except Exception as scrot_err:
            raise HTTPException(status_code=500, detail={
                "error": "Both screenshot methods failed",
                "cdp_error": str(cdp_err),
                "scrot_error": str(scrot_err),
                "hint": "Check /health — are Chrome and Xvfb running?",
            })

    return JSONResponse(content={
        "status": "ok",
        "screenshot": screenshot_b64,
        "format": "png",
        "encoding": "base64",
        "method": method_used,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "img_src": "data:image/png;base64," + screenshot_b64,
    })


@app.get("/api/vnc/status")
async def vnc_status():
    """Check entire VNC streaming chain."""
    return JSONResponse({
        "chain": {
            "1_xvfb": "running" if is_process_running("Xvfb") else "stopped",
            "2_chromium": "running" if is_process_running("chrome") else "stopped",
            "3_x11vnc": "running" if is_process_running("x11vnc") else "stopped",
            "4_websockify": "running" if is_process_running("websockify") else "stopped",
        },
        "ports": {
            "vnc_raw_5900": "open" if is_port_open(5900) else "closed",
            "novnc_ws_6080": "open" if is_port_open(6080) else "closed",
            "chrome_devtools_9222": "open" if is_port_open(9222) else "closed",
        },
        "access": {
            "novnc_direct": "http://localhost:6080/vnc.html",
            "novnc_via_fastapi": "http://localhost:7860/vnc/vnc.html",
            "screenshot_api": "http://localhost:7860/api/browser/screenshot",
        }
    })


@app.get("/")
async def root():
    react_build = "/app/frontend/build/index.html"
    if os.path.exists(react_build):
        return FileResponse(react_build)
    return JSONResponse({
        "message": "Browser Automation Studio — M2",
        "status": "ok",
        "endpoints": {
            "health": "/health",
            "docs": "/docs",
            "screenshot": "/api/browser/screenshot",
            "vnc_status": "/api/vnc/status",
            "novnc_direct": "http://localhost:6080/vnc.html",
            "novnc_via_fastapi": "http://localhost:7860/vnc/vnc.html",
        }
    })


# noVNC static files at /vnc path
if os.path.exists("/opt/novnc"):
    app.mount("/vnc", StaticFiles(directory="/opt/novnc"), name="novnc")

# React build (M4 onwards)
if os.path.exists("/app/frontend/build"):
    app.mount("/static", StaticFiles(directory="/app/frontend/build/static"), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0",
                port=int(os.getenv("APP_PORT", "7860")), reload=True)
MAIN_EOF

# ==============================================================
# FILE: guide_m2.md
# ==============================================================
echo "Writing guide_m2.md..."
cat > guide_m2.md << 'GUIDE_EOF'
# Browser Automation Studio — M2 Guide
**Chrome + noVNC Live Viewer**

## What Changed from M1

| File | Change |
|---|---|
| `Dockerfile` | Added `scrot` package |
| `requirements.txt` | Added `websocket-client` |
| `supervisord.conf` | All commands single-line (backslash continuation broke supervisord) |
| `backend/main.py` | Added `/api/browser/screenshot` and `/api/vnc/status` endpoints |

## Step 1 — Rebuild the Image

```bash
docker compose down
docker compose build
```

Docker will use cached layers for everything up to the `scrot` addition,
so this rebuild is faster than M1 (~2-5 min).

## Step 2 — Start the Container

```bash
docker compose up
```

Look for ALL of these in the logs:
```
success: xvfb entered RUNNING state
success: chromium entered RUNNING state
success: x11vnc entered RUNNING state
success: websockify entered RUNNING state
success: fastapi entered RUNNING state
```

## Step 3 — Verify Each DoD Item

### DoD 1: Xvfb starts on :99
```bash
curl -s http://localhost:7860/api/vnc/status | jq '.chain."1_xvfb"'
# Expected: "running"
```

### DoD 2: Chromium launches and draws to :99
```bash
curl -s http://localhost:7860/api/vnc/status | jq '.chain."2_chromium"'
# Expected: "running"

# Also verify Chrome DevTools port is open
curl -s http://localhost:9222/json | jq '.[0].type'
# Expected: "page"
```

### DoD 3: x11vnc connects to :99
```bash
curl -s http://localhost:7860/api/vnc/status | jq '.chain."3_x11vnc"'
# Expected: "running"
```

### DoD 4: websockify runs on port 6080
```bash
curl -s http://localhost:7860/api/vnc/status | jq '.ports.novnc_ws_6080'
# Expected: "open"
```

### DoD 5 & 6: Open noVNC — see Chrome, click inside it
Open in your browser:
```
http://localhost:6080/vnc.html
```
Click "Connect". You should see Chrome's window.
Click inside it — Chrome should respond.
Type in the address bar — Chrome should receive keystrokes.

Also works via FastAPI proxy:
```
http://localhost:7860/vnc/vnc.html
```

### DoD 7: Screenshot API works
```bash
# Returns JSON with base64 PNG
curl -s http://localhost:7860/api/browser/screenshot | jq '{status, method, format}'
# Expected: {"status": "ok", "method": "chrome_devtools_protocol", "format": "png"}
```

To actually VIEW the screenshot, open this in your browser:
```
http://localhost:7860/docs
```
Go to `GET /api/browser/screenshot` → Try it out → Execute.
The response will contain `img_src` — copy that value and paste it
into a browser address bar to see the image.

Or use this one-liner to save it as a file:
```bash
curl -s http://localhost:7860/api/browser/screenshot \
  | jq -r '.screenshot' \
  | base64 -d > /tmp/chrome_screenshot.png
xdg-open /tmp/chrome_screenshot.png
```

### DoD 8: VNC connection survives 5 minutes
Open `http://localhost:6080/vnc.html`, connect, leave it open for 5 minutes.
It should not disconnect.

## Full Status Check (all at once)

```bash
# Health check
curl -s http://localhost:7860/health | jq

# VNC chain status
curl -s http://localhost:7860/api/vnc/status | jq

# Screenshot (saves to file)
curl -s http://localhost:7860/api/browser/screenshot \
  | jq -r '.screenshot' | base64 -d > /tmp/shot.png && xdg-open /tmp/shot.png
```

## Troubleshooting

### Chrome not showing in noVNC (black screen)
Chrome may not have loaded yet. Give it 10 seconds then reconnect noVNC.
Also try navigating Chrome to a real page:
```bash
# From inside container:
docker compose exec automation-studio bash
curl http://localhost:9222/json/new?https://google.com
```

### screenshot returns scrot_virtual_display instead of chrome_devtools_protocol
Chrome DevTools port 9222 is not responding. Check:
```bash
curl http://localhost:9222/json
```
If that fails, Chrome crashed. Check logs:
```bash
docker compose exec automation-studio cat /var/log/supervisor/chromium.err
```

### noVNC connects but screen is grey
x11vnc started before Xvfb was ready. It will self-heal on next autorestart.
Wait 10 seconds or restart x11vnc:
```bash
docker compose exec automation-studio supervisorctl restart x11vnc
```

### websockify not running
```bash
docker compose exec automation-studio cat /var/log/supervisor/websockify.err
```

## M2 DoD Checklist

- [ ] Xvfb running: `curl -s http://localhost:7860/api/vnc/status | jq '.chain."1_xvfb"'` = "running"
- [ ] Chromium running: `curl -s http://localhost:7860/api/vnc/status | jq '.chain."2_chromium"'` = "running"
- [ ] x11vnc running: `curl -s http://localhost:7860/api/vnc/status | jq '.chain."3_x11vnc"'` = "running"
- [ ] websockify on 6080: `curl -s http://localhost:7860/api/vnc/status | jq '.ports.novnc_ws_6080'` = "open"
- [ ] noVNC shows Chrome: open http://localhost:6080/vnc.html → Connect → see browser
- [ ] Click works in noVNC
- [ ] Typing works in noVNC
- [ ] VNC stable for 5 min

## Git Commit After M2

```bash
git add .
git commit -m "[M2] chrome-novnc: COMPLETE — all DoD items ticked"
```

## What M3 Adds

M3 builds the full FastAPI backend: JWT auth, SQLite database, task queue,
WebSocket for real-time updates, session management, and all API endpoints
that the React frontend (M4) and Telegram bot (M6) will use.
GUIDE_EOF

# ==============================================================
# Verification
# ==============================================================
echo ""
echo "======================================================"
echo "  Verifying M2 files..."
echo "======================================================"

EXPECTED=(
    "./Dockerfile"
    "./requirements.txt"
    "./supervisord.conf"
    "./backend/main.py"
    "./guide_m2.md"
)

ALL_OK=true
for f in "${EXPECTED[@]}"; do
    if [ -f "$f" ]; then
        echo "  ✓ $f"
    else
        echo "  ✗ MISSING: $f"
        ALL_OK=false
    fi
done

# Verify M1 files still intact
M1_FILES=(
    "./.env"
    "./docker-compose.yml"
    "./scripts/start.sh"
    "./frontend/package.json"
    "./backend/__init__.py"
)
echo ""
echo "  M1 files still present:"
for f in "${M1_FILES[@]}"; do
    if [ -f "$f" ]; then
        echo "  ✓ $f"
    else
        echo "  ✗ MISSING: $f (was this from M1?)"
        ALL_OK=false
    fi
done

echo ""
if [ "$ALL_OK" = true ]; then
    echo "✅ M2 setup complete."
    echo ""
    echo "Next steps:"
    echo "  docker compose down"
    echo "  docker compose build"
    echo "  docker compose up"
    echo "  # Then open: http://localhost:6080/vnc.html"
else
    echo "❌ Some files missing — check above."
fi
echo "======================================================"
