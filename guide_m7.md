# Browser Automation Studio

A self-hosted browser automation platform with AI. Control a real Chrome browser using natural language — from a web UI or Telegram, from anywhere.

```
┌─────────────────────────────────────────────────────┐
│  Your Browser  →  Web UI  →  FastAPI  →  AI Agent   │
│  Telegram      →  Bot     →  FastAPI  →  AI Agent   │
│                                    ↓                 │
│                          Chrome (noVNC live view)    │
│                          sessions persist on disk    │
└─────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | 24+ | `docker --version` |
| Docker Compose | v2+ | `docker compose version` |
| RAM | 4 GB minimum | Chrome + AI agent are memory-hungry |
| Disk | 10 GB free | Docker image + Chrome profile + Playwright |

**API Keys needed:**
- **Google AI (Gemini)** — free tier: [aistudio.google.com](https://aistudio.google.com) → Get API key
- **Groq** (fallback LLM) — free tier: [console.groq.com](https://console.groq.com)
- **Telegram Bot** (optional) — from [@BotFather](https://t.me/BotFather)

---

## Quick Start

### 1. Clone and configure

```bash
git clone <your-repo-url> browser-automation-studio
cd browser-automation-studio

cp .env.example .env
nano .env   # fill in your keys
```

### 2. Fill in `.env`

Minimum required:

```env
APP_PASSWORD=your_secure_password
JWT_SECRET=any_long_random_string_here
GOOGLE_API_KEY=your_gemini_api_key
```

See [`.env.example`](.env.example) for all variables with descriptions.

### 3. Create the Chrome profile directory

```bash
mkdir -p data/chrome-profile
```

This is where Chrome's cookies and login sessions are stored on your host machine. It persists across every `docker compose down/up`.

### 4. Start the container

```bash
docker compose up --build
```

First build takes 8–12 minutes. Subsequent starts take ~30 seconds.

Watch for this — it means everything is ready:

```
success: fastapi entered RUNNING state
success: telegram-bot entered RUNNING state
[start.sh] Chrome lock cleanup done.
```

### 5. Open the web UI

→ **[http://localhost:7860](http://localhost:7860)**

Log in with the `APP_PASSWORD` you set in `.env`.

---

## Session Persistence — How It Works

Chrome's `--user-data-dir` flag is mounted as a Docker volume:

```
./data/chrome-profile/  ←→  /root/.chrome-data  (inside container)
```

This means **every cookie Chrome writes is immediately saved to your host disk**. When you `docker compose down && docker compose up`, Chrome picks up the exact same profile — including all your login sessions — automatically.

**You never need to run any save or load commands.**

### First-time login (one-time only per site)

1. Start the container → open `http://localhost:7860`
2. Look at the Chrome panel on the right (noVNC)
3. Click inside Chrome → navigate to any site → log in normally
4. That's it — `docker compose down` then `docker compose up` → still logged in

### Why it sometimes asks you to verify

Google and some other sites detect when the browser process restarts (new container = new PID, slightly different fingerprint) and may ask you to confirm your account once every few weeks. This is their security system, not a problem with the setup. Just confirm when asked — no re-login needed, just a verification step.

---

## Submitting Tasks

### Via Web UI

Type any natural language objective in the chat panel and press Enter:

```
search for the current Bitcoin price
go to youtube and find videos about machine learning
open gmail and summarize the 3 most recent unread emails
go to chatgpt and ask it to write a poem about space
```

The chat panel shows live step-by-step progress. The Chrome panel shows the browser acting in real time.

### Via Telegram

```
/task search for the current Bitcoin price
/task go to gmail and check unread emails
/video machine learning tutorials
```

The bot sends "Task started…" then edits the message with progress and the final result.

### Via API (curl)

```bash
# Get a token
TOKEN=$(curl -s -X POST http://localhost:7860/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"password":"YOUR_APP_PASSWORD"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Submit a task
curl -X POST http://localhost:7860/api/task/submit \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"objective": "search for Python tutorials on youtube"}'
```

---

## Telegram Commands Reference

| Command | Example | What it does |
|---------|---------|--------------|
| `/task <objective>` | `/task find Bitcoin price` | Runs automation task |
| `/video <topic>` | `/video machine learning` | YouTube search task |
| `/status` | `/status` | Current mode + last 3 tasks |
| `/screenshot` | `/screenshot` | Sends Chrome screenshot as photo |
| `/reset` | `/reset` | Closes stale tabs, navigates to blank |
| `/session save <name>` | `/session save google` | Saves Playwright storage_state snapshot |
| `/session load <name>` | `/session load google` | Restores a saved snapshot |
| `/session list` | `/session list` | Lists saved snapshots |
| `/mode <auto\|manual>` | `/mode manual` | Switches operating mode |
| `/help` | `/help` | Shows all commands |

> **Note on `/session` commands:** These are still available but optional since M7. The Chrome profile volume mount already keeps you logged in automatically. The session save/load commands are useful if you want an explicit named snapshot — for example, to restore a specific login state after testing.

---

## Development Workflow

### Hot reload — no rebuild needed

`docker-compose.yml` mounts source code directly into the container:

```
./backend        → /app/backend     (FastAPI auto-reloads on every .py save)
./frontend/src   → /app/frontend/src
```

Edit any `.py` file → FastAPI reloads automatically in ~2 seconds.

For the Telegram bot (not uvicorn-managed):
```bash
docker cp backend/telegram_bot.py $(docker ps -q):/app/backend/telegram_bot.py
docker exec $(docker ps -q) supervisorctl restart telegram-bot
```

### Check service health

```bash
# All processes at a glance
docker exec $(docker ps -q) supervisorctl status

# Follow specific logs
docker exec $(docker ps -q) tail -f /var/log/supervisor/fastapi.log
docker exec $(docker ps -q) tail -f /var/log/supervisor/telegram.log
docker exec $(docker ps -q) tail -f /var/log/supervisor/chromium.log

# System health endpoint
curl http://localhost:7860/health | python3 -m json.tool
```

### Switch LLM (persistent across restarts)

Edit `.env`:
```env
PRIMARY_LLM=groq        # or gemini
```
Then `docker compose down && docker compose up -d`.

### Run in background

```bash
docker compose up -d          # detached mode
docker compose logs -f        # follow all logs
docker compose down           # stop (data and chrome profile preserved)
```

---

## Port Reference

| Port | Service | URL |
|------|---------|-----|
| 7860 | Web UI + FastAPI | http://localhost:7860 |
| 6080 | noVNC (direct) | http://localhost:6080/vnc.html |
| 5900 | Raw VNC | VNC client apps |
| 9222 | Chrome DevTools | Internal only |

---

## Troubleshooting

**Chrome panel is black / blank**
```bash
docker exec $(docker ps -q) supervisorctl status
# If xvfb or chromium shows STOPPED:
docker exec $(docker ps -q) supervisorctl restart xvfb chromium x11vnc
```

**Chrome not starting — "Failed to create ProcessSingleton"**

This means `start.sh` didn't clean the lock files, or Chrome crashed and left them. Fix:
```bash
docker exec $(docker ps -q) bash -c "
  rm -f /root/.chrome-data/SingletonLock
  rm -f /root/.chrome-data/SingletonSocket
  supervisorctl restart chromium
"
```
If it keeps happening, check that `scripts/start.sh` contains the lock cleanup block.

**Sessions lost after `docker compose up`**

Check that `data/chrome-profile/` exists on your host and is mounted:
```bash
ls -la data/chrome-profile/     # should show Chrome profile files
docker exec $(docker ps -q) ls /root/.chrome-data/   # should match
```
If the directory is empty, Chrome started with a fresh profile. Make sure `docker-compose.yml` has the volume line:
```yaml
- ./data/chrome-profile:/root/.chrome-data
```

**Gemini 429 rate limit**

Normal — `ChatGoogle` retries with exponential backoff. If you hit the 1,000 RPD daily limit, switch to Groq until midnight UTC:
```bash
# Edit .env: PRIMARY_LLM=groq
docker compose down && docker compose up -d
```

**Telegram bot not responding**
```bash
docker exec $(docker ps -q) supervisorctl status telegram-bot
docker exec $(docker ps -q) tail -20 /var/log/supervisor/telegram.err
```
Most common cause: `TELEGRAM_BOT_TOKEN` is invalid or was auto-revoked (happens if you paste it publicly). Get a new token from @BotFather and update `.env`.

**Container runs out of memory**

Reduce memory limit in `docker-compose.yml`:
```yaml
deploy:
  resources:
    limits:
      memory: 3G
```

---

## Security Notes

- `APP_PASSWORD` and `JWT_SECRET` protect the entire web UI — choose strong values
- `TELEGRAM_BOT_TOKEN` is sensitive — never paste it in public chats or logs. Telegram auto-revokes exposed tokens within minutes
- `data/chrome-profile/` contains your browser cookies — treat it like a password file. Add it to `.gitignore`
- The API requires JWT auth on all endpoints — do not expose port 7860 to the public internet without additional firewall rules

---

## Project Structure

```
browser-automation-studio/
├── backend/
│   ├── main.py             # FastAPI routes
│   ├── browser.py          # browser-use AI automation engine
│   ├── tasks.py            # task queue, WebSocket manager
│   ├── auth.py             # JWT auth
│   ├── models.py           # SQLite models
│   └── telegram_bot.py     # Telegram bot (M6)
├── frontend/src/
│   ├── App.jsx
│   ├── api.js
│   └── components/
│       ├── ChatBox.jsx
│       ├── NoVNCViewer.jsx
│       ├── StatusBar.jsx
│       └── ModeSelector.jsx
├── scripts/
│   └── start.sh            # Container entrypoint (cleans Chrome locks)
├── data/                   # Host-mounted persistent storage
│   ├── chrome-profile/     # Chrome user data (cookies, sessions) ← NEW M7
│   ├── cookies/            # Playwright storage_state snapshots (optional)
│   ├── outputs/            # Task output files
│   └── app.db              # SQLite database
├── Dockerfile
├── docker-compose.yml      # Mounts data/chrome-profile → /root/.chrome-data
├── supervisord.conf
├── requirements.txt
├── .env                    # Your config (never commit)
├── .env.example            # Template (commit this)
├── README.md
└── DEPLOYMENT.md
```
