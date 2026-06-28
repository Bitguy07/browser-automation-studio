"""
heartbeat.py — Liveness heartbeat for the agent.

Writes a one-line JSON record to /data/logs/hf_fr_heartbeat.jsonl
every N seconds. If the Space is about to be killed, the heartbeat
stops — so the last heartbeat timestamp tells you exactly when the
container last had CPU time.

Runs as a daemon thread inside the agent process.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path
from typing import Optional

log = logging.getLogger("hf_flight_recorder_agent.heartbeat")

DEFAULT_PATH = "/data/logs/hf_fr_heartbeat.jsonl"
DEFAULT_INTERVAL = 5.0


class Heartbeat:
    """
    Writes:
        {"ts": 1719440000.123, "iso": "2026-06-26T23:13:20", "uptime_s": 42.1, "pid": 99}
    every `interval` seconds.
    """

    def __init__(
        self,
        interval: float = DEFAULT_INTERVAL,
        path: str = DEFAULT_PATH,
    ):
        self._interval = interval
        self._path = Path(path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._start = time.time()
        self._running = False
        self._thread: Optional[threading.Thread] = None

    def _beat(self) -> None:
        import os
        now = time.time()
        record = {
            "ts": round(now, 3),
            "iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "uptime_s": round(now - self._start, 1),
            "pid": os.getpid(),
        }
        try:
            with self._path.open("a") as f:
                f.write(json.dumps(record) + "\n")
        except OSError as e:
            log.warning("Heartbeat write failed: %s", e)

    def _loop(self) -> None:
        log.info("Heartbeat started (interval=%.1fs, path=%s)", self._interval, self._path)
        while self._running:
            self._beat()
            time.sleep(self._interval)

    def start(self) -> None:
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True, name="hf-fr-heartbeat")
        self._thread.start()

    def stop(self) -> None:
        self._running = False

    def last_beat_iso(self) -> Optional[str]:
        """Read the last heartbeat timestamp from the log file."""
        if not self._path.exists():
            return None
        try:
            with self._path.open() as f:
                lines = [l.strip() for l in f if l.strip()]
            if not lines:
                return None
            last = json.loads(lines[-1])
            return last.get("iso")
        except Exception:
            return None
