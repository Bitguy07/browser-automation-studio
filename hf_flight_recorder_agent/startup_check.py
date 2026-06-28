"""
startup_check.py — Boot-time persistence and restart detection for the agent.

Runs once when the agent starts. Writes a startup event to
/data/logs/hf_fr_startup.jsonl and reads back previous events to:

  1. Confirm /data/logs is writable and persistent
  2. Count prior restarts (any existing entries = restarted)
  3. Detect if the last shutdown was clean or abrupt
  4. Log the time gap since the last heartbeat (gap > threshold → likely OOM/kill)

The startup record is surfaced via /_hf_flight_recorder/health so the
recorder on your Ubuntu machine can see restart history.
"""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

log = logging.getLogger("hf_flight_recorder_agent.startup_check")

STARTUP_LOG  = "/data/logs/hf_fr_startup.jsonl"
HEARTBEAT_LOG = "/data/logs/hf_fr_heartbeat.jsonl"
ABRUPT_THRESHOLD_S = 30.0   # gap > this after last heartbeat → likely abrupt kill


@dataclass
class StartupRecord:
    ts: float
    iso: str
    pid: int
    restart_count: int           # how many previous entries in startup log
    seconds_since_last_heartbeat: Optional[float]
    last_heartbeat_iso: Optional[str]
    shutdown_type: str           # "clean" | "abrupt" | "first_boot" | "unknown"
    data_dir_writable: bool
    data_dir_path: str


def _last_heartbeat() -> Optional[dict]:
    """Read the last heartbeat record from disk, or None."""
    hb_path = Path(HEARTBEAT_LOG)
    if not hb_path.exists():
        return None
    try:
        lines = hb_path.read_text().splitlines()
        for line in reversed(lines):
            line = line.strip()
            if line:
                return json.loads(line)
    except Exception:
        pass
    return None


def _previous_startups() -> list[dict]:
    """Return all previous startup records from disk."""
    path = Path(STARTUP_LOG)
    if not path.exists():
        return []
    records = []
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except Exception:
        pass
    return records


def _write_record(record: StartupRecord) -> bool:
    """Append the startup record. Returns True if successful."""
    path = Path(STARTUP_LOG)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as f:
            f.write(json.dumps(asdict(record)) + "\n")
        return True
    except OSError as e:
        log.warning("Could not write startup record to %s: %s", path, e)
        return False


def run() -> StartupRecord:
    """
    Execute the startup check. Call once at agent boot.
    Returns a StartupRecord describing this boot.
    """
    now    = time.time()
    iso    = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))
    pid    = os.getpid()
    data_dir = Path(STARTUP_LOG).parent

    # ── 1. Check /data/logs is writable ──────────────────────────────
    probe = data_dir / ".hf_fr_probe"
    writable = False
    try:
        data_dir.mkdir(parents=True, exist_ok=True)
        probe.write_text("ok")
        probe.unlink()
        writable = True
    except OSError as e:
        log.error("/data/logs is NOT writable: %s", e)
        log.error(
            "Without a writable /data volume, metrics will NOT survive a Space restart. "
            "Ensure your Space has a persistent /data storage mount."
        )

    # ── 2. Previous startups → restart count ─────────────────────────
    previous = _previous_startups()
    restart_count = len(previous)

    # ── 3. Heartbeat gap → shutdown type ─────────────────────────────
    last_hb = _last_heartbeat()
    seconds_since: Optional[float] = None
    last_hb_iso: Optional[str] = None
    shutdown_type: str

    if restart_count == 0:
        shutdown_type = "first_boot"
    elif last_hb is None:
        shutdown_type = "unknown"
    else:
        last_hb_iso = last_hb.get("iso")
        last_hb_ts  = last_hb.get("ts", 0.0)
        seconds_since = round(now - last_hb_ts, 1)

        if seconds_since <= ABRUPT_THRESHOLD_S:
            shutdown_type = "clean"     # graceful SIGTERM before heartbeat could record a gap
        else:
            shutdown_type = "abrupt"    # large gap → OOM / external kill
            log.warning(
                "Last heartbeat was %.1fs ago — shutdown appears abrupt. "
                "This is consistent with an OOM kill or external platform termination.",
                seconds_since,
            )

    record = StartupRecord(
        ts=now,
        iso=iso,
        pid=pid,
        restart_count=restart_count,
        seconds_since_last_heartbeat=seconds_since,
        last_heartbeat_iso=last_hb_iso,
        shutdown_type=shutdown_type,
        data_dir_writable=writable,
        data_dir_path=str(data_dir),
    )

    ok = _write_record(record)

    log.info(
        "Startup check complete: restart_count=%d shutdown_type=%s "
        "data_writable=%s gap=%s",
        restart_count,
        shutdown_type,
        writable,
        f"{seconds_since:.1f}s" if seconds_since is not None else "n/a",
    )

    if not ok:
        log.warning(
            "Startup record could not be written. Persistence check failed. "
            "In-memory telemetry will still work, but post-mortem logs will be lost."
        )

    return record


# ── Module-level singleton so the server can expose it via /health ────────────

_startup_record: Optional[StartupRecord] = None


def get() -> Optional[StartupRecord]:
    return _startup_record


def run_once() -> StartupRecord:
    """Run the startup check exactly once per process lifetime."""
    global _startup_record
    if _startup_record is None:
        _startup_record = run()
    return _startup_record
