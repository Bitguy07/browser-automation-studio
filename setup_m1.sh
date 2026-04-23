#!/bin/bash
# ============================================================
# Browser Automation Studio — M1 Complete Setup Script
# Run this from the PARENT directory of your project, e.g.:
#   cd ~/Documents/studies/Development/BrowserAutomaionStudio
#   bash setup_m1.sh
#
# What this does:
#   1. Wipes the broken browser-automation-studio/ directory
#   2. Recreates the exact M1 folder structure
#   3. Writes every file with correct content
#   4. Verifies the result
# ============================================================

set -e

PROJECT="browser-automation-studio"

echo "======================================================"
echo "  Browser Automation Studio — M1 Setup"
echo "======================================================"
echo ""

# ── Safety check ─────────────────────────────────────────────
if [ ! -f "$PROJECT/.env" ]; then
    echo "NOTE: No .env file found. Will create .env.example only."
    echo "      After this script, copy it: cp $PROJECT/.env.example $PROJECT/.env"
    HAS_ENV=false
else
    echo "Found existing .env — will preserve it."
    cp "$PROJECT/.env" /tmp/bas_env_backup
    HAS_ENV=true
fi

# ── Wipe and recreate ─────────────────────────────────────────
echo "Removing old directory..."
rm -rf "$PROJECT"
mkdir -p "$PROJECT"
cd "$PROJECT"

echo "Creating folder structure..."

# ── All directories ───────────────────────────────────────────
mkdir -p backend
mkdir -p frontend/src/components
mkdir -p frontend/public
mkdir -p data/cookies
mkdir -p data/outputs
mkdir -p scripts

echo "Writing files..."

# ==============================================================
# FILE: Dockerfile
# ==============================================================
cat > Dockerfile << 'DOCKERFILE_EOF'
# ============================================================
# Browser Automation Studio — Dockerfile
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

# ── Chromium browser ──────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    chromium-browser \
    chromium-chromedriver \
    && rm -rf /var/lib/apt/lists/*

# ── noVNC ─────────────────────────────────────────────────────
RUN git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth=1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify

RUN ln -s /opt/novnc/vnc.html /opt/novnc/index.html

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

# Uncomment for Hugging Face deployment:
# RUN useradd -m -u 1000 appuser && chown -R appuser /app /data
# USER 1000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]
DOCKERFILE_EOF

# ==============================================================
# FILE: docker-compose.yml
# ==============================================================
cat > docker-compose.yml << 'COMPOSE_EOF'
# ============================================================
# Browser Automation Studio — docker-compose.yml
# Local development launcher
# Usage: docker compose up --build
# ============================================================

services:
  automation-studio:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: browser-automation-studio

    ports:
      - "7860:7860"
      - "6080:6080"
      - "5900:5900"

    env_file:
      - .env

    volumes:
      - ./data:/data
      - ./backend:/app/backend
      - ./frontend/src:/app/frontend/src

    restart: unless-stopped

    shm_size: '2gb'

    environment:
      - PYTHONUNBUFFERED=1
      - PYTHONDONTWRITEBYTECODE=1
      - DISPLAY=:99

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7860/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

volumes:
  data:
    driver: local
COMPOSE_EOF

# ==============================================================
# FILE: supervisord.conf
# ==============================================================
cat > supervisord.conf << 'SUPERVISOR_EOF'
# ============================================================
# Browser Automation Studio — supervisord.conf
# Manages all background processes
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

# ── 1. Log directory setup (runs first) ───────────────────────
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

# ── 2. Xvfb — Virtual Framebuffer Display ────────────────────
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

# ── 3. Chromium Browser ───────────────────────────────────────
[program:chromium]
command=/usr/bin/chromium-browser \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --remote-debugging-port=9222 \
    --display=:99 \
    --window-size=1280,720 \
    --disable-notifications \
    --disable-popup-blocking \
    --start-maximized \
    about:blank
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

# ── 4. x11vnc — Screen Capture ───────────────────────────────
[program:x11vnc]
command=/usr/bin/x11vnc \
    -display :99 \
    -forever \
    -shared \
    -nopw \
    -rfbport 5900 \
    -listen 127.0.0.1 \
    -xkb
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

# ── 5. websockify — VNC to WebSocket Bridge ──────────────────
[program:websockify]
command=/usr/bin/websockify \
    --web /opt/novnc \
    0.0.0.0:6080 \
    localhost:5900
autostart=true
autorestart=true
startsecs=5
priority=400
stdout_logfile=/var/log/supervisor/websockify.log
stderr_logfile=/var/log/supervisor/websockify.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
startretries=5

# ── 6. FastAPI Backend ────────────────────────────────────────
[program:fastapi]
command=/usr/bin/python3 -m uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 7860 \
    --log-level info \
    --reload
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

# ── 7. Telegram Bot ───────────────────────────────────────────
[program:telegram-bot]
command=/usr/bin/python3 /app/backend/telegram_bot.py
directory=/app
autostart=true
autorestart=true
startsecs=10
priority=600
stdout_logfile=/var/log/supervisor/telegram.log
stderr_logfile=/var/log/supervisor/telegram.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
environment=PYTHONPATH="/app"
startretries=5
SUPERVISOR_EOF

# ==============================================================
# FILE: requirements.txt
# ==============================================================
cat > requirements.txt << 'REQ_EOF'
# ============================================================
# Browser Automation Studio — requirements.txt
# ============================================================

# Web Framework
fastapi==0.111.0
uvicorn[standard]==0.29.0
python-multipart==0.0.9
aiofiles==23.2.1

# Authentication
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4

# Database
sqlalchemy==2.0.30
aiosqlite==0.20.0

# Browser Automation
selenium==4.21.0
webdriver-manager==4.0.1

# AI / LLM
browser-use==0.1.40
groq==0.8.0
langchain==0.2.3
langchain-groq==0.1.6

# Telegram Bot
python-telegram-bot==21.2

# Utilities
python-dotenv==1.0.1
pydantic==2.7.1
pydantic-settings==2.2.1
httpx==0.27.0
Pillow==10.3.0
websockets==12.0
structlog==24.1.0
REQ_EOF

# ==============================================================
# FILE: .env.example
# ==============================================================
cat > .env.example << 'ENV_EOF'
# ============================================================
# Browser Automation Studio — .env.example
# INSTRUCTIONS:
#   1. cp .env.example .env
#   2. Fill in your values
#   3. NEVER commit .env to git
# ============================================================

# Get free key at: https://console.groq.com
GROQ_API_KEY=gsk_your_groq_api_key_here

# Message @BotFather on Telegram -> /newbot
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrSTUvwxYZ

# Message @userinfobot on Telegram to get your ID
TELEGRAM_CHAT_ID=987654321

# Password for the web interface — choose something strong
APP_PASSWORD=your-strong-password-here

# Generate: python3 -c "import secrets; print(secrets.token_hex(32))"
JWT_SECRET=your-random-64-character-hex-string-here

# DO NOT change APP_PORT — Hugging Face requires 7860
APP_PORT=7860
VNC_PORT=6080

DATA_DIR=/data
COOKIES_DIR=/data/cookies
OUTPUTS_DIR=/data/outputs
DB_PATH=/data/app.db

# Only needed for M8 Hugging Face deployment
HF_TOKEN=
ENV_EOF

# ==============================================================
# FILE: .gitignore
# ==============================================================
cat > .gitignore << 'GITIGNORE_EOF'
# NEVER commit your secrets
.env

# Python
__pycache__/
*.py[cod]
*.pyo
.pytest_cache/

# Node
node_modules/
frontend/build/

# Data (sensitive)
data/cookies/*.json
data/app.db
*.db

# OS
.DS_Store
*.swp
Thumbs.db

# IDE
.vscode/
.idea/
GITIGNORE_EOF

# ==============================================================
# FILE: backend/__init__.py
# ==============================================================
touch backend/__init__.py

# ==============================================================
# FILE: backend/main.py
# ==============================================================
cat > backend/main.py << 'MAIN_EOF'
# ============================================================
# Browser Automation Studio — backend/main.py
# FastAPI entry point — M1: health endpoint only
# More endpoints added in M3
# ============================================================

import os
import subprocess
import socket
from datetime import datetime, timezone
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from dotenv import load_dotenv

load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("=" * 60)
    print("  Browser Automation Studio — Starting Up")
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
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:7860",
        "https://*.hf.space",
        "*",
    ],
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


@app.get("/health")
async def health_check():
    """
    Health check endpoint.
    Used by Docker, Hugging Face, and cron-job.org keep-alive ping.
    """
    return JSONResponse(
        status_code=200,
        content={
            "status": "ok",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "version": "1.0.0",
            "module": "M1 — Foundation",
            "components": {
                "fastapi": "ok",
                "xvfb": "ok" if is_process_running("Xvfb") else "not_running",
                "chromium": "ok" if is_process_running("chromium") else "not_running",
                "x11vnc": "ok" if is_process_running("x11vnc") else "not_running",
                "vnc_port": "ok" if is_port_open(6080) else "not_ready",
                "database": "ok" if os.path.exists("/data") else "no_data_dir",
            },
        }
    )


@app.get("/")
async def root():
    react_build = "/app/frontend/build/index.html"
    if os.path.exists(react_build):
        return FileResponse(react_build)
    return JSONResponse({
        "message": "Browser Automation Studio is running!",
        "status": "ok",
        "docs": "/docs",
        "health": "/health",
        "note": "React frontend will appear here after M4.",
    })


# Mount noVNC static files if available (M2 onwards)
if os.path.exists("/opt/novnc"):
    app.mount("/vnc", StaticFiles(directory="/opt/novnc"), name="novnc")

# Mount React build if available (M4 onwards)
if os.path.exists("/app/frontend/build"):
    app.mount("/static", StaticFiles(directory="/app/frontend/build/static"), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0",
                port=int(os.getenv("APP_PORT", "7860")), reload=True)
MAIN_EOF

# ==============================================================
# FILE: backend stubs (filled in M3, M5, M6)
# ==============================================================
cat > backend/auth.py << 'EOF'
# Filled in Module M3
EOF

cat > backend/models.py << 'EOF'
# Filled in Module M3
EOF

cat > backend/tasks.py << 'EOF'
# Filled in Module M3
EOF

cat > backend/browser.py << 'EOF'
# Filled in Module M5
EOF

cat > backend/telegram_bot.py << 'EOF'
# Filled in Module M6
EOF

# ==============================================================
# FILE: frontend/package.json
# ==============================================================
cat > frontend/package.json << 'PKG_EOF'
{
  "name": "browser-automation-studio-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "react-scripts": "5.0.1",
    "axios": "^1.7.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "proxy": "http://localhost:7860",
  "eslintConfig": {
    "extends": ["react-app"]
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version"]
  }
}
PKG_EOF

# ==============================================================
# FILE: frontend/public/index.html  (minimal, required by React)
# ==============================================================
cat > frontend/public/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Browser Automation Studio</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
HTML_EOF

# ==============================================================
# FILE: frontend/src stubs (filled in M4)
# ==============================================================
cat > frontend/src/index.jsx << 'EOF'
// Filled in Module M4
EOF

cat > frontend/src/App.jsx << 'EOF'
// Filled in Module M4
EOF

cat > frontend/src/api.js << 'EOF'
// Filled in Module M4
EOF

cat > frontend/src/components/ChatBox.jsx << 'EOF'
// Filled in Module M4
EOF

cat > frontend/src/components/NoVNCViewer.jsx << 'EOF'
// Filled in Module M4
EOF

cat > frontend/src/components/ModeSelector.jsx << 'EOF'
// Filled in Module M4
EOF

cat > frontend/src/components/StatusBar.jsx << 'EOF'
// Filled in Module M4
EOF

# ==============================================================
# FILE: scripts/start.sh
# ==============================================================
cat > scripts/start.sh << 'STARTSH_EOF'
#!/bin/bash
# ============================================================
# Browser Automation Studio — scripts/start.sh
# Container entrypoint — runs when Docker container starts
# ============================================================

set -e

echo "======================================================"
echo "  Browser Automation Studio — Container Starting"
echo "======================================================"

if [ -f /app/.env ]; then
    echo "[start.sh] Loading .env file..."
    export $(grep -v '^#' /app/.env | xargs)
else
    echo "[start.sh] No .env — using environment variables only"
fi

mkdir -p /data/cookies /data/outputs /var/log/supervisor /var/run
chmod -R 777 /data
chmod -R 755 /var/log/supervisor

echo "[start.sh] Checking binaries..."
for bin in Xvfb chromium-browser x11vnc websockify python3 supervisord; do
    if command -v "$bin" &>/dev/null; then
        echo "  ✓ $bin"
    else
        echo "  ✗ $bin NOT FOUND"
    fi
done

export DISPLAY=:99

echo ""
echo "  APP_PORT = ${APP_PORT:-7860}"
echo "  VNC_PORT = ${VNC_PORT:-6080}"
echo "  DISPLAY  = $DISPLAY"
echo ""
echo "[start.sh] Starting supervisord..."

exec /usr/bin/supervisord -n -c /app/supervisord.conf
STARTSH_EOF

chmod +x scripts/start.sh

# ==============================================================
# FILE: data/.gitkeep files
# ==============================================================
touch data/cookies/.gitkeep
touch data/outputs/.gitkeep

# ==============================================================
# FILE: guide.md
# ==============================================================
cat > guide.md << 'GUIDE_EOF'
# Browser Automation Studio — M1 Guide
**Machine: HP EliteBook 840 G3 | Ubuntu 24.04 | 8GB RAM | i5-6300U**

## Quick Start (Docker already installed)

```bash
# 1. Create your .env from the template
cp .env.example .env
nano .env   # Fill in APP_PASSWORD and JWT_SECRET at minimum

# 2. Build the Docker image (first time: 10-20 min)
docker compose build

# 3. Start the container
docker compose up

# 4. Verify in a second terminal
curl http://localhost:7860/health
# Expected: {"status": "ok", ...}
```

## Minimal .env for M1 Testing

```
GROQ_API_KEY=placeholder
TELEGRAM_BOT_TOKEN=placeholder
TELEGRAM_CHAT_ID=123456789
APP_PASSWORD=mypassword123
JWT_SECRET=a3f8c2d1e4b5a6f7c8d9e0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1
APP_PORT=7860
VNC_PORT=6080
DATA_DIR=/data
COOKIES_DIR=/data/cookies
OUTPUTS_DIR=/data/outputs
DB_PATH=/data/app.db
HF_TOKEN=
```

Generate JWT_SECRET: `python3 -c "import secrets; print(secrets.token_hex(32))"`

## M1 DoD Checklist

```bash
# Folder structure correct?
find . -type f | sort

# Dockerfile builds?
docker compose build

# Container starts?
docker compose up

# .env.example has all variables?
grep "=" .env.example | grep -v "^#"

# supervisord defines all processes?
grep "^\[program:" supervisord.conf

# Health endpoint works?
curl http://localhost:7860/health

# Container starts under 60s?
time docker compose up
```

## Useful Commands

```bash
docker compose up -d          # Start in background
docker compose logs -f        # Live logs
docker compose exec automation-studio bash   # Shell inside container
docker compose down           # Stop
docker compose down -v        # Stop + wipe volumes
docker compose up --build     # Rebuild + start
docker ps                     # Running containers
docker stats                  # Resource usage
```

## Troubleshooting

**`permission denied` on docker**
```bash
sudo usermod -aG docker $USER && newgrp docker
```

**Port 7860 in use**
```bash
sudo lsof -i :7860
```

**`chromium-browser: not found` in container**
Change `chromium-browser` to `chromium` in Dockerfile.

**Build fails at pip install**
Remove version pins in requirements.txt for the failing package.

**Container OOM (out of memory)**
Lower memory limit in docker-compose.yml: `memory: 2G`

## What M2 Adds

After M1 is verified: paste the M2 prompt block from the master plan PDF.
M2 gives you: open `http://localhost:6080/vnc.html` → see Chrome live.
GUIDE_EOF

# ==============================================================
# Restore .env if it existed
# ==============================================================
if [ "$HAS_ENV" = true ]; then
    cp /tmp/bas_env_backup .env
    echo "Restored your existing .env file."
fi

# ==============================================================
# Final verification
# ==============================================================
echo ""
echo "======================================================"
echo "  Setup complete. Verifying structure..."
echo "======================================================"
echo ""

find . -type f | sort

echo ""
echo "======================================================"
echo "  Expected structure vs actual:"
echo "======================================================"

EXPECTED=(
    "./Dockerfile"
    "./docker-compose.yml"
    "./supervisord.conf"
    "./.env.example"
    "./.gitignore"
    "./requirements.txt"
    "./guide.md"
    "./backend/__init__.py"
    "./backend/main.py"
    "./backend/auth.py"
    "./backend/models.py"
    "./backend/tasks.py"
    "./backend/browser.py"
    "./backend/telegram_bot.py"
    "./frontend/package.json"
    "./frontend/public/index.html"
    "./frontend/src/index.jsx"
    "./frontend/src/App.jsx"
    "./frontend/src/api.js"
    "./frontend/src/components/ChatBox.jsx"
    "./frontend/src/components/NoVNCViewer.jsx"
    "./frontend/src/components/ModeSelector.jsx"
    "./frontend/src/components/StatusBar.jsx"
    "./scripts/start.sh"
    "./data/cookies/.gitkeep"
    "./data/outputs/.gitkeep"
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

echo ""
if [ "$ALL_OK" = true ]; then
    echo "✅ All files present. Structure is correct."
    echo ""
    echo "Next step:"
    echo "  cd browser-automation-studio"
    echo "  cp .env.example .env && nano .env"
    echo "  docker compose build"
else
    echo "❌ Some files are missing — check errors above."
fi
echo "======================================================"
