# ============================================================
# Browser Automation Studio — backend/main.py
# M5: Real browser automation — session/screenshot/reset wired
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

from backend.telegram_bot import init_bot

import websockets
import asyncio

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
DATA_DIR    = os.getenv("DATA_DIR",    "/data")

# Telegram Bot disabled per user request
ptb_app = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("=" * 60)
    print("  Browser Automation Studio — M5 Starting")
    print(f"  Port  : {os.getenv('APP_PORT', '7860')}")
    print(f"  DB    : {os.getenv('DB_PATH', '/data/app.db')}")
    primary = os.getenv("PRIMARY_LLM", "gemini")
    gemini_ok = bool(os.getenv("GOOGLE_API_KEY"))
    groq_ok   = bool(os.getenv("GROQ_API_KEY"))
    print(f"  LLM   : primary={primary}  gemini={'✓' if gemini_ok else '✗'}  groq={'✓' if groq_ok else '✗'}")
    print("=" * 60)

    for path in [DATA_DIR, COOKIES_DIR, "/data/outputs", "/data/downloads"]:
        os.makedirs(path, exist_ok=True)

    init_db()
    asyncio.create_task(ws_heartbeat())

    # Start Telegram Bot in background so it never blocks FastAPI startup
    if ptb_app:
        async def start_telegram():
            # HF Free Tier has slow outbound networking during first ~60s of boot.
            # Retry initialize() multiple times before giving up.
            for attempt in range(1, 11):
                try:
                    print(f"[Telegram] Initialization attempt {attempt}/10...", flush=True)
                    await ptb_app.initialize()
                    await ptb_app.start()
                    print("[Telegram] Deleting any existing webhook...", flush=True)
                    await ptb_app.bot.delete_webhook(drop_pending_updates=True)
                    print("[Telegram] Starting polling...", flush=True)
                    await ptb_app.updater.start_polling(drop_pending_updates=True)
                    print("[Telegram] ✓ Bot is running and polling for messages!", flush=True)
                    return  # success — exit the retry loop
                except Exception as e:
                    print(f"[Telegram] Attempt {attempt} failed: {e}", flush=True)
                    # Clean up partial init before retrying
                    try:
                        await ptb_app.shutdown()
                    except Exception:
                        pass
                    if attempt < 10:
                        wait = min(15 * attempt, 60)
                        print(f"[Telegram] Retrying in {wait}s...", flush=True)
                        await asyncio.sleep(wait)
            print("[Telegram] ✗ All 10 attempts failed. Bot will not run.", flush=True)

        asyncio.create_task(start_telegram())

    db = SessionLocal()
    log_event(db, "INFO", "system", "Browser Automation Studio M5 started")
    db.close()
    yield
    db = SessionLocal()
    log_event(db, "INFO", "system", "Shutting down")
    db.close()

    if ptb_app:
        print("[Telegram] Shutting down bot...")
        try:
            await ptb_app.updater.stop()
            await ptb_app.stop()
            await ptb_app.shutdown()
        except Exception:
            pass


app = FastAPI(
    title="Browser Automation Studio",
    description=(
        "Self-hosted browser automation platform with AI.\n\n"
        "**Auth:** POST /api/auth/login → get token → click Authorize → enter `Bearer <token>`"
    ),
    version="5.0.0",
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





# ── System helpers ────────────────────────────────────────────
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


# ════════════════════════════════════════════════════════════════
# ROUTES
# ════════════════════════════════════════════════════════════════

@app.post("/api/auth/login", response_model=LoginResponse, tags=["Auth"])
async def login(request: LoginRequest, db=Depends(get_db)):
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
    blacklist_token(token)
    log_event(db, "INFO", "auth", "Admin logout")
    return LogoutResponse()


@app.get("/health", tags=["System"])
async def health_check():
    return JSONResponse({
        "status":    "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version":   "5.0.0",
        "module":    "M5 — Browser Automation",
        "mode":      get_mode(),
        "llm": {
            "primary":    os.getenv("PRIMARY_LLM", "gemini"),
            "gemini_key": bool(os.getenv("GOOGLE_API_KEY")),
            "groq_key":   bool(os.getenv("GROQ_API_KEY")),
        },
        "components": {
            "fastapi":         "ok",
            "database":        "ok" if check_db_ok() else "error",
            "xvfb":            "ok" if is_process_running("Xvfb") else "not_running",
            "chromium":        "ok" if is_process_running("chrome") else "not_running",
            "x11vnc":          "ok" if is_process_running("x11vnc") else "not_running",
            "websockify":      "ok" if is_port_open(6080) else "not_ready",
            "chrome_devtools": "ok" if is_port_open(9222) else "not_ready",
        },
        "websocket_clients": ws_manager.connection_count(),
    })


@app.get("/api/mode", response_model=ModeResponse, tags=["Mode"])
async def get_current_mode(_user=Depends(verify_token)):
    mode = get_mode()
    return ModeResponse(mode=mode, message=f"Current mode is {mode}")


@app.post("/api/mode/switch", response_model=ModeResponse, tags=["Mode"])
async def switch_mode(request: ModeSwitchRequest,
                      _user=Depends(verify_token), db=Depends(get_db)):
    try:
        new_mode = set_mode(request.mode)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    log_event(db, "INFO", "system", f"Mode → {new_mode}")
    await ws_manager.broadcast(_ws_event(
        "mode_change", message=f"Mode → {new_mode}", data={"mode": new_mode}
    ))
    return ModeResponse(mode=new_mode, message=f"Mode switched to {new_mode}")


@app.post("/api/task/submit", response_model=TaskResponse, tags=["Tasks"])
async def submit_new_task(request: TaskSubmitRequest,
                          _user=Depends(verify_token), db=Depends(get_db)):
    task = submit_task(db, request.objective, request.mode)
    log_event(db, "INFO", "tasks",
              f"Task submitted: '{request.objective[:60]}'", task_id=task.id)
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
async def cancel_task_endpoint(task_id: str,
                                _user=Depends(verify_token), db=Depends(get_db)):
    task = cancel_task(db, task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    await ws_manager.broadcast(_ws_event(
        "task_update", task_id, "CANCELLED", f"Task {task_id[:8]} cancelled"
    ))
    return JSONResponse({"message": f"Task {task_id} cancelled", "status": task.status})


# ── Browser / Screenshot ──────────────────────────────────────

@app.post("/api/browser/screenshot", tags=["Browser"])
@app.get("/api/browser/screenshot", tags=["Browser"])
async def browser_screenshot(_user=Depends(verify_token)):
    """Capture Chrome screen as base64 PNG (CDP first, scrot fallback)."""
    from backend.browser import take_screenshot
    try:
        s = await take_screenshot()
        return JSONResponse({
            "status": "ok", "screenshot": s,
            "format": "png", "encoding": "base64",
            "img_src": "data:image/png;base64," + s,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/browser/reset", tags=["Browser"])
async def browser_reset(_user=Depends(verify_token), db=Depends(get_db)):
    """
    /reset command — close stale Chrome tabs, navigate to about:blank.
    Does NOT restart Docker or supervisord.
    """
    from backend.browser import reset_browser
    try:
        msg = await reset_browser()
        log_event(db, "INFO", "browser", msg)
        await ws_manager.broadcast(_ws_event(
            "browser_reset", message=msg, data={"reset": True}
        ))
        return JSONResponse({"message": msg, "status": "ok"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Session management (real, using Playwright storage_state) ─

@app.post("/api/session/save", tags=["Sessions"])
async def save_session(request: SessionSaveRequest,
                       _user=Depends(verify_token), db=Depends(get_db)):
    """Save Chrome cookies/session to named file via Playwright storage_state."""
    from backend.browser import save_session as browser_save_session
    os.makedirs(COOKIES_DIR, exist_ok=True)
    safe = "".join(c for c in request.name if c.isalnum() or c in "-_")
    if not safe:
        raise HTTPException(status_code=400, detail="Invalid session name")
    try:
        fpath = await browser_save_session(safe)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session save failed: {e}")
    log_event(db, "INFO", "sessions", f"Session saved: {safe}")
    return JSONResponse({
        "message": f"Session '{safe}' saved",
        "file": fpath,
        "size_bytes": os.path.getsize(fpath),
    })


@app.get("/api/session/list", response_model=SessionListResponse, tags=["Sessions"])
async def list_sessions(_user=Depends(verify_token)):
    os.makedirs(COOKIES_DIR, exist_ok=True)
    sessions = []
    for fname in sorted(os.listdir(COOKIES_DIR)):
        if fname.endswith(".json"):
            fpath = os.path.join(COOKIES_DIR, fname)
            stat  = os.stat(fpath)
            sessions.append(SessionInfo(
                name=fname[:-5], file_path=fpath, size_bytes=stat.st_size,
                created_at=datetime.fromtimestamp(
                    stat.st_ctime, tz=timezone.utc).isoformat(),
            ))
    return SessionListResponse(sessions=sessions, total=len(sessions))


@app.post("/api/session/load/{name}", tags=["Sessions"])
async def load_session(name: str, _user=Depends(verify_token), db=Depends(get_db)):
    """Load saved session into Chrome (injects cookies via Playwright)."""
    from backend.browser import load_session as browser_load_session
    safe  = "".join(c for c in name if c.isalnum() or c in "-_")
    fpath = os.path.join(COOKIES_DIR, f"{safe}.json")
    if not os.path.exists(fpath):
        raise HTTPException(status_code=404, detail=f"Session '{safe}' not found")
    try:
        count = await browser_load_session(safe)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session load failed: {e}")
    log_event(db, "INFO", "sessions", f"Session loaded: {safe}")
    return JSONResponse({
        "message": f"Session '{safe}' loaded",
        "cookies_count": count,
    })


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
            "novnc_direct":   "http://localhost:6080/vnc.html",
            "screenshot_api": "http://localhost:7860/api/browser/screenshot",
        },
    })


# ── WebSocket monitor ─────────────────────────────────────────

@app.websocket("/api/ws/monitor")
async def websocket_monitor(websocket: WebSocket):
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
        data={"mode": get_mode(),
              "clients": ws_manager.connection_count(),
              "version": "5.0.0"},
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


# ── Static files / SPA ────────────────────────────────────────

if os.path.exists("/opt/novnc"):
    app.mount("/vnc", StaticFiles(directory="/opt/novnc", html=True), name="novnc")

@app.websocket("/websockify")
async def vnc_proxy(websocket: WebSocket):
    await websocket.accept()
    try:
        # Connect to internal websockify
        async with websockets.connect("ws://127.0.0.1:6080", subprotocols=["binary"]) as backend_ws:
            async def forward():
                try:
                    while True:
                        data = await backend_ws.recv()
                        if isinstance(data, bytes):
                            await websocket.send_bytes(data)
                        else:
                            await websocket.send_text(data)
                except Exception:
                    pass

            async def reverse():
                try:
                    while True:
                        msg = await websocket.receive()
                        if "bytes" in msg and msg["bytes"]:
                            await backend_ws.send(msg["bytes"])
                        elif "text" in msg and msg["text"]:
                            await backend_ws.send(msg["text"])
                        elif msg["type"] == "websocket.disconnect":
                            break
                except Exception:
                    pass

            await asyncio.gather(forward(), reverse())
    except Exception as e:
        print(f"[VNC Proxy] Error: {e}")
    finally:
        try:
            await websocket.close()
        except Exception:
            pass

if os.path.isdir("/app/frontend/build"):
    static_dir = "/app/frontend/build/static"
    if os.path.isdir(static_dir):
        app.mount("/static", StaticFiles(directory=static_dir), name="static")
    
    @app.get("/{full_path:path}", tags=["System"])
    async def serve_spa(full_path: str):
        # Serve explicit file if it exists (e.g., manifest.json, favicon.ico)
        file_path = os.path.join("/app/frontend/build", full_path)
        if os.path.isfile(file_path):
            return FileResponse(file_path)
        # Fallback to index.html for React Router
        index_path = "/app/frontend/build/index.html"
        if os.path.exists(index_path):
            return FileResponse(index_path)
        return JSONResponse({"error": "index.html not found"}, status_code=404)
else:
    @app.get("/", tags=["System"])
    async def root():
        return JSONResponse({
            "message": "Browser Automation Studio — M5",
            "version": "5.0.0", "docs": "/docs", "health": "/health",
        })


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "backend.main:app", host="0.0.0.0",
        port=int(os.getenv("APP_PORT", "7860")), reload=True,
    )
