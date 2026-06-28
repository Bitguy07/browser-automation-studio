"""
collector.py — System metrics collector for the agent.
Reads from psutil, /proc/meminfo, and cgroup memory limits.
"""

from __future__ import annotations

import time
import os
import psutil
from dataclasses import dataclass, field, asdict
from typing import Optional


INTERESTING_PROCS = {
    "chrome", "chromium", "google-chrome",
    "ollama", "python3", "uvicorn", "fastapi",
    "Xvfb", "x11vnc", "websockify", "supervisord",
}


def _read_file(path: str) -> Optional[str]:
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return None


def _cgroup_memory_limit_mb() -> Optional[int]:
    """Read the container's hard memory limit from cgroups (v1 or v2)."""
    # cgroup v2
    v2 = _read_file("/sys/fs/cgroup/memory.max")
    if v2 and v2 != "max":
        try:
            return int(v2) // (1024 * 1024)
        except ValueError:
            pass

    # cgroup v1
    v1 = _read_file("/sys/fs/cgroup/memory/memory.limit_in_bytes")
    if v1:
        try:
            val = int(v1)
            # sentinel value meaning "no limit"
            if val < (1 << 62):
                return val // (1024 * 1024)
        except ValueError:
            pass

    return None


def _cgroup_memory_used_mb() -> Optional[int]:
    """Read current cgroup memory usage (v1 or v2)."""
    v2 = _read_file("/sys/fs/cgroup/memory.current")
    if v2:
        try:
            return int(v2) // (1024 * 1024)
        except ValueError:
            pass

    v1 = _read_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")
    if v1:
        try:
            return int(v1) // (1024 * 1024)
        except ValueError:
            pass

    return None


@dataclass
class ProcessInfo:
    name: str
    pid: int
    rss_mb: float
    cpu_percent: float
    status: str


@dataclass
class Snapshot:
    timestamp: float
    timestamp_iso: str

    # System RAM
    ram_total_mb: int
    ram_used_mb: int
    ram_available_mb: int
    ram_percent: float

    # cgroup limits (what HF actually gave the container)
    cgroup_limit_mb: Optional[int]
    cgroup_used_mb: Optional[int]

    # CPU
    cpu_percent: float
    cpu_count: int

    # Disk
    disk_total_gb: float
    disk_used_gb: float
    disk_free_gb: float
    disk_percent: float

    # Interesting processes
    processes: list = field(default_factory=list)

    # Health of the FastAPI endpoint (filled in by the server)
    fastapi_health: Optional[str] = None

    def to_dict(self) -> dict:
        d = asdict(self)
        return d


def collect(fastapi_health: Optional[str] = None) -> Snapshot:
    now = time.time()
    iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(now))

    mem = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.2)
    cpu_count = psutil.cpu_count(logical=True)

    disk = psutil.disk_usage("/")

    procs = []
    for p in psutil.process_iter(["name", "pid", "memory_info", "cpu_percent", "status"]):
        try:
            name = p.info["name"] or ""
            matched = any(iname in name for iname in INTERESTING_PROCS)
            if matched:
                rss = p.info["memory_info"].rss / (1024 * 1024) if p.info["memory_info"] else 0
                procs.append(ProcessInfo(
                    name=name,
                    pid=p.info["pid"],
                    rss_mb=round(rss, 1),
                    cpu_percent=round(p.info["cpu_percent"] or 0.0, 1),
                    status=p.info["status"] or "unknown",
                ))
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    return Snapshot(
        timestamp=now,
        timestamp_iso=iso,
        ram_total_mb=mem.total // (1024 * 1024),
        ram_used_mb=mem.used // (1024 * 1024),
        ram_available_mb=mem.available // (1024 * 1024),
        ram_percent=mem.percent,
        cgroup_limit_mb=_cgroup_memory_limit_mb(),
        cgroup_used_mb=_cgroup_memory_used_mb(),
        cpu_percent=cpu,
        cpu_count=cpu_count or 1,
        disk_total_gb=round(disk.total / (1024 ** 3), 2),
        disk_used_gb=round(disk.used / (1024 ** 3), 2),
        disk_free_gb=round(disk.free / (1024 ** 3), 2),
        disk_percent=disk.percent,
        processes=[asdict(p) for p in procs],
        fastapi_health=fastapi_health,
    )
