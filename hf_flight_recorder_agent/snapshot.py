"""
snapshot.py — Rolling snapshot history for the agent.

Maintains the last N snapshots in memory and on disk.
The HTTP server exposes this via /_hf_flight_recorder/history.

This is separate from server.py's _RollingBuffer so that the data
model can be extended without touching the HTTP layer.
"""

from __future__ import annotations

import json
import logging
import threading
from collections import deque
from pathlib import Path
from typing import Optional

log = logging.getLogger("hf_flight_recorder_agent.snapshot")

MAX_IN_MEMORY = 600          # ~10 min @ 1/s
JSONL_TAIL = 3600            # max lines kept in the JSONL history file


class SnapshotStore:
    """
    Thread-safe rolling snapshot store.

    Attributes
    ----------
    maxlen  Maximum number of snapshots kept in memory
    path    Optional path for the persistent JSONL file
    """

    def __init__(self, maxlen: int = MAX_IN_MEMORY, path: Optional[str] = None):
        self._buf: deque[dict] = deque(maxlen=maxlen)
        self._lock = threading.Lock()
        self._path = Path(path) if path else None
        if self._path:
            self._path.parent.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------ #
    #  Write
    # ------------------------------------------------------------------ #

    def push(self, snapshot: dict) -> None:
        with self._lock:
            self._buf.append(snapshot)
        if self._path:
            self._write_disk(snapshot)

    def _write_disk(self, snapshot: dict) -> None:
        try:
            with self._path.open("a") as f:
                f.write(json.dumps(snapshot) + "\n")
            self._maybe_rotate()
        except OSError as e:
            log.warning("Snapshot disk write failed: %s", e)

    def _maybe_rotate(self) -> None:
        """Keep the on-disk file from growing unbounded."""
        try:
            lines = self._path.read_text().splitlines()
            if len(lines) > JSONL_TAIL:
                trimmed = lines[-JSONL_TAIL:]
                self._path.write_text("\n".join(trimmed) + "\n")
        except OSError:
            pass

    # ------------------------------------------------------------------ #
    #  Read
    # ------------------------------------------------------------------ #

    def latest(self) -> Optional[dict]:
        with self._lock:
            return self._buf[-1] if self._buf else None

    def last_n(self, n: int) -> list[dict]:
        with self._lock:
            return list(self._buf)[-n:]

    def all(self) -> list[dict]:
        with self._lock:
            return list(self._buf)

    def stats(self) -> dict:
        with self._lock:
            count = len(self._buf)
        if count == 0:
            return {"count": 0}
        latest = self.latest() or {}
        return {
            "count": count,
            "latest_ts": latest.get("timestamp_iso", ""),
            "disk_path": str(self._path) if self._path else None,
        }

    # ------------------------------------------------------------------ #
    #  RAM trend analysis (used by the server's /events endpoint)
    # ------------------------------------------------------------------ #

    def ram_trend(self, window: int = 30) -> Optional[float]:
        """
        Return MB/sample slope over the last `window` samples.
        Positive = growing. None if insufficient data.
        """
        snapshots = self.last_n(window)
        used = [s.get("ram_used_mb") for s in snapshots if s.get("ram_used_mb") is not None]
        if len(used) < 5:
            return None
        n = len(used)
        xs = list(range(n))
        x_mean = sum(xs) / n
        y_mean = sum(used) / n
        num = sum((xs[i] - x_mean) * (used[i] - y_mean) for i in range(n))
        den = sum((xs[i] - x_mean) ** 2 for i in range(n))
        return round(num / den, 3) if den else 0.0
