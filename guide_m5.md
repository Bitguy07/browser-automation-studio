# Browser Automation Studio — M5 Guide
## Real Browser Automation with browser-use 0.12.6

---

## What M5 Builds

M5 replaces the M3 stub with real AI browser automation:

- **browser-use 0.12.6** agent drives Chrome via Playwright CDP
- **Gemini 2.0 Flash** as primary LLM (free, vision-capable)
- **Groq Llama-70B** as fallback (via OpenAI-compat endpoint)
- Real cookie/session save & load (Playwright `storage_state`)
- Live step-by-step progress via WebSocket
- `/reset` command to close stale Chrome tabs
- Groq rate-limit bar in the UI (30 req/min free tier)
- Markdown rendering of AI results

---

## Files Changed in M5

| File | Status | What changed |
|------|--------|-------------|
| `backend/browser.py` | NEW | Full automation engine |
| `backend/tasks.py` | UPDATED | Calls real `browser.run_task()` |
| `backend/main.py` | UPDATED | Real session/screenshot/reset endpoints, v5.0.0 |
| `requirements.txt` | UPDATED | Added `browser-use==0.12.6`, `langchain-google-genai`, `langchain-openai`, removed selenium/groq conflicts |
| `Dockerfile` | UPDATED | Playwright browser install step added |
| `frontend/src/components/ChatBox.jsx` | UPDATED | All UI updates from ui_updates.md |
| `frontend/src/api.js` | UPDATED | Added `resetBrowser()` |
| `frontend/src/App.jsx` | UPDATED | Version badge M4→M5 |

**Files NOT changed** (no modifications needed):
- `backend/auth.py`
- `backend/models.py`
- `backend/telegram_bot.py`
- `supervisord.conf`
- `docker-compose.yml`
- `frontend/src/components/StatusBar.jsx`
- `frontend/src/components/ModeSelector.jsx`
- `frontend/src/components/NoVNCViewer.jsx`
- `frontend/src/index.jsx`
- `frontend/public/index.html`
- `scripts/start.sh`

---

## Critical Dependency Notes

### Why no `langchain-groq`?

`browser-use 0.12.6` pins `groq==1.0.0` exactly.  
`langchain-groq` (all versions) requires `groq<1.0.0`.  
They **cannot coexist**.

**Solution used**: Groq is accessed via `langchain-openai` pointed at Groq's OpenAI-compatible endpoint:
```python
from langchain_openai import ChatOpenAI
llm = ChatOpenAI(
    model="llama-3.3-70b-versatile",
    openai_api_key=GROQ_API_KEY,          # your normal Groq key
    openai_api_base="https://api.groq.com/openai/v1",
)
```
No OpenAI account needed. No extra cost.

### Why no `selenium` in requirements?

`browser-use 0.12.6` uses **Playwright** internally (not Selenium).  
The old `selenium` and `webdriver-manager` packages are removed.  
CDP connection is via `BrowserSession(cdp_url="http://localhost:9222")`.

---

## New .env Variables Required

Add these to your `.env` file:

```bash
# Gemini (primary LLM — free at aistudio.google.com)
GOOGLE_API_KEY=AIza...

# Which LLM to use as primary ("gemini" or "groq")
PRIMARY_LLM=gemini
```

Your existing `GROQ_API_KEY` still works as the fallback LLM.

---

## Fresh Start Instructions

Because M5 changes the core automation stack (Playwright replaces Selenium,
new DB schema awareness, stale auth tokens), a fresh start is required.

### Method A: Using `setup_m5.sh` (recommended)

```bash
cd browser-automation-studio
chmod +x setup_m5.sh
./setup_m5.sh
```

The script:
1. Backs up `./data` to `./data_backup_<timestamp>`
2. Deletes `./data/app.db` (stale DB)
3. Adds `GOOGLE_API_KEY` and `PRIMARY_LLM` to `.env` if missing
4. Stops old container
5. Builds with `--no-cache` (essential for Playwright install)
6. Starts and waits for health

### Method B: Manual

```bash
# 1. Stop container
docker-compose down

# 2. Delete stale database
rm -f data/app.db data/app.db-shm data/app.db-wal

# 3. Add to .env
echo "GOOGLE_API_KEY=AIza..." >> .env
echo "PRIMARY_LLM=gemini" >> .env

# 4. Copy M5 files into project
cp -f /path/to/m5/backend/browser.py  backend/browser.py
cp -f /path/to/m5/backend/tasks.py    backend/tasks.py
cp -f /path/to/m5/backend/main.py     backend/main.py
cp -f /path/to/m5/requirements.txt    requirements.txt
cp -f /path/to/m5/Dockerfile          Dockerfile
cp -f /path/to/m5/frontend/src/components/ChatBox.jsx  frontend/src/components/ChatBox.jsx
cp -f /path/to/m5/frontend/src/api.js  frontend/src/api.js
cp -f /path/to/m5/frontend/src/App.jsx frontend/src/App.jsx

# 5. Rebuild (--no-cache is important for Playwright install)
docker-compose build --no-cache

# 6. Start
docker-compose up -d

# 7. Follow logs
docker-compose logs -f
```

---

## How to Apply M5 Files Manually (file-by-file)

If you prefer to copy files one by one rather than run the script:

```bash
# From inside the project directory, replace only these files:
backend/browser.py          ← NEW (full file)
backend/tasks.py            ← UPDATED
backend/main.py             ← UPDATED
requirements.txt            ← UPDATED
Dockerfile                  ← UPDATED
frontend/src/components/ChatBox.jsx   ← UPDATED
frontend/src/api.js         ← UPDATED
frontend/src/App.jsx        ← UPDATED
```

All other files stay as-is from M4.

---

## Testing M5 — Definition of Done Checklist

Test these in order. All must pass before moving to M6.

### ☐ 1. Container starts, health endpoint is green

```bash
curl http://localhost:7860/health
```

Expected (abbreviated):
```json
{
  "status": "ok",
  "version": "5.0.0",
  "module": "M5 — Browser Automation",
  "llm": {
    "primary": "gemini",
    "gemini_key": true,
    "groq_key": true
  },
  "components": {
    "fastapi": "ok",
    "database": "ok",
    "chromium": "ok",
    "chrome_devtools": "ok"
  }
}
```

### ☐ 2. Login and dashboard load correctly

- Open `http://localhost:7860`
- Login with your `APP_PASSWORD`
- Dashboard shows: Status bar (M5 ACTIVE), Mode selector, Chat panel, noVNC panel

### ☐ 3. noVNC shows live Chrome

- Right panel shows Chrome browser live
- You can click in it
- Chrome is on Google.com (or last visited page)

### ☐ 4. Simple task completes successfully

Type in chat:
```
Go to google.com and search for "browser automation python"
```

Expected sequence:
1. Your message appears as a right-side bubble (user)
2. A queued bubble appears below it (bot, left side): `Task queued → abc12345…`
3. A step bubble appears: `Step 1: navigating to google.com`
4. Step bubble updates in place: `Step 2: typing search query`
5. Step bubble disappears when done
6. Queued bubble updates to show: `✓ DONE` in green
7. Result shown as markdown-rendered text
8. Chrome in noVNC has navigated to Google search results

### ☐ 5. Groq rate-limit bar is visible

- A thin bar appears above the input field
- Shows "1/30 req/min" after submitting a task
- Bar is blue when low, yellow when >50%, red when >85%

### ☐ 6. /reset command works

Type in chat: `/reset`

Expected:
- Chat shows: "Resetting browser — closing stale tabs…"
- Followed by: "Browser reset complete. Closed X extra tab(s)."

### ☐ 7. /help shows all commands including /reset

Type: `/help`

Expected output includes: `/reset — reset Chrome (close stale tabs)`

### ☐ 8. /status shows Groq API usage

Type: `/status`

Expected: `Mode: IDLE | Ready for tasks\nGroq API: X/30 req/min used`

### ☐ 9. Session save works

1. In noVNC, manually log in to any website (e.g. GitHub)
2. In chat: type a task like `save cookies for github`
3. OR use Swagger at `/docs` → POST `/api/session/save` with `{"name": "github"}`
4. Check `data/cookies/github.json` exists

### ☐ 10. Session load works

1. Use Swagger → POST `/api/session/load/github`
2. In noVNC: navigate to github.com — should be logged in

### ☐ 11. Screenshot API works

```bash
TOKEN=$(curl -s -X POST http://localhost:7860/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"password":"YOUR_PASSWORD"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s -X POST http://localhost:7860/api/browser/screenshot \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
with open('/tmp/screenshot.png','wb') as f:
  f.write(base64.b64decode(d['screenshot']))
print('Screenshot saved to /tmp/screenshot.png')
"
```

### ☐ 12. Task failure is handled gracefully

Submit a deliberately broken task:
```
xyzzy invalid impossible task 123 !@#$
```

Expected:
- Chrome stays open (does not crash)
- Chat shows task FAILED with error message
- Error message is visible in red in the bubble

---

## UI Features in M5 (from ui_updates.md)

### User message stays as its own bubble

When you send a task, your original message appears on the **right side** permanently. The task status bubble appears separately on the left — it does not replace your message.

### Queued bubble updates in-place

The bot's "Task queued →" bubble updates its status suffix in-place:
- While running: shows `⚡ RUNNING` with a progress bar
- On success: updates to show `✓ DONE` in green
- On failure: updates to show `✗ FAILED` in red

No extra bubbles are added for status changes.

### Live step bubble

While a task runs, a separate orange step bubble shows what the agent is doing (`Step 3: clicking search button`). This updates in-place as each step happens. When the task finishes, this bubble disappears.

### Markdown rendering

Results from the AI that contain bold text, bullet lists, numbered lists, headings, inline code, code blocks, and links are rendered as proper HTML instead of showing raw `**text**` or `## heading`.

### Groq rate-limit bar

A thin bar above the input shows:
- Request count: `X/30 req/min`
- Color: blue → yellow (>50%) → red (>85%)
- When 100% reached: input and send button are disabled with a countdown timer
- Freeze state is saved to sessionStorage — survives page reload

### /reset command

Type `/reset` in chat to close all stale Chrome tabs and navigate to `about:blank`. Useful when Chrome has many open tabs from previous tasks.

---

## Troubleshooting

### "No LLM available" error

Check your `.env`:
```bash
grep -E "GOOGLE_API_KEY|GROQ_API_KEY|PRIMARY_LLM" .env
```

At least one key must be non-empty. If both are empty, tasks will fail immediately.

### "CDP unreachable" or "No Chrome page found"

Chrome hasn't started yet. Check:
```bash
docker-compose logs chromium
curl http://localhost:9222/json
```

CDP should return a JSON array with a page entry.

### Playwright can't connect to Chrome

Chrome must be started with `--remote-debugging-port=9222`. Check `supervisord.conf` — the `[program:chromium]` section must include this flag (it does in M2+).

### Task submits but nothing happens in Chrome

Check the FastAPI logs:
```bash
docker-compose logs fastapi | tail -50
```

Look for "Agent starting" or import errors.

### "ImportError: No module named 'langchain_google_genai'"

The Docker image wasn't rebuilt with the new `requirements.txt`. Run:
```bash
docker-compose build --no-cache
docker-compose up -d
```

### Playwright install failed in Docker

Check Docker build logs:
```bash
docker-compose build --no-cache 2>&1 | grep -A5 "playwright"
```

The Dockerfile runs `python3 -m playwright install chromium --with-deps`.
This requires internet access during the build.

---

## Architecture Summary (M5)

```
User types task
      ↓
ChatBox.jsx → submitTask() → POST /api/task/submit
      ↓
tasks.py: create_task() + asyncio.create_task(run_task_async())
      ↓
run_task_async() calls browser.run_task()
      ↓
browser.py:
  _build_llms() → Gemini (primary) + Groq (fallback)
  BrowserSession(cdp_url="http://localhost:9222")
  Agent(task, llm, browser, register_new_step_callback=on_step)
  agent.run()
      ↓
on_step callback fires each step:
  ws_manager.broadcast({step, action, progress, step_bubble:true})
      ↓
ChatBox.jsx receives WS event:
  step_bubble=true → update step bubble in-place
  COMPLETED → update queued bubble suffix, remove step bubble
      ↓
noVNC shows Chrome performing the task live
```

---

*M5 complete. Next: M6 — Telegram Bot wired to real browser automation.*
