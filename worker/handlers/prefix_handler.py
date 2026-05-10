from __future__ import annotations

from typing import Any

from eth_abi import decode
from web3 import Web3

from .base import BaseHandler

MAX_PREFIX_SEARCH = 5_000_000


class PrefixHandler(BaseHandler):
    def can_handle(self, payload: dict[str, Any]) -> bool:
        return payload.get("type") == "prefix"

    def solve(self, payload: dict[str, Any], verification_params: bytes) -> bytes:
        (prefix,) = decode(["bytes"], verification_params)
        if len(prefix) == 0:
            return b"\x00"

        for i in range(MAX_PREFIX_SEARCH):
            candidate = i.to_bytes(32, "big")
            h = Web3.keccak(candidate)
            if h[: len(prefix)] == prefix:
                return h

        raise RuntimeError(
            f"prefix search exceeded {MAX_PREFIX_SEARCH} iterations; shorten required prefix"
        )
