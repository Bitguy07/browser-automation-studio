"""
fastapi_proxy.py — FastAPI router that proxies all agent endpoints.

Drop this into your existing FastAPI app:

    from hf_flight_recorder_agent.fastapi_proxy import router as fr_router
    app.include_router(fr_router)

Exposes:
    GET /_hf_flight_recorder/metrics
    GET /_hf_flight_recorder/history
    GET /_hf_flight_recorder/events
    GET /_hf_flight_recorder/health
    GET /_hf_flight_recorder/version
"""

from __future__ import annotations

import json
import logging
from urllib.request import urlopen, Request
from urllib.error import URLError

try:
    from fastapi import APIRouter, HTTPException, Request as FARequest
    from fastapi.responses import JSONResponse
except ImportError:
    raise ImportError("fastapi is required: pip install fastapi")

log = logging.getLogger("hf_flight_recorder_agent.proxy")

AGENT_BASE = "http://127.0.0.1:9999/_hf_flight_recorder"

router = APIRouter(prefix="/_hf_flight_recorder", tags=["flight-recorder"])


def _fetch(path: str, timeout: float = 4.0) -> dict | list:
    url = f"{AGENT_BASE}{path}"
    try:
        req = Request(url, method="GET")
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except URLError as e:
        log.warning("Agent unreachable at %s: %s", url, e)
        raise HTTPException(status_code=503, detail=f"Agent unreachable: {e.reason}")
    except Exception as e:
        log.exception("Proxy error for %s: %s", url, e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/metrics")
async def proxy_metrics():
    """Latest system snapshot from the in-container agent."""
    return JSONResponse(_fetch("/metrics"))


@router.get("/history")
async def proxy_history():
    """Rolling snapshot history + RAM trend from the agent."""
    return JSONResponse(_fetch("/history"))


@router.get("/events")
async def proxy_events():
    """Derived events (RAM pressure, disk pressure, FastAPI health) from the agent."""
    return JSONResponse(_fetch("/events"))


@router.get("/health")
async def proxy_health():
    """Agent liveness probe (uptime, snapshot count)."""
    return JSONResponse(_fetch("/health"))


@router.get("/version")
async def proxy_version():
    """Agent version and API endpoint manifest."""
    return JSONResponse(_fetch("/version"))
