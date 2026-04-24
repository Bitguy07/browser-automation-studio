# ============================================================
# Browser Automation Studio — backend/main.py
# M3: Full FastAPI backend — all endpoints
# ============================================================

import asyncio
import base64
import json
import os
import socket
import subprocess
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

from backend.auth import (
    verify_password, create_access_token,
    verify_token, get_raw_token, blacklist_token
)
from backend.models import (
    init_db, get_db, SessionLocal,
    TaskStatus, task_to_schema, log_event,
    LoginRequest, LoginResponse, LogoutResponse,
    TaskSubmitRequest, TaskResponse, TaskListResponse,
    ModeResponse, ModeSwitchRequest,
    SessionSaveRequest, SessionListResponse, SessionInfo,
    UserModel,
)
from backend.tasks import (
    ws_manager, ws_heartbeat,
    get_mode, set_mode,
    get_task, get_all_tasks, cancel_task, submit_task,
    _ws_event,
)

load_dotenv()

COOKIES_DIR = os.getenv("COOKIES_DIR", "/data/cookies")
DATA_DIR    = os.getenv("DATA_DIR", "/data")


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("=" * 60)
    print("  Browser Automation Studio — M3 Starting")
    print(f"  Port: {os.getenv('APP_PORT', '7860')}")
    print(f"  DB  : {os.getenv('DB_PATH', '/data/app.db')}")
    print("=" * 60)
    for path in [DATA_DIR, COOKIES_DIR, "/data/outputs"]:
        os.makedirs(path, exist_ok=True)
    init_db()
    asyncio.create_task(ws_heartbeat())
    db = SessionLocal()
    log_event(db, "INFO", "system", "Browser Automation Studio M3 started")
    db.close()
    yield
    db = SessionLocal()
    log_event(db, "INFO", "system", "Shutting down")
    db.close()


app = FastAPI(
    title="Browser Automation Studio",
    description=(
        "Self-hosted browser automation platform with AI.\n\n"
        "**Auth:** POST /api/auth/login → get token → click Authorize → enter `Bearer <token>`"
    ),
    version="3.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:7860",
                   "https://*.hf.space", "*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def is_process_running(name: str) -> bool:
    try:
        r = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
        return r.returncode == 0
    except Exception:
        return False


def is_port_open(port: int) -> bool:
    try:
        with socket.create_connection(("localhost", port), timeout=1):
            return True
    except (ConnectionRefusedError, OSError):
        return False


def check_db_ok() -> bool:
    try:
        import sqlalchemy
        db = SessionLocal()
        db.execute(sqlalchemy.text("SELECT 1"))
        db.close()
        return True
    except Exception:
        return False


def take_screenshot_scrot() -> str:
    tmppath = f"/tmp/scrot_{os.getpid()}.png"
    if os.path.exists(tmppath):
        os.unlink(tmppath)
    try:
        env = {**os.environ, "DISPLAY": ":99"}
        r = subprocess.run(["scrot", tmppath], capture_output=True, text=True, timeout=10, env=env)
        if r.returncode != 0:
            raise RuntimeError(f"scrot: {r.stderr.strip()}")
        if not os.path.exists(tmppath) or os.path.getsize(tmppath) == 0:
            raise RuntimeError("scrot produced empty file")
        with open(tmppath, "rb") as f:
            return base64.b64encode(f.read()).decode("utf-8")
    finally:
        if os.path.exists(tmppath):
            os.unlink(tmppath)


def take_screenshot_cdp() -> str:
    import urllib.request
    import websocket as ws_client
    try:
        with urllib.request.urlopen("http://localhost:9222/json", timeout=3) as resp:
            pages = json.loads(resp.read())
    except Exception as e:
        raise RuntimeError(f"CDP unreachable: {e}")
    page = next((p for p in pages if p.get("type") == "page"), None)
    if not page:
        raise RuntimeError("No Chrome page")
    ws_url = page.get("webSocketDebuggerUrl")
    if not ws_url:
        raise RuntimeError("No WS debugger URL")
    ws = ws_client.create_connection(ws_url, timeout=5)
    try:
        ws.send(json.dumps({"id": 1, "method": "Page.captureScreenshot",
                            "params": {"format": "png", "quality": 80}}))
        r = json.loads(ws.recv())
        if "result" in r and "data" in r["result"]:
            return r["result"]["data"]
        raise RuntimeError(f"CDP no data: {r}")
    finally:
        ws.close()


# ════════════════════════════════════════════════════
# ROUTES
# ════════════════════════════════════════════════════

@app.post("/api/auth/login", response_model=LoginResponse, tags=["Auth"])
async def login(request: LoginRequest, db=Depends(get_db)):
    """Login with APP_PASSWORD. Returns JWT Bearer token (24h)."""
    if not verify_password(request.password):
        raise HTTPException(status_code=401, detail="Incorrect password")
    token = create_access_token({"sub": "admin", "role": "admin"})
    user = db.query(UserModel).filter_by(username="admin").first()
    if user:
        user.last_login = datetime.now(timezone.utc)
        user.login_count = (user.login_count or 0) + 1
        db.commit()
    log_event(db, "INFO", "auth", "Admin login")
    return LoginResponse(access_token=token)


@app.post("/api/auth/logout", response_model=LogoutResponse, tags=["Auth"])
async def logout(
    token: str = Depends(get_raw_token),
    _user=Depends(verify_token),
    db=Depends(get_db),
):
    """Invalidate current Bearer token."""
    blacklist_token(token)
    log_event(db, "INFO", "auth", "Admin logout")
    return LogoutResponse()


@app.get("/health", tags=["System"])
async def health_check():
    """System health — no auth required."""
    return JSONResponse({
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": "3.0.0",
        "module": "M3 — Full FastAPI Backend",
        "mode": get_mode(),
        "components": {
            "fastapi":        "ok",
            "database":       "ok" if check_db_ok() else "error",
            "xvfb":           "ok" if is_process_running("Xvfb") else "not_running",
            "chromium":       "ok" if is_process_running("chrome") else "not_running",
            "x11vnc":         "ok" if is_process_running("x11vnc") else "not_running",
            "websockify":     "ok" if is_port_open(6080) else "not_ready",
            "chrome_devtools":"ok" if is_port_open(9222) else "not_ready",
        },
        "websocket_clients": ws_manager.connection_count(),
    })


@app.get("/api/mode", response_model=ModeResponse, tags=["Mode"])
async def get_current_mode(_user=Depends(verify_token)):
    mode = get_mode()
    return ModeResponse(mode=mode, message=f"Current mode is {mode}")


@app.post("/api/mode/switch", response_model=ModeResponse, tags=["Mode"])
async def switch_mode(request: ModeSwitchRequest, _user=Depends(verify_token), db=Depends(get_db)):
    try:
        new_mode = set_mode(request.mode)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    log_event(db, "INFO", "system", f"Mode → {new_mode}")
    await ws_manager.broadcast(_ws_event("mode_change", message=f"Mode → {new_mode}",
                                         data={"mode": new_mode}))
    return ModeResponse(mode=new_mode, message=f"Mode switched to {new_mode}")


@app.post("/api/task/submit", response_model=TaskResponse, tags=["Tasks"])
async def submit_new_task(request: TaskSubmitRequest, _user=Depends(verify_token), db=Depends(get_db)):
    """Submit automation task. Runs async — poll status or watch WebSocket."""
    task = submit_task(db, request.objective, request.mode)
    log_event(db, "INFO", "tasks", f"Task submitted: '{request.objective[:60]}'", task_id=task.id)
    return task_to_schema(task)


@app.get("/api/task/list", response_model=TaskListResponse, tags=["Tasks"])
async def list_tasks(_user=Depends(verify_token), db=Depends(get_db)):
    tasks = get_all_tasks(db)
    return TaskListResponse(tasks=[task_to_schema(t) for t in tasks], total=len(tasks))


@app.get("/api/task/{task_id}/status", response_model=TaskResponse, tags=["Tasks"])
async def get_task_status(task_id: str, _user=Depends(verify_token), db=Depends(get_db)):
    task = get_task(db, task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    return task_to_schema(task)


@app.delete("/api/task/{task_id}", tags=["Tasks"])
async def cancel_task_endpoint(task_id: str, _user=Depends(verify_token), db=Depends(get_db)):
    task = cancel_task(db, task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    await ws_manager.broadcast(_ws_event("task_update", task_id, "CANCELLED",
                                         f"Task {task_id[:8]} cancelled"))
    return JSONResponse({"message": f"Task {task_id} cancelled", "status": task.status})


@app.post("/api/browser/screenshot", tags=["Browser"])
@app.get("/api/browser/screenshot", tags=["Browser"])
async def browser_screenshot(_user=Depends(verify_token)):
    """Capture Chrome screen as base64 PNG. CDP first, scrot fallback."""
    try:
        s = take_screenshot_cdp()
        method = "chrome_devtools_protocol"
    except Exception as e1:
        try:
            s = take_screenshot_scrot()
            method = "scrot_virtual_display"
        except Exception as e2:
            raise HTTPException(status_code=500, detail={
                "error": "Both methods failed",
                "cdp_error": str(e1), "scrot_error": str(e2),
            })
    return JSONResponse({
        "status": "ok", "screenshot": s, "format": "png",
        "encoding": "base64", "method": method,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "img_src": "data:image/png;base64," + s,
    })


@app.post("/api/session/save", tags=["Sessions"])
async def save_session(request: SessionSaveRequest, _user=Depends(verify_token), db=Depends(get_db)):
    """Save Chrome cookies to named session file. (Stub — real cookies in M5)"""
    os.makedirs(COOKIES_DIR, exist_ok=True)
    safe = "".join(c for c in request.name if c.isalnum() or c in "-_")
    if not safe:
        raise HTTPException(status_code=400, detail="Invalid session name")
    fpath = os.path.join(COOKIES_DIR, f"{safe}.json")
    payload = {"session_name": safe, "cookies": [],
               "saved_at": datetime.now(timezone.utc).isoformat(),
               "note": "Real cookies wired in M5."}
    with open(fpath, "w") as f:
        json.dump(payload, f, indent=2)
    log_event(db, "INFO", "sessions", f"Session saved: {safe}")
    return JSONResponse({"message": f"Session '{safe}' saved", "file": fpath,
                         "size_bytes": os.path.getsize(fpath)})


@app.get("/api/session/list", response_model=SessionListResponse, tags=["Sessions"])
async def list_sessions(_user=Depends(verify_token)):
    os.makedirs(COOKIES_DIR, exist_ok=True)
    sessions = []
    for fname in sorted(os.listdir(COOKIES_DIR)):
        if fname.endswith(".json"):
            fpath = os.path.join(COOKIES_DIR, fname)
            stat = os.stat(fpath)
            sessions.append(SessionInfo(
                name=fname[:-5], file_path=fpath, size_bytes=stat.st_size,
                created_at=datetime.fromtimestamp(stat.st_ctime, tz=timezone.utc).isoformat(),
            ))
    return SessionListResponse(sessions=sessions, total=len(sessions))


@app.post("/api/session/load/{name}", tags=["Sessions"])
async def load_session(name: str, _user=Depends(verify_token), db=Depends(get_db)):
    """Load saved session into Chrome. (Stub — real injection in M5)"""
    safe = "".join(c for c in name if c.isalnum() or c in "-_")
    fpath = os.path.join(COOKIES_DIR, f"{safe}.json")
    if not os.path.exists(fpath):
        raise HTTPException(status_code=404, detail=f"Session '{safe}' not found")
    with open(fpath) as f:
        data = json.load(f)
    log_event(db, "INFO", "sessions", f"Session loaded: {safe}")
    return JSONResponse({"message": f"Session '{safe}' loaded",
                         "cookies_count": len(data.get("cookies", [])),
                         "note": "Real injection in M5."})


@app.get("/api/vnc/status", tags=["Browser"])
async def vnc_status(_user=Depends(verify_token)):
    return JSONResponse({
        "chain": {
            "1_xvfb":      "running" if is_process_running("Xvfb") else "stopped",
            "2_chromium":  "running" if is_process_running("chrome") else "stopped",
            "3_x11vnc":    "running" if is_process_running("x11vnc") else "stopped",
            "4_websockify":"running" if is_process_running("websockify") else "stopped",
        },
        "ports": {
            "vnc_raw_5900":        "open" if is_port_open(5900) else "closed",
            "novnc_ws_6080":       "open" if is_port_open(6080) else "closed",
            "chrome_devtools_9222":"open" if is_port_open(9222) else "closed",
        },
        "access": {
            "novnc_direct":    "http://localhost:6080/vnc.html",
            "screenshot_api":  "http://localhost:7860/api/browser/screenshot",
        },
    })


@app.websocket("/api/ws/monitor")
async def websocket_monitor(websocket: WebSocket):
    """
    Real-time WebSocket event stream.
    Connect: ws://localhost:7860/api/ws/monitor?token=<jwt>
    Events: task_update, mode_change, ping, connected
    """
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4001, reason="Missing token")
        return
    try:
        from backend.auth import decode_token
        decode_token(token)
    except HTTPException:
        await websocket.close(code=4001, reason="Invalid token")
        return

    await ws_manager.connect(websocket)
    await ws_manager.send_to(websocket, _ws_event(
        "connected", message="Connected to monitor",
        data={"mode": get_mode(), "clients": ws_manager.connection_count(), "version": "3.0.0"},
    ))

    try:
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await ws_manager.send_to(websocket, _ws_event(
                    "pong", message="pong", data={"mode": get_mode()}
                ))
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)


@app.get("/", tags=["System"])
async def root():
    if os.path.exists("/app/frontend/build/index.html"):
        return FileResponse("/app/frontend/build/index.html")
    return JSONResponse({
        "message": "Browser Automation Studio — M3",
        "version": "3.0.0", "docs": "/docs", "health": "/health",
        "auth": "POST /api/auth/login",
    })


if os.path.exists("/opt/novnc"):
    app.mount("/vnc", StaticFiles(directory="/opt/novnc"), name="novnc")

if os.path.exists("/app/frontend/build"):
    app.mount("/static", StaticFiles(directory="/app/frontend/build/static"), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0",
                port=int(os.getenv("APP_PORT", "7860")), reload=True)
