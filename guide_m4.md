# Browser Automation Studio — M4 Guide
**React Frontend — Cyberpunk Terminal UI**

## What M4 Adds

| File | What's New |
|---|---|
| `frontend/src/App.jsx` | Login page + dashboard with routing, WebSocket client |
| `frontend/src/api.js` | All fetch calls to FastAPI (auth, tasks, mode, sessions) |
| `frontend/src/components/StatusBar.jsx` | Top bar: mode badge, health, WS status, clock, logout |
| `frontend/src/components/ModeSelector.jsx` | IDLE / MANUAL / AUTONOMOUS toggle buttons |
| `frontend/src/components/ChatBox.jsx` | Chat UI: submit tasks, see results in real time |
| `frontend/src/components/NoVNCViewer.jsx` | noVNC iframe: live Chrome, clickable and typeable |

## Design Aesthetic

Cyberpunk terminal — dark background (#000408), phosphor teal (#00d4ff),
phosphor green (#00ff88), Share Tech Mono font, scanline overlays, hex glyphs,
animated glitch title, border glow pulses, smooth transitions.

## Step 1 — Apply M4

```bash
bash setup_m4.sh
```

## Step 2 — Rebuild (REQUIRED for React)

```bash
docker compose down
docker compose build
docker compose up
```

React must compile into static files that FastAPI serves. This takes 3–5 min.

## Step 3 — Open the App

Visit: **http://localhost:7860**

You should see the cyberpunk login card.

## Step 4 — Verify All DoD Items

### DoD 1: Login page at root URL
```
http://localhost:7860
→ Cyberpunk login card with hexagon logo
```

### DoD 2: Login works
Enter your APP_PASSWORD → click "INITIALIZE SESSION →"
→ Dashboard loads with status bar and mode selector

### DoD 3 & 4: noVNC shows Chrome and is clickable
Right panel (60%) shows Chrome live. Click inside to control Chrome.

### DoD 5: WebSocket live
Status bar shows "WS LIVE" in blue within a few seconds of login.

### DoD 6: Mode switch
Click MANUAL → badge turns orange, API called.
Click AUTO → badge turns blue. Click IDLE → green.

### DoD 7: Chat submits tasks
Type anything → Enter → bot shows task status updating in real time
(PENDING → RUNNING → COMPLETED via WebSocket).

### DoD 8: React served by FastAPI
```bash
curl -s http://localhost:7860/ | grep "Browser Automation"
# Expected: Browser Automation Studio
```

## Chat Commands

- `/help` — show available commands
- `/clear` — clear chat history
- `/status` — show current mode
- Any other text → submitted as automation task

## Troubleshooting

### White screen after login
Open browser DevTools → Console → look for errors.
Most likely React build is missing:
```bash
docker compose exec automation-studio ls /app/frontend/build/
```

### noVNC shows "CONNECTING..." forever
The iframe connects WebSocket back to port 6080.
Make sure docker-compose.yml has: `"6080:6080"` in ports.

### Mode button shows no response
Token expired — logout and login again.

## M4 DoD Checklist

- [ ] http://localhost:7860 shows login page
- [ ] Login works → dashboard loads
- [ ] noVNC right panel shows Chrome
- [ ] Clicking noVNC controls Chrome
- [ ] WS LIVE shows in status bar
- [ ] Mode buttons work
- [ ] Chat submits tasks with real-time status
- [ ] React served by FastAPI at root

## Git Commit

```bash
git add .
git commit -m "[M4] react-frontend: COMPLETE — all DoD items ticked"
```

## What M5 Adds

M5 wires real browser automation: Selenium + Browser Use + Groq AI.
Tasks will actually navigate websites instead of showing "[M3 STUB]".
