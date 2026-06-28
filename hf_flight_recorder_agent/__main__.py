"""
__main__.py — Run the agent as a standalone process.

Usage:
    python -m hf_flight_recorder_agent
    hf-flight-recorder-agent          # after pip install

All settings can also be set via environment variables — see config.py.
"""

from __future__ import annotations

import argparse
import logging
import signal
import sys
import time

from .config import AgentConfig


def main() -> None:
    parser = argparse.ArgumentParser(description="HF Flight Recorder Agent")
    parser.add_argument("--host", default=None, help="Bind host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=None, help="Bind port (default: 9999)")
    parser.add_argument("--collect-interval", type=float, default=None,
                        help="Seconds between snapshots (default: 1.0)")
    parser.add_argument("--history-size", type=int, default=None,
                        help="Max snapshots in memory (default: 600)")
    parser.add_argument("--verify-token", action="store_true", default=None,
                        help="Require HF Bearer token on every request")
    parser.add_argument("--heartbeat-interval", type=float, default=None,
                        help="Heartbeat write interval in seconds (default: 5)")
    parser.add_argument("--log-level", default=None,
                        help="Logging level: DEBUG/INFO/WARNING (default: INFO)")
    args = parser.parse_args()

    # Build config from env, then apply non-None CLI overrides
    overrides = {k: v for k, v in vars(args).items() if v is not None}
    cfg = AgentConfig.from_env()
    for k, v in overrides.items():
        attr = k.replace("-", "_")
        if hasattr(cfg, attr):
            setattr(cfg, attr, v)

    logging.basicConfig(
        level=getattr(logging, cfg.log_level, logging.INFO),
        format="%(asctime)s [AGENT] %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    log = logging.getLogger("hf_flight_recorder_agent")

    from .server import AgentServer
    agent = AgentServer(cfg=cfg)
    agent.start()

    log.info("Agent started (v%s). Ctrl-C or SIGTERM to stop.", cfg)

    def _shutdown(sig, frame):
        log.info("Signal %s — shutting down.", sig)
        agent.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    while True:
        time.sleep(1)


if __name__ == "__main__":
    main()
