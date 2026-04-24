# Browser Automation Studio — M3 Guide
**Full FastAPI Backend**

## What M3 Adds

| File | What's New |
|---|---|
| `backend/auth.py` | JWT login, logout, token blacklist, verify_token dependency |
| `backend/models.py` | SQLAlchemy tables (tasks, recordings, system_logs, users) + Pydantic schemas |
| `backend/tasks.py` | In-memory task queue, WebSocket broadcast manager, heartbeat |
| `backend/main.py` | All 14 endpoints + WebSocket monitor |

## Step 1 — Apply M3

```bash
bash setup_m3.sh
```

No rebuild needed — backend/ is volume-mounted.

## Step 2 — Restart Container

```bash
docker compose down
docker compose up
```

## Step 3 — Verify All DoD Items

### DoD 1: Login returns JWT token
```bash
curl -s -X POST http://localhost:7860/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"password": "YOUR_APP_PASSWORD"}' | jq '{access_token: .access_token[:30], token_type}'
# Expected: access_token starts with "ey...", token_type: "bearer"
```

Save the token:
```bash
TOKEN=$(curl -s -X POST http://localhost:7860/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"password": "YOUR_APP_PASSWORD"}' | jq -r '.access_token')
echo "Token saved: ${TOKEN:0:30}..."
```

### DoD 2: Protected endpoints return 401 without token
```bash
curl -s http://localhost:7860/api/mode | jq '.detail'
# Expected: "Authorization header missing..."
```

### DoD 3: SQLite creates all 4 tables
```bash
docker compose exec automation-studio \
  python3 -c "
from backend.models import init_db, SessionLocal
import sqlalchemy
init_db()
db = SessionLocal()
tables = db.execute(sqlalchemy.text(\"SELECT name FROM sqlite_master WHERE type='table'\")).fetchall()
print([t[0] for t in tables])
"
# Expected: ['tasks', 'recordings', 'system_logs', 'users']
```

### DoD 4: Task submit → status poll works
```bash
# Submit a task
TASK=$(curl -s -X POST http://localhost:7860/api/task/submit \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"objective": "Test task for M3 DoD", "mode": "auto"}' | jq '.')
echo $TASK | jq '{id, status, objective}'

# Get the task ID
TASK_ID=$(echo $TASK | jq -r '.id')

# Poll status (wait a few seconds first)
sleep 4
curl -s http://localhost:7860/api/task/$TASK_ID/status \
  -H "Authorization: Bearer $TOKEN" | jq '{status, progress, result}'
# Expected: status: "COMPLETED", progress: 100
```

### DoD 5: WebSocket connects and receives events
```bash
# Install wscat if not present
npm install -g wscat 2>/dev/null

# Connect to WebSocket (use your actual token)
wscat -c "ws://localhost:7860/api/ws/monitor?token=$TOKEN"
# Expected: {"type": "connected", "message": "Connected to monitor", ...}
# Send: ping
# Expected: {"type": "pong", ...}
```

### DoD 6: Mode switches correctly
```bash
curl -s -X POST http://localhost:7860/api/mode/switch \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mode": "MANUAL"}' | jq '{mode, message}'
# Expected: mode: "MANUAL"

curl -s http://localhost:7860/api/mode \
  -H "Authorization: Bearer $TOKEN" | jq '.mode'
# Expected: "MANUAL"

# Switch back
curl -s -X POST http://localhost:7860/api/mode/switch \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mode": "IDLE"}' | jq '.mode'
```

### DoD 7: All endpoints in Swagger
Open: http://localhost:7860/docs
You should see all endpoints grouped by tag:
- Auth: login, logout
- System: health, root
- Mode: get mode, switch mode
- Tasks: submit, list, status, cancel
- Browser: screenshot, vnc status
- Sessions: save, list, load

### DoD 8: Session save/load works
```bash
# Save a session
curl -s -X POST http://localhost:7860/api/session/save \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "test-session"}' | jq '{message, file}'

# List sessions
curl -s http://localhost:7860/api/session/list \
  -H "Authorization: Bearer $TOKEN" | jq '{total, sessions}'

# Load session
curl -s -X POST http://localhost:7860/api/session/load/test-session \
  -H "Authorization: Bearer $TOKEN" | jq '{message}'
```

## Quick Full Test Script

```bash
# Set your password
PASS="your_app_password_here"

# Login
TOKEN=$(curl -s -X POST http://localhost:7860/api/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"password\": \"$PASS\"}" | jq -r '.access_token')

echo "=== Health ==="
curl -s http://localhost:7860/health | jq '{status, version, mode}'

echo "=== Mode ==="
curl -s http://localhost:7860/api/mode -H "Authorization: Bearer $TOKEN" | jq '.mode'

echo "=== Submit Task ==="
curl -s -X POST http://localhost:7860/api/task/submit \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"objective": "M3 full test task", "mode": "auto"}' | jq '{id, status}'

echo "=== Task List ==="
sleep 5
curl -s http://localhost:7860/api/task/list \
  -H "Authorization: Bearer $TOKEN" | jq '{total, first_task_status: .tasks[0].status}'

echo "=== All done! ==="
```

## Troubleshooting

### ImportError on startup
```bash
docker compose exec automation-studio cat /var/log/supervisor/fastapi.err | tail -20
```
Most likely a missing import. The backend/ volume mount means you see errors immediately without rebuild.

### 401 on all requests even with token
Check your token is not expired (24h) and APP_PASSWORD in .env matches what you used to login.

### Database not created
```bash
docker compose exec automation-studio ls -la /data/
# Should show app.db
```
If missing, check DATA_DIR in .env is set to /data.

### WebSocket connection refused
Make sure you pass token as query param: `?token=<jwt>` not as header.

## M3 DoD Checklist

- [ ] POST /api/auth/login returns JWT
- [ ] Protected endpoints return 401 without token
- [ ] SQLite creates all 4 tables on startup
- [ ] Task submit → poll → COMPLETED works
- [ ] WebSocket connects + receives events
- [ ] Mode switches IDLE/MANUAL/AUTONOMOUS
- [ ] All endpoints visible in /docs Swagger
- [ ] Session save/load works

## Git Commit

```bash
git add .
git commit -m "[M3] fastapi-backend: COMPLETE — all DoD items ticked"
```

## What M4 Adds

M4 builds the React frontend: login page, dashboard with chat panel,
embedded noVNC viewer, mode switcher, real-time status bar via WebSocket.
