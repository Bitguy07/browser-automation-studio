# Browser Automation Studio — M1 Setup Guide
**Your machine: HP EliteBook 840 G3 | Ubuntu 24.04 LTS | 8GB RAM | i5-6300U**

---

## Before You Start — Important Notes for Your Machine

Your machine has **~4GB free RAM** (7694MB total, 3770MB used). Docker + Chrome inside the container
will use roughly 1.5–2GB. You have enough headroom. The `docker-compose.yml` caps container memory at 4GB.

Your CPU is an **Intel i5-6300U (4 cores, 3GHz)** — perfectly capable. Building the Docker image for
the first time will take 10–15 minutes. Subsequent rebuilds are faster (Docker caches layers).

---

## Step 1 — Install Docker on Ubuntu 24.04

Ubuntu 24.04 requires the official Docker repo (not the snap version — snap Docker has issues).

### 1a. Remove old versions (if any)
```bash
sudo apt-get remove docker docker-engine docker.io containerd runc 2>/dev/null
```

### 1b. Add Docker's official GPG key and repo
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### 1c. Install Docker Engine + Docker Compose
```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 1d. Allow your user to run Docker WITHOUT sudo (important)
```bash
sudo usermod -aG docker $USER

# Apply the group change — you MUST do one of these:
newgrp docker          # Option A: apply in current terminal (temporary)
# OR
sudo reboot            # Option B: reboot (permanent, recommended)
```

### 1e. Verify Docker works
```bash
docker --version         # Should show: Docker version 26.x.x
docker compose version   # Should show: Docker Compose version v2.x.x
docker run hello-world   # Should print "Hello from Docker!"
```

If `hello-world` runs without `sudo`, you're ready.

---

## Step 2 — Get the Project Files

### Option A: If you cloned this from git
```bash
cd browser-automation-studio
ls -la    # You should see Dockerfile, docker-compose.yml, etc.
```

### Option B: If you're creating from scratch
```bash
mkdir browser-automation-studio
cd browser-automation-studio
# Copy all the generated files into this directory
```

---

## Step 3 — Create Your .env File

```bash
cp .env.example .env
nano .env   # or use any text editor
```

Fill in these values:

| Variable | Where to get it |
|---|---|
| `GROQ_API_KEY` | https://console.groq.com → API Keys → Create key (free) |
| `TELEGRAM_BOT_TOKEN` | Message `@BotFather` on Telegram → `/newbot` |
| `TELEGRAM_CHAT_ID` | Message `@userinfobot` on Telegram — it replies with your ID |
| `APP_PASSWORD` | Make up a strong password |
| `JWT_SECRET` | Run: `python3 -c "import secrets; print(secrets.token_hex(32))"` |

For M1, only `APP_PASSWORD` and `JWT_SECRET` are strictly required.
The rest can be placeholder values until M5/M6.

**Example minimal .env for M1 testing:**
```bash
GROQ_API_KEY=placeholder_get_this_in_m5
TELEGRAM_BOT_TOKEN=placeholder_get_this_in_m6
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

---

## Step 4 — Build the Docker Image

```bash
cd browser-automation-studio
docker compose build
```

**What happens:** Docker reads the `Dockerfile` and:
1. Downloads Ubuntu 22.04 (~80MB)
2. Installs Python 3.11, Node 18, Chromium, Xvfb, x11vnc, noVNC (~800MB total)
3. Installs Python packages from `requirements.txt`
4. Installs Node packages for React

**First build time on your machine: 10–20 minutes** (depends on internet speed)

Watch the output for errors. Common first-build issues:
- `apt-get` failures → usually network issue, retry with `docker compose build --no-cache`
- `pip install` failures → version conflicts — see Troubleshooting below

---

## Step 5 — Start the Container

```bash
docker compose up
```

You should see logs flowing in the terminal. Look for:
```
[start.sh] ✓ Xvfb found
[start.sh] ✓ chromium-browser found
[start.sh] ✓ x11vnc found
...
INFO:     Uvicorn running on http://0.0.0.0:7860
```

Leave this terminal open. Open a **second terminal** for the next step.

---

## Step 6 — Verify the Health Endpoint (M1 DoD item 6)

```bash
curl http://localhost:7860/health
```

Expected response:
```json
{
  "status": "ok",
  "timestamp": "2025-xx-xxTxx:xx:xxZ",
  "version": "1.0.0",
  "module": "M1 — Foundation",
  "components": {
    "fastapi": "ok",
    "xvfb": "ok",
    "chromium": "ok",
    ...
  }
}
```

Or open in browser: **http://localhost:7860/health**

If you see `{"status": "ok", ...}` — M1 DoD item 6 is ✅ complete.

---

## M1 DoD Checklist — How to Verify Each Item

### ☐ Folder structure created exactly as above
```bash
find . -type f | sort
# Should show all files listed in the plan
```

### ☐ Dockerfile builds without error
```bash
docker compose build
# Last line should be: => exporting to image  (no ERROR lines)
```

### ☐ docker-compose up runs without error
```bash
docker compose up
# Should see supervisord starting all processes
# No "error" or "failed" lines in red
```

### ☐ .env.example has all required variable names
```bash
cat .env.example | grep -v "^#" | grep "="
# Should show all 11 variables
```

### ☐ supervisord.conf defines all 5 processes
```bash
grep "^\[program:" supervisord.conf
# Should show: xvfb, chromium, x11vnc, websockify, fastapi, telegram-bot
```

### ☐ GET /health returns {status: ok} in browser
```bash
curl http://localhost:7860/health
# Should return JSON with "status": "ok"
```

### ☐ requirements.txt installs without pip errors
```bash
docker compose run --rm automation-studio pip install -r requirements.txt
# Or check logs during docker compose build
```

### ☐ Container starts in under 60 seconds
```bash
time docker compose up
# From "Starting supervisor" to "Uvicorn running" should be < 60s
```

---

## Useful Docker Commands

```bash
# Start container in background (detached mode)
docker compose up -d

# See live logs
docker compose logs -f

# See logs for a specific service
docker compose logs -f automation-studio

# Open a shell INSIDE the running container
docker compose exec automation-studio bash

# Stop everything
docker compose down

# Stop AND delete all data volumes (full reset)
docker compose down -v

# Rebuild after code changes
docker compose up --build

# Check running containers
docker ps

# Check container resource usage
docker stats
```

---

## Troubleshooting

### Problem: `permission denied` when running docker
**Fix:** You haven't added your user to the docker group yet.
```bash
sudo usermod -aG docker $USER
newgrp docker   # Apply immediately without reboot
```

### Problem: `Port 7860 already in use`
**Fix:** Something else is using that port.
```bash
sudo lsof -i :7860   # Find what's using it
# Or change port in docker-compose.yml: "7861:7860"
```

### Problem: `Cannot connect to Docker daemon`
**Fix:** Docker service isn't running.
```bash
sudo systemctl start docker
sudo systemctl enable docker   # Make it start on boot
```

### Problem: Build fails at `pip install browser-use`
**Fix:** This package is relatively new. Try pinning to a specific version:
```bash
# In requirements.txt, change:
browser-use==0.1.40
# To the latest available:
browser-use  # no version pin
```

### Problem: `x11vnc: unable to open display ':99'`
**Fix:** Xvfb didn't start before x11vnc. The supervisord `priority` values should handle this,
but if it still fails:
```bash
# Inside the container:
docker compose exec automation-studio bash
Xvfb :99 -screen 0 1280x720x24 &
x11vnc -display :99 -forever -nopw &
```

### Problem: Container uses too much memory
**Fix:** Your machine has 8GB but only ~4GB free. Reduce the limit in docker-compose.yml:
```yaml
deploy:
  resources:
    limits:
      memory: 2G    # Reduce from 4G
```

### Problem: `chromium-browser: not found` inside container
**Fix:** Some Ubuntu 22.04 images name it differently. Try:
```bash
# In Dockerfile, replace:
chromium-browser
# With:
chromium
```

---

## What's Next: Module M2

Once all M1 DoD boxes are ticked, you're ready for M2. M2 will:
- Verify Xvfb + Chrome are actually drawing to the virtual screen
- Set up noVNC so you can **see Chrome in your browser**
- Add a screenshot API endpoint

**Your M2 prompt is in the master plan PDF, section "M2 Claude Prompt Block".**

---

## Architecture Reminder (What M1 Gives You)

```
Your Terminal
    ↓
docker compose up
    ↓
Docker Container starts on your machine
    ├─ supervisord starts all processes:
    │   ├─ Xvfb :99 (virtual screen — Chrome will draw here)
    │   ├─ Chromium (invisible browser on virtual screen)
    │   ├─ x11vnc (captures virtual screen)
    │   ├─ websockify (converts VNC to WebSocket)
    │   └─ FastAPI on port 7860 (API + will serve React later)
    │
Your Browser → http://localhost:7860/health → {"status": "ok"}
```

In M2, you'll add: `Your Browser → http://localhost:6080/vnc.html → See Chrome live`