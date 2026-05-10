from __future__ import annotations

from typing import Any

from .base import BaseHandler


class HashHandler(BaseHandler):
    def can_handle(self, payload: dict[str, Any]) -> bool:
        return payload.get("type") == "hash"

    def solve(self, payload: dict[str, Any], verification_params: bytes) -> bytes:
        raw = payload.get("input")
        if raw is None:
            raise ValueError('hash task requires payload["input"] (string)')
        if not isinstance(raw, str):
            raw = str(raw)
        return raw.encode("utf-8")
