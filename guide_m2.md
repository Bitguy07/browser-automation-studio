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
