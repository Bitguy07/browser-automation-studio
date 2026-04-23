# ============================================================
# Browser Automation Studio — backend/main.py
# M2: Added /api/browser/screenshot endpoint
#     Added /vnc proxy route for noVNC access via port 7860
#     Added /api/vnc/status endpoint
# ============================================================

import os
import base64
import subprocess
import socket
import tempfile
from datetime import datetime, timezone
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from dotenv import load_dotenv

load_dotenv()


# ── Lifespan ─────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    print("=" * 60)
    print("  Browser Automation Studio — Starting Up (M2)")
    print(f"  Port: {os.getenv('APP_PORT', '7860')}")
    print(f"  Running in: {'Docker' if os.path.exists('/.dockerenv') else 'Local'}")
    print("=" * 60)
    for path in ["/data", "/data/cookies", "/data/outputs"]:
        os.makedirs(path, exist_ok=True)
    yield
    print("Browser Automation Studio — Shutting down.")


# ── App ───────────────────────────────────────────────────────
app = FastAPI(
    title="Browser Automation Studio",
    description="Self-hosted browser automation platform with AI",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:7860",
        "https://*.hf.space",
        "*",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Helpers ───────────────────────────────────────────────────
def is_process_running(name: str) -> bool:
    try:
        result = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
        return result.returncode == 0
    except Exception:
        return False


def is_port_open(port: int) -> bool:
    try:
        with socket.create_connection(("localhost", port), timeout=1):
            return True
    except (ConnectionRefusedError, OSError):
        return False


def take_screenshot_scrot() -> str:
    """
    Take a screenshot of virtual display :99 using scrot.
    Returns base64-encoded PNG string.
    Captures the ENTIRE virtual screen including Chrome window.
    """
    # Use a fixed path — scrot requires the file to NOT exist before writing
    tmppath = f"/tmp/scrot_screenshot_{os.getpid()}.png"

    # Delete if exists — scrot refuses to overwrite existing files
    if os.path.exists(tmppath):
        os.unlink(tmppath)

    try:
        env = {**os.environ, "DISPLAY": ":99"}
        result = subprocess.run(
            ["scrot", tmppath],
            capture_output=True,
            text=True,
            timeout=10,
            env=env
        )
        if result.returncode != 0:
            raise RuntimeError(f"scrot error: {result.stderr.strip()}")

        if not os.path.exists(tmppath) or os.path.getsize(tmppath) == 0:
            raise RuntimeError(f"scrot produced empty or missing file at {tmppath}")

        with open(tmppath, "rb") as f:
            return base64.b64encode(f.read()).decode("utf-8")
    finally:
        if os.path.exists(tmppath):
            os.unlink(tmppath)


def take_screenshot_cdp() -> str:
    """
    Take a screenshot via Chrome DevTools Protocol.
    Connects to Chrome's --remote-debugging-port=9222.
    Returns base64-encoded PNG string.
    This captures exactly what Chrome is rendering.
    """
    import urllib.request
    import json
    import websocket  # websocket-client package

    # Get available pages from Chrome
    try:
        with urllib.request.urlopen("http://localhost:9222/json", timeout=3) as resp:
            pages = json.loads(resp.read())
    except Exception as e:
        raise RuntimeError(f"Cannot reach Chrome DevTools :9222 — {e}")

    # Find a real page tab
    page = next((p for p in pages if p.get("type") == "page"), None)
    if not page:
        raise RuntimeError("No Chrome page tab found")

    ws_url = page.get("webSocketDebuggerUrl")
    if not ws_url:
        raise RuntimeError("No WebSocket debugger URL in page")

    ws = websocket.create_connection(ws_url, timeout=5)
    try:
        ws.send(json.dumps({
            "id": 1,
            "method": "Page.captureScreenshot",
            "params": {"format": "png", "quality": 80}
        }))
        response = json.loads(ws.recv())
        if "result" in response and "data" in response["result"]:
            return response["result"]["data"]
        raise RuntimeError(f"CDP response had no data: {response}")
    finally:
        ws.close()


# ── Routes ────────────────────────────────────────────────────

@app.get("/health")
async def health_check():
    """Health check — all M2 component status."""
    return JSONResponse(
        status_code=200,
        content={
            "status": "ok",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "version": "2.0.0",
            "module": "M2 — Chrome + noVNC",
            "components": {
                "fastapi": "ok",
                "xvfb": "ok" if is_process_running("Xvfb") else "not_running",
                "chromium": "ok" if is_process_running("chrome") else "not_running",
                "x11vnc": "ok" if is_process_running("x11vnc") else "not_running",
                "websockify": "ok" if is_port_open(6080) else "not_ready",
                "chrome_devtools": "ok" if is_port_open(9222) else "not_ready",
                "database": "ok" if os.path.exists("/data") else "no_data_dir",
            },
        }
    )


@app.post("/api/browser/screenshot")
@app.get("/api/browser/screenshot")
async def browser_screenshot():
    """
    M2: Capture current Chrome screen as base64 PNG.

    Strategy:
      1. Try Chrome DevTools Protocol (CDP) — captures actual browser content
      2. Fall back to scrot — captures entire virtual display :99

    Returns JSON with base64 PNG you can use directly as:
      <img src="data:image/png;base64,{screenshot}">
    """
    screenshot_b64 = None
    method_used = None

    # Try CDP first
    try:
        screenshot_b64 = take_screenshot_cdp()
        method_used = "chrome_devtools_protocol"
    except Exception as cdp_err:
        # Fall back to scrot
        try:
            screenshot_b64 = take_screenshot_scrot()
            method_used = "scrot_virtual_display"
        except Exception as scrot_err:
            raise HTTPException(
                status_code=500,
                detail={
                    "error": "Both screenshot methods failed",
                    "cdp_error": str(cdp_err),
                    "scrot_error": str(scrot_err),
                    "hint": "Ensure Chrome and Xvfb are running (check /health)",
                }
            )

    return JSONResponse(content={
        "status": "ok",
        "screenshot": screenshot_b64,
        "format": "png",
        "encoding": "base64",
        "method": method_used,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "img_src": "data:image/png;base64," + screenshot_b64,
    })


@app.get("/api/vnc/status")
async def vnc_status():
    """Check the entire VNC streaming chain."""
    return JSONResponse({
        "chain": {
            "1_xvfb": "running" if is_process_running("Xvfb") else "stopped",
            "2_chromium": "running" if is_process_running("chrome") else "stopped",
            "3_x11vnc": "running" if is_process_running("x11vnc") else "stopped",
            "4_websockify": "running" if is_process_running("websockify") else "stopped",
        },
        "ports": {
            "vnc_raw_5900": "open" if is_port_open(5900) else "closed",
            "novnc_ws_6080": "open" if is_port_open(6080) else "closed",
            "chrome_devtools_9222": "open" if is_port_open(9222) else "closed",
        },
        "access": {
            "novnc_direct": "http://localhost:6080/vnc.html",
            "novnc_via_fastapi": "http://localhost:7860/vnc/vnc.html",
            "screenshot_api": "http://localhost:7860/api/browser/screenshot",
        }
    })


@app.get("/")
async def root():
    react_build = "/app/frontend/build/index.html"
    if os.path.exists(react_build):
        return FileResponse(react_build)
    return JSONResponse({
        "message": "Browser Automation Studio — M2 running",
        "status": "ok",
        "module": "M2 — Chrome + noVNC",
        "endpoints": {
            "health": "/health",
            "docs": "/docs",
            "screenshot": "/api/browser/screenshot",
            "vnc_status": "/api/vnc/status",
            "novnc_direct": "http://localhost:6080/vnc.html",
            "novnc_via_fastapi": "http://localhost:7860/vnc/vnc.html",
        }
    })


# ── Static mounts ─────────────────────────────────────────────
# noVNC served at /vnc — accessible at http://localhost:7860/vnc/vnc.html
novnc_dir = "/opt/novnc"
if os.path.exists(novnc_dir):
    app.mount("/vnc", StaticFiles(directory=novnc_dir), name="novnc")

# React build (M4 onwards)
react_build_dir = "/app/frontend/build"
if os.path.exists(react_build_dir):
    app.mount("/static", StaticFiles(directory=f"{react_build_dir}/static"), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0",
                port=int(os.getenv("APP_PORT", "7860")), reload=True)