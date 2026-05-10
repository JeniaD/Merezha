from __future__ import annotations

from pathlib import Path
from typing import Any

from eth_abi import encode

from .base import BaseHandler

# Default relative to worker/ directory
ARTIFACTS_DIR = Path(__file__).resolve().parent.parent / "ezkl_artifacts"


class ZkMlHandler(BaseHandler):
    """Requires EZKL + ONNX pipeline (README §8). Disabled until artifacts exist."""

    def __init__(self, artifacts_dir: Path | None = None) -> None:
        self._dir = artifacts_dir or ARTIFACTS_DIR

    def can_handle(self, payload: dict[str, Any]) -> bool:
        if payload.get("type") != "zkml":
            return False
        required = [
            self._dir / "compiled_model.ezkl",
            self._dir / "pk.key",
            self._dir / "vk.key",
            self._dir / "settings.json",
        ]
        return all(p.exists() for p in required)

    def solve(self, payload: dict[str, Any], verification_params: bytes) -> bytes:
        try:
            import ezkl  # noqa: F401
        except ImportError as e:
            raise RuntimeError("Install ezkl and run the EZKL setup pipeline (README §8).") from e

        _ = verification_params
        _ = payload
        raise NotImplementedError(
            "ZkMlHandler.solve: wire ezkl.gen_witness + ezkl.prove + abi.encode(proof, instances) "
            "once your circuit is set up; see README."
        )
