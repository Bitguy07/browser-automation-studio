"""
security.py — Token verification for the agent's HTTP endpoints.

For private Spaces the agent should only respond to requests that
carry a valid Hugging Face Bearer token.  We verify by calling the
HF /api/whoami endpoint — if it returns 200 the token is valid.

Verification results are cached for `ttl` seconds to avoid hammering
the HF API on every metrics poll.
"""

from __future__ import annotations

import logging
import time
from threading import Lock
from typing import Optional
from urllib.request import urlopen, Request
from urllib.error import URLError

log = logging.getLogger("hf_flight_recorder_agent.security")

WHOAMI_URL = "https://huggingface.co/api/whoami-v2"
_CACHE_TTL = 60.0       # seconds a verified token stays valid


class TokenVerifier:
    """
    Caches token → (is_valid, expiry) so that every HTTP request
    doesn't hit the HF API.
    """

    def __init__(self, ttl: float = _CACHE_TTL, enabled: bool = True):
        self._ttl = ttl
        self._enabled = enabled
        self._cache: dict[str, tuple[bool, float]] = {}
        self._lock = Lock()

    def is_valid(self, token: str) -> bool:
        if not self._enabled:
            return True
        if not token:
            return False

        with self._lock:
            cached = self._cache.get(token)
            if cached:
                valid, expiry = cached
                if time.time() < expiry:
                    return valid

        valid = self._verify(token)

        with self._lock:
            self._cache[token] = (valid, time.time() + self._ttl)

        return valid

    def _verify(self, token: str) -> bool:
        try:
            req = Request(WHOAMI_URL, headers={"Authorization": f"Bearer {token}"})
            with urlopen(req, timeout=5) as resp:
                return resp.status == 200
        except URLError as e:
            log.debug("Token verification failed (network): %s", e.reason)
            # Fail open on network errors so the agent doesn't lock itself out
            return True
        except Exception as e:
            log.debug("Token verification error: %s", e)
            return True

    def invalidate(self, token: str) -> None:
        with self._lock:
            self._cache.pop(token, None)


def extract_bearer(auth_header: Optional[str]) -> Optional[str]:
    """Extract the token from 'Authorization: Bearer <token>'."""
    if not auth_header:
        return None
    parts = auth_header.strip().split()
    if len(parts) >= 2 and parts[0].lower() == "bearer":
        return parts[1]
    return None
