# ============================================================
# Browser Automation Studio — backend/tasks.py
# M3: In-memory task queue + state machine
#
# State machine: PENDING → RUNNING → COMPLETED / FAILED / CANCELLED
#
# Tasks are stored in SQLite (persistent) but the active queue
# and WebSocket broadcast manager live in memory.
# ============================================================

import asyncio
import json
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional, Set

from fastapi import WebSocket
from sqlalchemy.orm import Session

from backend.models import (
    TaskModel, TaskStatus, SessionLocal, task_to_schema, log_event
)


# ── WebSocket connection manager ──────────────────────────────
class ConnectionManager:
    """
    Manages all active WebSocket connections.
    Broadcasts task updates and system events to all connected clients.
    """
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        """Send message to all connected WebSocket clients."""
        if not self.active_connections:
            return
        msg_str = json.dumps(message)
        dead = []
        for connection in self.active_connections:
            try:
                await connection.send_text(msg_str)
            except Exception:
                dead.append(connection)
        for conn in dead:
            self.disconnect(conn)

    async def send_to(self, websocket: WebSocket, message: dict):
        """Send message to a single WebSocket client."""
        try:
            await websocket.send_text(json.dumps(message))
        except Exception:
            self.disconnect(websocket)

    def connection_count(self) -> int:
        return len(self.active_connections)


# ── Global instances ──────────────────────────────────────────
# These are module-level singletons shared across the app
ws_manager = ConnectionManager()

# Current system mode — stored in memory, resets to IDLE on restart
_current_mode: str = "IDLE"

# Currently running task ID — only one at a time
_running_task_id: Optional[str] = None


# ── Mode management ───────────────────────────────────────────
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


# ── Task helpers ──────────────────────────────────────────────
def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ws_event(event_type: str, task_id: Optional[str] = None,
              status: Optional[str] = None, message: str = "",
              data: Optional[dict] = None) -> dict:
    """Build a standardised WebSocket event dict."""
    return {
        "type": event_type,
        "task_id": task_id,
        "status": status,
        "message": message,
        "data": data or {},
        "timestamp": _now().isoformat(),
    }


# ── Task CRUD ─────────────────────────────────────────────────
def create_task(db: Session, objective: str, mode: str = "auto") -> TaskModel:
    """Create a new task in PENDING state and persist to DB."""
    task = TaskModel(
        id=str(uuid.uuid4()),
        objective=objective,
        mode=mode,
        status=TaskStatus.PENDING,
        created_at=_now(),
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    log_event(db, "INFO", "tasks", f"Task created: {task.id[:8]}",
              task_id=task.id)
    return task


def get_task(db: Session, task_id: str) -> Optional[TaskModel]:
    """Fetch a task by ID."""
    return db.query(TaskModel).filter(TaskModel.id == task_id).first()


def get_all_tasks(db: Session, limit: int = 50) -> List[TaskModel]:
    """Fetch all tasks, most recent first."""
    return db.query(TaskModel).order_by(
        TaskModel.created_at.desc()
    ).limit(limit).all()


def cancel_task(db: Session, task_id: str) -> Optional[TaskModel]:
    """Cancel a PENDING or RUNNING task."""
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


# ── Task execution ────────────────────────────────────────────
async def run_task_async(task_id: str):
    """
    Execute a task asynchronously.

    In M3, this is a STUB — it simulates task execution.
    Real browser automation is wired in M5 (browser.py + Browser Use).

    State machine: PENDING → RUNNING → COMPLETED / FAILED
    Each state change is broadcast via WebSocket.
    """
    global _running_task_id
    db = SessionLocal()

    try:
        task = get_task(db, task_id)
        if not task:
            return

        # ── PENDING → RUNNING ─────────────────────────────────
        task.status = TaskStatus.RUNNING
        task.started_at = _now()
        task.steps_total = 3   # stub: 3 simulated steps
        db.commit()
        _running_task_id = task_id

        await ws_manager.broadcast(_ws_event(
            "task_update", task_id, "RUNNING",
            f"Starting task: {task.objective[:60]}",
        ))

        # ── Simulate steps (M5 will replace this with real automation) ──
        for step in range(1, 4):
            if task.status == TaskStatus.CANCELLED:
                break

            await asyncio.sleep(1)   # simulate work

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

        # ── RUNNING → COMPLETED ───────────────────────────────
        db.refresh(task)
        if task.status != TaskStatus.CANCELLED:
            task.status = TaskStatus.COMPLETED
            task.completed_at = _now()
            task.progress = 100
            task.result = (
                f"[M3 STUB] Task completed successfully. "
                f"Objective: '{task.objective}'. "
                f"Real automation will run in M5."
            )
            started = task.started_at
            if started:
                task.duration_s = (_now() - started.replace(tzinfo=timezone.utc) if started.tzinfo is None else started).total_seconds()
            db.commit()

            log_event(db, "INFO", "tasks",
                      f"Task completed: {task_id[:8]}", task_id=task_id)

            await ws_manager.broadcast(_ws_event(
                "task_update", task_id, "COMPLETED",
                "Task completed successfully.",
                {"result": task.result, "progress": 100},
            ))

    except Exception as e:
        # ── RUNNING → FAILED ──────────────────────────────────
        db.refresh(task)
        task.status = TaskStatus.FAILED
        task.completed_at = _now()
        task.error = str(e)
        db.commit()

        log_event(db, "ERROR", "tasks",
                  f"Task failed: {task_id[:8]} — {str(e)}", task_id=task_id)

        await ws_manager.broadcast(_ws_event(
            "task_update", task_id, "FAILED",
            f"Task failed: {str(e)}",
        ))

    finally:
        _running_task_id = None
        db.close()


def submit_task(db: Session, objective: str, mode: str = "auto") -> TaskModel:
    """
    Create task in DB and schedule async execution.
    Returns the created task immediately (non-blocking).
    """
    task = create_task(db, objective, mode)
    # Schedule execution in the background event loop
    asyncio.create_task(run_task_async(task.id))
    return task


# ── Periodic WebSocket heartbeat ──────────────────────────────
async def ws_heartbeat():
    """
    Send a ping to all WebSocket clients every 30 seconds.
    Keeps connections alive and lets clients detect disconnects.
    """
    while True:
        await asyncio.sleep(30)
        if ws_manager.connection_count() > 0:
            await ws_manager.broadcast(_ws_event(
                "ping", message="heartbeat",
                data={"connections": ws_manager.connection_count(),
                      "mode": _current_mode},
            ))