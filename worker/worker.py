#!/usr/bin/env python3
"""Poll ComputeMarketplace for TaskPosted events and attempt hash/prefix (and optional zkml) tasks."""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path
from typing import Any

from eth_account import Account
from web3 import Web3
from web3.contract.contract import Contract
from web3.types import EventData

from handlers import get_handler

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("merezha-worker")

STATUS_OPEN = 0
STATUS_SUBMITTED = 1


def _add_fees_and_gas(w3: Web3, tx: dict[str, Any]) -> None:
    """Set gas limit and either EIP-1559 fees (London+) or legacy gasPrice."""
    block = w3.eth.get_block("latest")
    base = block.get("baseFeePerGas")
    if base is not None:
        tip = Web3.to_wei(2, "gwei")
        tx["maxPriorityFeePerGas"] = tip
        tx["maxFeePerGas"] = base * 2 + tip
    else:
        tx["gasPrice"] = w3.eth.gas_price
    tx["gas"] = w3.eth.estimate_gas(tx)


def _signed_raw_bytes(signed: Any) -> bytes:
    """eth-account uses rawTransaction (v0.11); newer stacks may use raw_transaction."""
    raw = getattr(signed, "raw_transaction", None) or getattr(signed, "rawTransaction", None)
    if raw is None:
        raise TypeError("signed tx has no raw_transaction / rawTransaction")
    return raw


def load_abi() -> list[dict[str, Any]]:
    root = Path(__file__).resolve().parent
    path = root / "abis" / "marketplace.json"
    return json.loads(path.read_text())


def decode_payload(raw: bytes) -> dict[str, Any]:
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError(f"invalid payload JSON: {e}") from e


def process_task(
    w3: Web3,
    marketplace: Contract,
    account: Account,
    log_entry: EventData,
    post_task_sleep: float = 0.0,
) -> None:
    args = log_entry["args"]
    task_id = args["taskId"]
    payload_raw: bytes = args["payload"]
    paced = False

    try:
        task = marketplace.functions.getTask(task_id).call()
    except Exception as e:
        log.warning("getTask(%s) failed: %s", task_id, e)
        return

    status = int(task[9])
    deadline = int(task[7])
    now = int(w3.eth.get_block("latest")["timestamp"])

    if status == STATUS_SUBMITTED:
        worker_addr = task[1]
        if worker_addr.lower() == account.address.lower():
            try:
                tx = marketplace.functions.finalize(task_id).build_transaction(
                    {
                        "from": account.address,
                        "nonce": w3.eth.get_transaction_count(account.address, "pending"),
                        "chainId": w3.eth.chain_id,
                    }
                )
                _add_fees_and_gas(w3, tx)
                signed = w3.eth.account.sign_transaction(tx, account.key)
                h = w3.eth.send_raw_transaction(_signed_raw_bytes(signed))
                w3.eth.wait_for_transaction_receipt(h)
                log.info("finalized task %s tx=%s", task_id, h.hex())
                paced = True
            except Exception as e:
                log.warning("finalize(%s): %s", task_id, e)
        if post_task_sleep > 0 and paced:
            time.sleep(post_task_sleep)
        return

    if status != STATUS_OPEN:
        return
    if now > deadline:
        return

    try:
        payload = decode_payload(payload_raw)
    except ValueError as e:
        log.warning("task %s: %s", task_id, e)
        return

    handler = get_handler(payload)
    if handler is None:
        log.debug("task %s: no handler for type %r", task_id, payload.get("type"))
        return

    vparams: bytes = task[4]
    try:
        result_bytes = handler.solve(payload, vparams)
    except Exception as e:
        log.warning("task %s solve skipped: %s", task_id, e)
        return

    try:
        tx = marketplace.functions.submitResult(task_id, result_bytes).build_transaction(
            {
                "from": account.address,
                "nonce": w3.eth.get_transaction_count(account.address, "pending"),
                "chainId": w3.eth.chain_id,
            }
        )
        _add_fees_and_gas(w3, tx)
        signed = w3.eth.account.sign_transaction(tx, account.key)
        h = w3.eth.send_raw_transaction(_signed_raw_bytes(signed))
        w3.eth.wait_for_transaction_receipt(h)
        log.info("submitted task %s tx=%s", task_id, h.hex())
    except Exception as e:
        log.warning("submitResult(%s): %s", task_id, e)
        return

    try:
        tx = marketplace.functions.finalize(task_id).build_transaction(
            {
                "from": account.address,
                "nonce": w3.eth.get_transaction_count(account.address, "pending"),
                "chainId": w3.eth.chain_id,
            }
        )
        _add_fees_and_gas(w3, tx)
        signed = w3.eth.account.sign_transaction(tx, account.key)
        h = w3.eth.send_raw_transaction(_signed_raw_bytes(signed))
        w3.eth.wait_for_transaction_receipt(h)
        log.info("finalized task %s tx=%s", task_id, h.hex())
        paced = True
    except Exception as e:
        log.warning("finalize(%s): %s", task_id, e)

    if post_task_sleep > 0 and paced:
        time.sleep(post_task_sleep)


def main() -> None:
    p = argparse.ArgumentParser(description="Merezha marketplace worker")
    p.add_argument("--rpc-url", required=True, help="HTTP RPC (Anvil or Sepolia)")
    p.add_argument("--private-key", required=True, help="Worker hex private key (0x…)")
    p.add_argument("--marketplace", required=True, help="ComputeMarketplace address")
    p.add_argument("--poll-interval", type=float, default=5.0)
    p.add_argument(
        "--from-block",
        type=int,
        default=0,
        help="First block to scan for TaskPosted (set to deploy block after restart)",
    )
    p.add_argument(
        "--post-task-sleep",
        type=float,
        default=3.0,
        help="Seconds to sleep after sending txs for a task (0 to disable; default 3 for demo pacing)",
    )
    args = p.parse_args()

    key = args.private_key.strip()
    if not key.startswith("0x"):
        key = "0x" + key

    w3 = Web3(Web3.HTTPProvider(args.rpc_url, request_kwargs={"timeout": 60}))
    if not w3.is_connected():
        log.error("RPC not connected")
        sys.exit(1)

    account = Account.from_key(key)
    abi = load_abi()
    marketplace = w3.eth.contract(
        address=Web3.to_checksum_address(args.marketplace),
        abi=abi,
    )

    last = max(0, args.from_block - 1)
    log.info(
        "worker %s polling %s from block %s",
        account.address,
        args.marketplace,
        last + 1,
    )

    while True:
        try:
            latest = w3.eth.block_number
            if latest > last:
                from_b = last + 1
                logs = marketplace.events.TaskPosted.get_logs(
                    fromBlock=from_b,
                    toBlock=latest,
                )
                if logs:
                    log.info(
                        "blocks %s-%s: %s TaskPosted event(s)",
                        from_b,
                        latest,
                        len(logs),
                    )
                for entry in logs:
                    try:
                        process_task(
                            w3,
                            marketplace,
                            account,
                            entry,
                            post_task_sleep=args.post_task_sleep,
                        )
                    except Exception as e:
                        log.exception("task loop error: %s", e)
                last = latest
        except Exception as e:
            log.exception("poll error: %s", e)

        time.sleep(args.poll_interval)


if __name__ == "__main__":
    main()
