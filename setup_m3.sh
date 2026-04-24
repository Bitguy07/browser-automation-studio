#!/bin/bash
# ============================================================
# Browser Automation Studio — setup_m3.sh
# Applies M3 file changes to your existing project.
#
# Run from INSIDE the project directory:
#   cd ~/Documents/studies/Development/BrowserAutomaionStudio/browser-automation-studio
#   bash setup_m3.sh
#
# What this does:
#   1. Updates backend/main.py  — full API with all endpoints
#   2. Updates backend/auth.py  — JWT auth
#   3. Updates backend/models.py — SQLAlchemy + Pydantic schemas
#   4. Updates backend/tasks.py — task queue + WebSocket manager
#   5. Writes guide_m3.md
#   Does NOT touch: Dockerfile, requirements.txt, supervisord.conf,
#                   .env, frontend/, data/, scripts/
# ============================================================

set -e

echo "======================================================"
echo "  Browser Automation Studio — M3 Setup"
echo "======================================================"

# Works from inside or outside the project directory
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
# FILE: backend/auth.py
# ==============================================================
echo "Writing backend/auth.py..."
cat > backend/auth.py << 'AUTH_EOF'
# ============================================================
# Browser Automation Studio — backend/auth.py
# M3: JWT authentication, password validation, token management
# ============================================================

import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext
from dotenv import load_dotenv

load_dotenv()

JWT_SECRET       = os.getenv("JWT_SECRET", "change-this-secret-in-production")
JWT_ALGORITHM    = "HS256"
JWT_EXPIRE_HOURS = 24
APP_PASSWORD     = os.getenv("APP_PASSWORD", "admin")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)
_blacklisted_tokens: set = set()


def verify_password(plain_password: str) -> bool:
    return plain_password == APP_PASSWORD


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRE_HOURS)
    to_encode.update({"exp": expire, "iat": datetime.now(timezone.utc)})
    return jwt.encode(to_encode, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    if token in _blacklisted_tokens:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked. Please login again.",
        )
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid or expired token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )


def blacklist_token(token: str) -> None:
    _blacklisted_tokens.add(token)


def verify_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme)
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header missing. Use: Bearer <token>",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return decode_token(credentials.credentials)


def get_raw_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme)
) -> str:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header missing.",
        )
    return credentials.credentials
AUTH_EOF

# ==============================================================
# FILE: backend/models.py
# ==============================================================
echo "Writing backend/models.py..."
cat > backend/models.py << 'MODELS_EOF'
# ============================================================
# Browser Automation Studio — backend/models.py
# M3: SQLAlchemy database models + Pydantic schemas
# Tables: tasks, recordings, system_logs, users
# ============================================================

import os
import uuid
from datetime import datetime, timezone
from typing import Optional, List
from enum import Enum

from sqlalchemy import (
    create_engine, Column, String, Text, DateTime,
    Boolean, Integer, Float, event
)
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from sqlalchemy.pool import StaticPool
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "/data/app.db")
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

DATABASE_URL = f"sqlite:///{DB_PATH}"
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
    echo=False,
)

@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class TaskStatus(str, Enum):
    PENDING   = "PENDING"
    RUNNING   = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED    = "FAILED"
    CANCELLED = "CANCELLED"


class SystemMode(str, Enum):
    IDLE       = "IDLE"
    MANUAL     = "MANUAL"
    AUTONOMOUS = "AUTONOMOUS"


class LogLevel(str, Enum):
    DEBUG   = "DEBUG"
    INFO    = "INFO"
    WARNING = "WARNING"
    ERROR   = "ERROR"


class TaskModel(Base):
    __tablename__ = "tasks"
    id           = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    objective    = Column(Text, nullable=False)
    mode         = Column(String, default="auto")
    status       = Column(String, default=TaskStatus.PENDING)
    result       = Column(Text, nullable=True)
    error        = Column(Text, nullable=True)
    progress     = Column(Integer, default=0)
    steps_done   = Column(Integer, default=0)
    steps_total  = Column(Integer, default=0)
    created_at   = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    started_at   = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    duration_s   = Column(Float, nullable=True)


class RecordingModel(Base):
    __tablename__ = "recordings"
    id          = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name        = Column(String, nullable=False, unique=True)
    description = Column(Text, nullable=True)
    file_path   = Column(String, nullable=True)
    size_bytes  = Column(Integer, default=0)
    created_at  = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class SystemLogModel(Base):
    __tablename__ = "system_logs"
    id         = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    level      = Column(String, default=LogLevel.INFO)
    component  = Column(String, default="system")
    message    = Column(Text, nullable=False)
    details    = Column(Text, nullable=True)
    task_id    = Column(String, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class UserModel(Base):
    __tablename__ = "users"
    id          = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    username    = Column(String, default="admin", unique=True)
    last_login  = Column(DateTime, nullable=True)
    login_count = Column(Integer, default=0)
    created_at  = Column(DateTime, default=lambda: datetime.now(timezone.utc))


def init_db():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        admin = db.query(UserModel).filter_by(username="admin").first()
        if not admin:
            db.add(UserModel(username="admin"))
            db.commit()
    finally:
        db.close()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── Pydantic schemas ──────────────────────────────────────────
class LoginRequest(BaseModel):
    password: str = Field(..., description="APP_PASSWORD from .env")

class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int = 86400
    message: str = "Login successful"

class LogoutResponse(BaseModel):
    message: str = "Logged out successfully"

class TaskSubmitRequest(BaseModel):
    objective: str = Field(..., min_length=3, description="What should the browser do?")
    mode: str = Field("auto", description="auto or manual")

class TaskResponse(BaseModel):
    id: str
    objective: str
    mode: str
    status: str
    result: Optional[str] = None
    error: Optional[str] = None
    progress: int = 0
    steps_done: int = 0
    steps_total: int = 0
    created_at: str
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    duration_s: Optional[float] = None

class TaskListResponse(BaseModel):
    tasks: List[TaskResponse]
    total: int

class ModeResponse(BaseModel):
    mode: str
    message: str

class ModeSwitchRequest(BaseModel):
    mode: str = Field(..., description="IDLE, MANUAL, or AUTONOMOUS")

class SessionSaveRequest(BaseModel):
    name: str = Field(..., min_length=1, description="Name for the saved session")

class SessionInfo(BaseModel):
    name: str
    file_path: str
    size_bytes: int
    created_at: str

class SessionListResponse(BaseModel):
    sessions: List[SessionInfo]
    total: int


def task_to_schema(task: TaskModel) -> TaskResponse:
    def fmt(dt): return dt.isoformat() if dt else None
    return TaskResponse(
        id=task.id, objective=task.objective, mode=task.mode,
        status=task.status, result=task.result, error=task.error,
        progress=task.progress, steps_done=task.steps_done,
        steps_total=task.steps_total,
        created_at=fmt(task.created_at), started_at=fmt(task.started_at),
        completed_at=fmt(task.completed_at), duration_s=task.duration_s,
    )


def log_event(db: Session, level: str, component: str, message: str,
              details: str = None, task_id: str = None):
    entry = SystemLogModel(
        level=level, component=component, message=message,
        details=details, task_id=task_id,
    )
    db.add(entry)
    db.commit()
MODELS_EOF

# ==============================================================
# FILE: backend/tasks.py
# ==============================================================
echo "Writing backend/tasks.py..."
cat > backend/tasks.py << 'TASKS_EOF'
# ============================================================
# Browser Automation Studio — backend/tasks.py
# M3: In-memory task queue + WebSocket broadcast manager
# State machine: PENDING → RUNNING → COMPLETED / FAILED / CANCELLED
# ============================================================

import asyncio
import json
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional

from fastapi import WebSocket
from sqlalchemy.orm import Session

from backend.models import (
    TaskModel, TaskStatus, SessionLocal, task_to_schema, log_event
)


class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        if not self.active_connections:
            return
        msg_str = json.dumps(message)
        dead = []
        for conn in self.active_connections:
            try:
                await conn.send_text(msg_str)
            except Exception:
                dead.append(conn)
        for conn in dead:
            self.disconnect(conn)

    async def send_to(self, websocket: WebSocket, message: dict):
        try:
            await websocket.send_text(json.dumps(message))
        except Exception:
            self.disconnect(websocket)

    def connection_count(self) -> int:
        return len(self.active_connections)


ws_manager = ConnectionManager()
_current_mode: str = "IDLE"
_running_task_id: Optional[str] = None


def get_mode() -> str:
    return _current_mode


def set_mode(mode: str) -> str:
    global _current_mode
    valid = {"IDLE", "MANUAL", "AUTONOMOUS"}
    mode = mode.upper()
    if mode not in valid:
        raise ValueError(f"Invalid mode '{mode}'. Must be one of: {valid}")
    _current_mode = mode
    return _current_mode


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ws_event(event_type: str, task_id: Optional[str] = None,
              status: Optional[str] = None, message: str = "",
              data: Optional[dict] = None) -> dict:
    return {
        "type": event_type, "task_id": task_id, "status": status,
        "message": message, "data": data or {},
        "timestamp": _now().isoformat(),
    }


def create_task(db: Session, objective: str, mode: str = "auto") -> TaskModel:
    task = TaskModel(
        id=str(uuid.uuid4()), objective=objective, mode=mode,
        status=TaskStatus.PENDING, created_at=_now(),
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    log_event(db, "INFO", "tasks", f"Task created: {task.id[:8]}", task_id=task.id)
    return task


def get_task(db: Session, task_id: str) -> Optional[TaskModel]:
    return db.query(TaskModel).filter(TaskModel.id == task_id).first()


def get_all_tasks(db: Session, limit: int = 50) -> List[TaskModel]:
    return db.query(TaskModel).order_by(TaskModel.created_at.desc()).limit(limit).all()


def cancel_task(db: Session, task_id: str) -> Optional[TaskModel]:
    task = get_task(db, task_id)
    if not task:
        return None
    if task.status in (TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED):
        return task
    task.status = TaskStatus.CANCELLED
    task.completed_at = _now()
    db.commit()
    db.refresh(task)
    log_event(db, "INFO", "tasks", f"Task cancelled: {task_id[:8]}", task_id=task_id)
    return task


async def run_task_async(task_id: str):
    global _running_task_id
    db = SessionLocal()
    try:
        task = get_task(db, task_id)
        if not task:
            return

        task.status = TaskStatus.RUNNING
        task.started_at = _now()
        task.steps_total = 3
        db.commit()
        _running_task_id = task_id

        await ws_manager.broadcast(_ws_event(
            "task_update", task_id, "RUNNING",
            f"Starting: {task.objective[:60]}",
        ))

        for step in range(1, 4):
            await asyncio.sleep(1)
            db.refresh(task)
            if task.status == TaskStatus.CANCELLED:
                break
            task.steps_done = step
            task.progress = int((step / task.steps_total) * 100)
            db.commit()
            await ws_manager.broadcast(_ws_event(
                "task_update", task_id, "RUNNING",
                f"Step {step}/{task.steps_total}: Processing...",
                {"progress": task.progress, "step": step},
            ))

        db.refresh(task)
        if task.status != TaskStatus.CANCELLED:
            task.status = TaskStatus.COMPLETED
            task.completed_at = _now()
            task.progress = 100
            task.result = (
                f"[M3 STUB] Completed: '{task.objective}'. "
                f"Real automation wired in M5."
            )
            if task.started_at:
                task.duration_s = (_now() - task.started_at).total_seconds()
            db.commit()
            log_event(db, "INFO", "tasks", f"Task completed: {task_id[:8]}", task_id=task_id)
            await ws_manager.broadcast(_ws_event(
                "task_update", task_id, "COMPLETED",
                "Task completed.", {"result": task.result, "progress": 100},
            ))

    except Exception as e:
        db.refresh(task)
        task.status = TaskStatus.FAILED
        task.completed_at = _now()
        task.error = str(e)
        db.commit()
        log_event(db, "ERROR", "tasks", f"Task failed: {task_id[:8]} — {e}", task_id=task_id)
        await ws_manager.broadcast(_ws_event(
            "task_update", task_id, "FAILED", f"Task failed: {e}",
        ))
    finally:
        _running_task_id = None
        db.close()


def submit_task(db: Session, objective: str, mode: str = "auto") -> TaskModel:
    task = create_task(db, objective, mode)
    asyncio.create_task(run_task_async(task.id))
    return task


async def ws_heartbeat():
    while True:
        await asyncio.sleep(30)
        if ws_manager.connection_count() > 0:
            await ws_manager.broadcast(_ws_event(
                "ping", message="heartbeat",
                data={"connections": ws_manager.connection_count(), "mode": _current_mode},
            ))
TASKS_EOF

# ==============================================================
# FILE: backend/main.py
# ==============================================================
echo "Writing backend/main.py..."
cat > backend/main.py << 'MAIN_EOF'
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
MAIN_EOF

# ==============================================================
# FILE: guide_m3.md
# ==============================================================
echo "Writing guide_m3.md..."
cat > guide_m3.md << 'GUIDE_EOF'
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
GUIDE_EOF

# ==============================================================
# Verification
# ==============================================================
echo ""
echo "======================================================"
echo "  Verifying M3 files..."
echo "======================================================"

EXPECTED=(
    "./backend/auth.py"
    "./backend/models.py"
    "./backend/tasks.py"
    "./backend/main.py"
    "./guide_m3.md"
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
echo "  Previous modules intact:"
PREV=(
    "./.env" "./Dockerfile" "./docker-compose.yml"
    "./supervisord.conf" "./requirements.txt"
    "./scripts/start.sh" "./frontend/package.json"
)
for f in "${PREV[@]}"; do
    if [ -f "$f" ]; then
        echo "  ✓ $f"
    else
        echo "  ✗ MISSING: $f"
        ALL_OK=false
    fi
done

echo ""
if [ "$ALL_OK" = true ]; then
    echo "✅ M3 setup complete."
    echo ""
    echo "Next steps:"
    echo "  docker compose down"
    echo "  docker compose up"
    echo "  TOKEN=\$(curl -s -X POST http://localhost:7860/api/auth/login \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"password\": \"YOUR_PASSWORD\"}' | jq -r '.access_token')"
    echo "  curl -s http://localhost:7860/api/mode -H \"Authorization: Bearer \$TOKEN\" | jq"
else
    echo "❌ Some files missing — check above."
fi
echo "======================================================"
