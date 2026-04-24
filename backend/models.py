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
