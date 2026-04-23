# ============================================================
# Browser Automation Studio — backend/main.py
# FastAPI application entry point
# M1: Only the /health endpoint. More added in M3.
# ============================================================

import os
import sys
import subprocess
from datetime import datetime, timezone
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse

# Load environment variables from .env if present
from dotenv import load_dotenv
load_dotenv()


# ── Lifespan: runs on startup and shutdown ────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events."""
    print("=" * 60)
    print("  Browser Automation Studio — Starting Up")
    print("=" * 60)
    print(f"  FastAPI running on port: {os.getenv('APP_PORT', '7860')}")
    print(f"  Environment: {'Docker/HF' if os.path.exists('/.dockerenv') else 'Local'}")
    print(f"  Data directory: {os.getenv('DATA_DIR', '/data')}")
    print("=" * 60)
    
    # Ensure data directories exist
    for path in ["/data", "/data/cookies", "/data/outputs"]:
        os.makedirs(path, exist_ok=True)
    
    yield  # App runs here
    
    print("Browser Automation Studio — Shutting down.")


# ── FastAPI app instance ──────────────────────────────────────
app = FastAPI(
    title="Browser Automation Studio",
    description="Self-hosted browser automation platform with AI",
    version="1.0.0",
    lifespan=lifespan,
    # Swagger UI available at /docs
    docs_url="/docs",
    redoc_url="/redoc",
)


# ── CORS middleware ───────────────────────────────────────────
# Allows React dev server (port 3000) and HF Spaces to call the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:7860",
        "https://*.hf.space",
        "*",  # Tighten this in production
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Helper: check if a process is running ────────────────────
def is_process_running(name: str) -> bool:
    """Check if a named process is currently running."""
    try:
        result = subprocess.run(
            ["pgrep", "-f", name],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except Exception:
        return False


def is_port_open(port: int) -> bool:
    """Check if a port is accepting connections."""
    import socket
    try:
        with socket.create_connection(("localhost", port), timeout=1):
            return True
    except (ConnectionRefusedError, OSError):
        return False


# ── Routes ────────────────────────────────────────────────────

@app.get("/health")
async def health_check():
    """
    Health check endpoint.
    Returns status of the application and all components.
    Used by: Docker healthcheck, Hugging Face, cron-job.org keep-alive
    """
    now = datetime.now(timezone.utc).isoformat()
    
    # Component checks (will become more meaningful in M2/M3)
    components = {
        "fastapi": "ok",
        "xvfb": "ok" if is_process_running("Xvfb") else "not_running",
        "chromium": "ok" if is_process_running("chromium") else "not_running",
        "x11vnc": "ok" if is_process_running("x11vnc") else "not_running",
        "vnc_port": "ok" if is_port_open(6080) else "not_ready",
        "database": "ok" if os.path.exists("/data") else "no_data_dir",
    }
    
    # Overall status: ok only if FastAPI itself is running (it is, we're here)
    # Other components may not be running in M1 yet — that's fine
    overall = "ok"
    
    return JSONResponse(
        status_code=200,
        content={
            "status": overall,
            "timestamp": now,
            "version": "1.0.0",
            "module": "M1 — Foundation",
            "components": components,
            "uptime": "running",
        }
    )


@app.get("/")
async def root():
    """
    Root endpoint.
    In M4, this will serve the React frontend.
    For now, returns a simple JSON response.
    """
    # Check if React build exists (will be built in M4)
    react_build = "/app/frontend/build/index.html"
    if os.path.exists(react_build):
        return FileResponse(react_build)
    
    # M1 fallback: simple JSON
    return JSONResponse({
        "message": "Browser Automation Studio is running!",
        "status": "ok",
        "docs": "/docs",
        "health": "/health",
        "note": "React frontend will be served here after M4 is complete."
    })


# ── Static file mounts (activated in later modules) ──────────

# React frontend build (M4)
react_build_dir = "/app/frontend/build"
if os.path.exists(react_build_dir):
    app.mount("/static", StaticFiles(directory=f"{react_build_dir}/static"), name="static")

# noVNC files (M2)
novnc_dir = "/opt/novnc"
if os.path.exists(novnc_dir):
    app.mount("/vnc", StaticFiles(directory=novnc_dir), name="novnc")


# ── Run directly (for testing without uvicorn CLI) ────────────
if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("APP_PORT", "7860"))
    uvicorn.run(
        "backend.main:app",
        host="0.0.0.0",
        port=port,
        reload=True,
        log_level="info"
    )
