from __future__ import annotations

from typing import Any

from .base import BaseHandler
from .hash_handler import HashHandler
from .prefix_handler import PrefixHandler
from .zkml_handler import ZkMlHandler

HANDLERS: list[BaseHandler] = [
    HashHandler(),
    PrefixHandler(),
    ZkMlHandler(),
]


def get_handler(payload: dict[str, Any]) -> BaseHandler | None:
    for h in HANDLERS:
        if h.can_handle(payload):
            return h
    return None
