# ============================================================
# Browser Automation Studio — backend/tasks.py
# M5: Real automation wired — replaces M3 stub
#
# State machine: PENDING → RUNNING → COMPLETED / FAILED / CANCELLED
# ============================================================

import asyncio
import json
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import WebSocket
from sqlalchemy.orm import Session

from backend.models import (
    TaskModel, TaskStatus, SessionLocal, task_to_schema, log_event
)


# ── WebSocket connection manager ──────────────────────────────
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
        for connection in self.active_connections:
            try:
                await connection.send_text(msg_str)
            except Exception:
                dead.append(connection)
        for conn in dead:
            self.disconnect(conn)

    async def send_to(self, websocket: WebSocket, message: dict):
        try:
            await websocket.send_text(json.dumps(message))
        except Exception:
            self.disconnect(websocket)

    def connection_count(self) -> int:
        return len(self.active_connections)


# ── Global singletons ─────────────────────────────────────────
ws_manager = ConnectionManager()
_current_mode: str = "IDLE"
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
    return {
        "type":      event_type,
        "task_id":   task_id,
        "status":    status,
        "message":   message,
        "data":      data or {},
        "timestamp": _now().isoformat(),
    }


# ── Task CRUD ─────────────────────────────────────────────────
def create_task(db: Session, objective: str, mode: str = "auto") -> TaskModel:
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


# ── DB update helpers (called from browser.py via run_task_async) ──

def _db_set_running(task_id: str):
    """Mark task RUNNING in DB (called just before browser.run_task)."""
    db = SessionLocal()
    try:
        task = get_task(db, task_id)
        if task:
            task.status    = TaskStatus.RUNNING
            task.started_at = _now()
            db.commit()
    finally:
        db.close()


def _db_update_step(task_id: str, steps_done: int, steps_total: int, progress: int):
    """Update step progress in DB (called from the step callback)."""
    db = SessionLocal()
    try:
        task = get_task(db, task_id)
        if task:
            task.steps_done  = steps_done
            task.steps_total = steps_total
            task.progress    = progress
            db.commit()
    finally:
        db.close()


def _db_set_completed(task_id: str, result: str):
    db = SessionLocal()
    try:
        task = get_task(db, task_id)
        if task:
            task.status       = TaskStatus.COMPLETED
            task.completed_at = _now()
            task.progress     = 100
            task.result       = result
            if task.started_at:
                started = task.started_at
                if started.tzinfo is None:
                    from datetime import timezone as tz
                    started = started.replace(tzinfo=tz.utc)
                task.duration_s = (_now() - started).total_seconds()
            db.commit()
        log_event(db, "INFO", "tasks", f"Task completed: {task_id[:8]}", task_id=task_id)
    finally:
        db.close()


def _db_set_failed(task_id: str, error: str):
    db = SessionLocal()
    try:
        task = get_task(db, task_id)
        if task:
            task.status       = TaskStatus.FAILED
            task.completed_at = _now()
            task.error        = error[:2000]
            db.commit()
        log_event(db, "ERROR", "tasks", f"Task failed: {task_id[:8]} — {error[:120]}",
                  task_id=task_id)
    finally:
        db.close()


# ── Task execution ────────────────────────────────────────────
async def run_task_async(task_id: str):
    """
    Full M5 task runner.
    Calls browser.run_task() with the real browser-use agent.
    Falls back to a descriptive error if something goes wrong.
    """
    global _running_task_id
    _running_task_id = task_id

    # Announce RUNNING via WebSocket
    _db_set_running(task_id)

    db_read = SessionLocal()
    try:
        task = get_task(db_read, task_id)
        if not task:
            return
        objective = task.objective
    finally:
        db_read.close()

    await ws_manager.broadcast(_ws_event(
        "task_update", task_id, "RUNNING",
        f"Starting: {objective[:60]}",
        {"progress": 1},
    ))

    try:
        from backend.browser import run_task as browser_run_task

        result = await browser_run_task(
            objective=objective,
            task_id=task_id,
            ws_broadcast=ws_manager.broadcast,
            update_task_status=lambda tid, st, **kw: None,   # handled internally
            update_task_step=_db_update_step,
        )

        _db_set_completed(task_id, result)

        await ws_manager.broadcast(_ws_event(
            "task_update", task_id, "COMPLETED",
            "Task completed.",
            {"result": result, "progress": 100},
        ))

    except Exception as e:
        error_msg = str(e)[:500]
        _db_set_failed(task_id, error_msg)

        await ws_manager.broadcast(_ws_event(
            "task_update", task_id, "FAILED",
            f"Task failed: {error_msg}",
            {"error": error_msg},
        ))

    finally:
        _running_task_id = None


def submit_task(db: Session, objective: str, mode: str = "auto") -> TaskModel:
    """Create task in DB and schedule async execution. Non-blocking."""
    task = create_task(db, objective, mode)
    asyncio.create_task(run_task_async(task.id))
    return task


# ── WebSocket heartbeat ───────────────────────────────────────
async def ws_heartbeat():
    while True:
        await asyncio.sleep(30)
        if ws_manager.connection_count() > 0:
            await ws_manager.broadcast(_ws_event(
                "ping", message="heartbeat",
                data={"connections": ws_manager.connection_count(),
                      "mode": _current_mode},
            ))
