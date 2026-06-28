"""
server.py — Agent HTTP server (v1.0).

Endpoints:
    GET /_hf_flight_recorder/metrics      latest snapshot
    GET /_hf_flight_recorder/history      rolling snapshot history + RAM trend
    GET /_hf_flight_recorder/events       derived events (stage hints, trend alerts)
    GET /_hf_flight_recorder/health       agent liveness
    GET /_hf_flight_recorder/version      package version + compatibility

All endpoints optionally require a valid HF Bearer token when
AgentConfig.verify_token is True.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Optional
from urllib.request import urlopen, Request
from urllib.error import URLError

from .collector import collect, Snapshot
from .config import AgentConfig
from .heartbeat import Heartbeat
from .security import TokenVerifier, extract_bearer
from .snapshot import SnapshotStore
from . import startup_check as _startup_check
from . import __version__

log = logging.getLogger("hf_flight_recorder_agent.server")


# ── Module-level shared state (set by AgentServer.start) ─────────────────────

_store: Optional[SnapshotStore] = None
_verifier: Optional[TokenVerifier] = None
_cfg: Optional[AgentConfig] = None
_start_time: float = time.time()


# ── FastAPI health helper ─────────────────────────────────────────────────────

def _check_fastapi_health(url: str, timeout: float) -> str:
    try:
        req = Request(url, method="GET")
        with urlopen(req, timeout=timeout) as resp:
            return f"ok:{resp.status}"
    except URLError as e:
        return f"error:{e.reason}"
    except Exception as e:
        return f"error:{e}"


# ── Collector loop ────────────────────────────────────────────────────────────

def _collector_loop(cfg: AgentConfig, store: SnapshotStore) -> None:
    log.info("Collector started (interval=%.1fs)", cfg.collect_interval)
    while True:
        t0 = time.monotonic()
        try:
            health = _check_fastapi_health(cfg.fastapi_health_url, cfg.fastapi_health_timeout)
            snap: Snapshot = collect(fastapi_health=health)
            store.push(snap.to_dict())
        except Exception as exc:
            log.exception("Collector error: %s", exc)
        elapsed = time.monotonic() - t0
        time.sleep(max(0.0, cfg.collect_interval - elapsed))


# ── Derived events builder ────────────────────────────────────────────────────

def _build_events(store: SnapshotStore) -> list[dict]:
    """
    Produce a list of derived event dicts from the snapshot history.
    These are lightweight signals the recorder can use without running
    the full analyzer locally.
    """
    events: list[dict] = []
    now = time.time()

    latest = store.latest()
    if not latest:
        return events

    # RAM pressure event
    ram_pct = latest.get("ram_percent", 0)
    cg_limit = latest.get("cgroup_limit_mb")
    cg_used  = latest.get("cgroup_used_mb")

    if cg_limit and cg_used:
        cg_pct = cg_used / cg_limit * 100
        if cg_pct > 85:
            events.append({
                "ts": now, "type": "CGROUP_PRESSURE",
                "cg_pct": round(cg_pct, 1), "cg_used": cg_used, "cg_limit": cg_limit,
            })
    elif ram_pct > 85:
        events.append({"ts": now, "type": "RAM_PRESSURE", "ram_pct": ram_pct})

    # RAM trend event
    trend = store.ram_trend(window=30)
    if trend is not None and trend > 5.0:
        events.append({"ts": now, "type": "RAM_TREND_UP", "slope_mb_per_sample": trend})

    # Disk event
    disk_pct = latest.get("disk_percent", 0)
    if disk_pct > 90:
        events.append({"ts": now, "type": "DISK_PRESSURE", "disk_pct": disk_pct})

    # FastAPI health event
    health = latest.get("fastapi_health", "")
    if health and not health.startswith("ok"):
        events.append({"ts": now, "type": "FASTAPI_UNHEALTHY", "detail": health})

    return events


# ── Request handler ───────────────────────────────────────────────────────────

class _Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass  # silence default access log; we use our own logger

    def _authorized(self) -> bool:
        if not (_cfg and _cfg.verify_token):
            return True
        auth = self.headers.get("Authorization")
        token = extract_bearer(auth)
        if not token:
            return False
        return _verifier.is_valid(token) if _verifier else True

    def _send_json(self, data, status: int = 200) -> None:
        body = json.dumps(data, default=str).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):   # noqa: N802
        if not self._authorized():
            self._send_json({"error": "unauthorized"}, 401)
            return

        path = self.path.split("?")[0]

        if path == "/_hf_flight_recorder/metrics":
            latest = _store.latest() if _store else None
            if latest:
                self._send_json(latest)
            else:
                self._send_json({"error": "no data yet"}, 503)

        elif path == "/_hf_flight_recorder/history":
            if _store:
                self._send_json({
                    "snapshots": _store.all(),
                    "stats": _store.stats(),
                    "ram_trend_mb_per_sample": _store.ram_trend(),
                })
            else:
                self._send_json({"error": "store not initialized"}, 503)

        elif path == "/_hf_flight_recorder/events":
            if _store:
                self._send_json({"events": _build_events(_store)})
            else:
                self._send_json({"events": []})

        elif path == "/_hf_flight_recorder/health":
            uptime = round(time.time() - _start_time, 1)
            count = len(_store.all()) if _store else 0
            sr = _startup_check.get()
            startup_info = {}
            if sr:
                from dataclasses import asdict
                startup_info = {
                    "restart_count": sr.restart_count,
                    "shutdown_type": sr.shutdown_type,
                    "data_dir_writable": sr.data_dir_writable,
                    "seconds_since_last_heartbeat": sr.seconds_since_last_heartbeat,
                    "last_heartbeat_iso": sr.last_heartbeat_iso,
                }
            self._send_json({
                "status": "alive",
                "uptime_s": uptime,
                "snapshots_collected": count,
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "startup": startup_info,
            })

        elif path == "/_hf_flight_recorder/version":
            self._send_json({
                "package": "hf-flight-recorder-agent",
                "version": __version__,
                "api_version": "1",
                "endpoints": [
                    "/_hf_flight_recorder/metrics",
                    "/_hf_flight_recorder/history",
                    "/_hf_flight_recorder/events",
                    "/_hf_flight_recorder/health",
                    "/_hf_flight_recorder/version",
                ],
            })

        else:
            self._send_json({"error": "not found"}, 404)


# ── AgentServer ───────────────────────────────────────────────────────────────

class AgentServer:
    """
    Top-level object that wires together config, collector, heartbeat,
    snapshot store, security verifier, and HTTP server.

    Call start() once at process startup.
    """

    def __init__(self, cfg: Optional[AgentConfig] = None):
        self._cfg = cfg or AgentConfig.from_env()

    def start(self) -> None:
        global _store, _verifier, _cfg, _start_time
        _start_time = time.time()
        cfg = self._cfg
        _cfg = cfg

        # Snapshot store
        _store = SnapshotStore(
            maxlen=cfg.history_size,
            path=cfg.jsonl_path,
        )

        # Token verifier
        _verifier = TokenVerifier(ttl=cfg.token_ttl, enabled=cfg.verify_token)

        # Startup persistence + restart detection check (runs before anything else)
        _startup_check.run_once()

        # Heartbeat
        hb = Heartbeat(interval=cfg.heartbeat_interval, path=cfg.heartbeat_path)
        hb.start()

        # Collector thread
        t = threading.Thread(
            target=_collector_loop,
            args=(cfg, _store),
            daemon=True,
            name="hf-fr-collector",
        )
        t.start()

        # HTTP server
        self._http = HTTPServer((cfg.host, cfg.port), _Handler)
        srv = threading.Thread(
            target=self._http.serve_forever,
            daemon=True,
            name="hf-fr-http",
        )
        srv.start()

        log.info(
            "Agent v%s listening on http://%s:%d/_hf_flight_recorder/",
            __version__, cfg.host, cfg.port,
        )

    def stop(self) -> None:
        if hasattr(self, "_http"):
            self._http.shutdown()
