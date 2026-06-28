"""
config.py — Configuration for the hf-flight-recorder-agent.

All settings can be overridden by environment variables.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass
class AgentConfig:
    # ── HTTP server ────────────────────────────────────────────────────
    host: str = "127.0.0.1"
    port: int = 9999

    # ── Collection ────────────────────────────────────────────────────
    collect_interval: float = 1.0       # seconds between snapshots
    fastapi_health_url: str = "http://127.0.0.1:7860/health"
    fastapi_health_timeout: float = 2.0

    # ── Retention ─────────────────────────────────────────────────────
    history_size: int = 600             # snapshots kept in memory (~10 min @ 1/s)
    jsonl_path: str = "/data/logs/hf_flight_recorder_metrics.jsonl"
    heartbeat_path: str = "/data/logs/hf_fr_heartbeat.jsonl"
    heartbeat_interval: float = 5.0

    # ── Security ──────────────────────────────────────────────────────
    verify_token: bool = False          # set True to require HF Bearer token
    token_ttl: float = 60.0            # seconds to cache verified tokens

    # ── Logging ───────────────────────────────────────────────────────
    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> "AgentConfig":
        return cls(
            host=os.environ.get("HF_FR_AGENT_HOST", "127.0.0.1"),
            port=int(os.environ.get("HF_FR_AGENT_PORT", 9999)),
            collect_interval=float(os.environ.get("HF_FR_COLLECT_INTERVAL", 1.0)),
            fastapi_health_url=os.environ.get(
                "HF_FR_FASTAPI_HEALTH_URL", "http://127.0.0.1:7860/health"
            ),
            fastapi_health_timeout=float(os.environ.get("HF_FR_HEALTH_TIMEOUT", 2.0)),
            history_size=int(os.environ.get("HF_FR_HISTORY_SIZE", 600)),
            jsonl_path=os.environ.get(
                "HF_FR_JSONL_PATH", "/data/logs/hf_flight_recorder_metrics.jsonl"
            ),
            heartbeat_path=os.environ.get(
                "HF_FR_HEARTBEAT_PATH", "/data/logs/hf_fr_heartbeat.jsonl"
            ),
            heartbeat_interval=float(os.environ.get("HF_FR_HEARTBEAT_INTERVAL", 5.0)),
            verify_token=os.environ.get("HF_FR_VERIFY_TOKEN", "").lower()
                         in ("1", "true", "yes"),
            token_ttl=float(os.environ.get("HF_FR_TOKEN_TTL", 60.0)),
            log_level=os.environ.get("HF_FR_LOG_LEVEL", "INFO").upper(),
        )
