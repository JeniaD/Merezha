from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class BaseHandler(ABC):
    @abstractmethod
    def can_handle(self, payload: dict[str, Any]) -> bool:
        ...

    @abstractmethod
    def solve(self, payload: dict[str, Any], verification_params: bytes) -> bytes:
        """Return ABI-encoded bytes for submitResult(result)."""
        ...
