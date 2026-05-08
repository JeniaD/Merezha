# Merezha — Decentralized Compute Marketplace with Pluggable Verification

> DMBLOCK Assignment 2 · Digital Currencies and Blockchain

---

## Table of Contents

1. [Project Description](#1-project-description)
2. [The Core Idea](#2-the-core-idea)
3. [Architecture Overview](#3-architecture-overview)
4. [Repository Structure](#4-repository-structure)
5. [Smart Contract Specifications](#5-smart-contract-specifications)
6. [Worker Specification](#6-worker-specification)
7. [Frontend Specification](#7-frontend-specification)
8. [zkML Verifier Specification](#8-zkml-verifier-specification)
9. [Tech Stack](#9-tech-stack)
10. [Development Phases](#10-development-phases)
11. [Deployment Details](#11-deployment-details)
12. [Setup Instructions](#12-setup-instructions)
13. [Known Limitations](#13-known-limitations)
14. [What We Learned](#14-what-we-learned)
15. [Use of AI Tools](#15-use-of-ai-tools)
16. [Conclusion](#16-conclusion)

---

## 1. Project Description

**Merezha** is a decentralized compute network on an EVM-compatible blockchain. Anyone can post a computational task with a reward denominated in ETH. Anyone else can act as a worker, execute the task off-chain, and submit the result on-chain to claim the reward.

Originally conceived as an academic **computational** network: to make it easier for research groups to collaborate and run large workloads on shared, distributed infrastructure. Compared with fully anonymous grids, participation can stay more accountable (known institutions or members), which mitigates some security concerns that anonymity introduces. The same design also works as an open marketplace where anyone pays ETH for compute. This project is a proof of concept of that general idea.

The key design question any such system must answer is: *how do you verify that a submitted result is actually correct?* Most existing systems hard-code a single answer to this question, which means the protocol becomes stale as verification technology evolves.

Merezha's answer is a **pluggable verifier interface**. The marketplace contract has no opinion about how verification works. Instead, each task references an external `IVerifier` contract. Verification logic lives entirely in that contract. When a new verification method is invented — a new zero-knowledge proof system, a new ML attestation scheme, anything — a new verifier contract is deployed and registered. The marketplace supports it immediately, with no upgrade, no migration, no governance vote.

This is demonstrated concretely with three shipped verifiers:

- **HashVerifier** — the poster commits `keccak256(expected_answer)`; the worker must find the exact answer. Simple and trustless.
- **PrefixVerifier** — the result must start with a given byte sequence. Models proof-of-work style tasks.
- **ZkMlVerifier** — wraps an EZKL-generated Solidity verifier. The worker runs an ONNX model off-chain, generates a zero-knowledge proof, and submits it. The on-chain verifier proves the worker ran *this exact model* on *this exact input* and got *this exact output* — without re-running the model on-chain.

---

## 2. The Core Idea

### The Verifier's Dilemma

In any decentralized compute system, verification is the hard problem. The naive solution — re-execute every submitted result on-chain — is either prohibitively expensive (ML inference) or simply impossible (tasks that take minutes of CPU time).

### Merezha's Solution

Separate the *verification strategy* from the *marketplace protocol*. The marketplace only knows:

```
given (verificationParams: bytes, result: bytes) → is this result correct? (bool)
```

Everything else is the verifier's business. This separation means:

- The marketplace contract never needs upgrading as verification technology advances.
- Verifiers are composable — a verifier could even chain to other verifiers.
- Task posters choose the trust model appropriate for their task.

### Real-World Motivation

Today, zkML (zero-knowledge proofs of machine learning inference) is an active research area. Libraries like EZKL can already generate Solidity verifiers for small ONNX models. Within a few years, proving times will drop enough for production use. A marketplace built today with pluggable verification adopts zkML the day it becomes viable — not the day the protocol team ships an upgrade.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        BLOCKCHAIN (Sepolia)                      │
│                                                                  │
│  ┌──────────────────┐     registers      ┌───────────────────┐  │
│  │ VerifierRegistry │◄───────────────────│  HashVerifier     │  │
│  │                  │                    │  PrefixVerifier   │  │
│  │  name → address  │                    │  ZkMlVerifier     │  │
│  └────────┬─────────┘                    └───────────────────┘  │
│           │ looks up                              ▲              │
│           ▼                                       │ IVerifier    │
│  ┌──────────────────────────────────────┐         │              │
│  │        ComputeMarketplace            │─────────┘              │
│  │                                      │  calls verify()        │
│  │  postTask(payload, verifier, params,│                        │
│  │           deadline, refundDeadline)  │                        │
│  │  submitResult(taskId, result)        │                        │
│  │  finalize(taskId)                    │                        │
│  │  refund(taskId)                      │                        │
│  │                                      │                        │
│  │  escrow: taskId → ETH                │                        │
│  └──────────────────────────────────────┘                        │
└────────────┬──────────────────────┬────────────────────────────-┘
             │                      │
    reads events               reads events
    submits txs                submits txs
             │                      │
  ┌──────────▼──────┐    ┌──────────▼────────────────────────────┐
  │   FRONTEND       │    │   WORKER PROCESSES (Python)           │
  │  (HTML/CSS/JS)   │    │                                       │
  │  ethers.js       │    │  worker.py --wallet <key>             │
  │                  │    │  ┌────────────────────────────────┐   │
  │  - Connect wallet│    │  │ 1. Subscribe to TaskPosted     │   │
  │  - Browse tasks  │    │  │ 2. Parse task payload (JSON)   │   │
  │  - Post task     │    │  │ 3. Execute computation locally │   │
  │  - View history  │    │  │    (hash / prefix / ML+proof)  │   │
  │  - See tx status │    │  │ 4. submitResult(taskId, result)│   │
  └──────────────────┘    │  │ 5. finalize(taskId)            │   │
                          │  └────────────────────────────────┘   │
                          └───────────────────────────────────────┘
```

### Data Flow: Task Lifecycle

```
POSTER                    MARKETPLACE              WORKER
  │                           │                      │
  │── postTask(payload,  ────►│                      │
  │   verifierAddr,           │                      │
  │   verifyParams,           │◄─── TaskPosted ─────►│
  │   deadline) + ETH         │       event           │
  │                           │                      │── compute(payload)
  │                           │                      │── proof (if zkML)
  │                           │◄── submitResult ─────│
  │                           │    (taskId, result)  │
  │                           │                      │
  │                           │◄── finalize ─────────│
  │                           │    (taskId)          │
  │                           │                      │
  │                           │── verifier.verify() ─►│ (on-chain)
  │                           │◄── true / false       │
  │                           │                      │
  │                           │── transfer reward ──►worker wallet
  │                           │   (if true)
  │                           │── task reopens
  │                           │   (if false, new worker can try)
```

### Task States

```
OPEN → SUBMITTED → FINALIZED (paid)
  ↑         │
  └─────────┘  (wrong result: task reopens, new worker can try)
  
OPEN → EXPIRED → REFUNDED (poster reclaims ETH after deadline)
```

---

## 4. Repository Structure

```
merezha/
├── contracts/                    # Solidity smart contracts
│   ├── interfaces/
│   │   └── IVerifier.sol         # Core verifier interface
│   ├── verifiers/
│   │   ├── HashVerifier.sol      # keccak256 commitment verifier
│   │   ├── PrefixVerifier.sol    # byte prefix verifier
│   │   └── ZkMlVerifier.sol      # wraps EZKL-generated verifier
│   ├── VerifierRegistry.sol      # on-chain verifier registry
│   ├── ComputeMarketplace.sol    # core marketplace contract
│   └── ezkl/
│       └── IrisVerifier.sol      # EZKL-generated (do not edit manually)
│
├── foundry.toml                  # Forge: build, test, script runner
├── script/                       # Foundry deployment scripts (Solidity)
│   ├── Deploy.s.sol              # deploys core contracts
│   └── RegisterVerifiers.s.sol   # registers verifiers in the registry
├── test/                         # Forge tests (Solidity .t.sol)
│   ├── ComputeMarketplace.t.sol
│   ├── HashVerifier.t.sol
│   └── ZkMlVerifier.t.sol
│
├── worker/                       # Python worker process
│   ├── worker.py                 # main worker entrypoint
│   ├── handlers/
│   │   ├── hash_handler.py       # handles hash tasks
│   │   ├── prefix_handler.py     # handles prefix tasks
│   │   └── zkml_handler.py       # runs ONNX model + generates proof
│   ├── models/
│   │   └── iris.onnx             # demo ONNX model (Iris classifier)
│   ├── ezkl_artifacts/           # compiled EZKL circuit artifacts
│   │   ├── settings.json
│   │   ├── compiled_model.ezkl
│   │   ├── pk.key
│   │   └── vk.key
│   └── requirements.txt
│
├── frontend/
│   └── index.html                # single-file frontend
│
├── .env.example
└── README.md
```

---

## 5. Smart Contract Specifications

### 5.1 `IVerifier.sol`

The single interface that all verifiers must implement.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVerifier {
    /// @notice Verifies that `result` is a valid answer for a task
    ///         whose verification parameters are `params`.
    /// @param  params  ABI-encoded parameters set by the task poster.
    ///                 Interpretation is entirely up to the verifier.
    /// @param  result  ABI-encoded result submitted by the worker.
    ///                 Interpretation is entirely up to the verifier.
    /// @return True if the result is accepted, false otherwise.
    function verify(
        bytes calldata params,
        bytes calldata result
    ) external view returns (bool);
}
```

**Rules for all verifier implementations:**
- Must be a `view` function — no state changes allowed.
- Must never revert on malformed input; return `false` instead.
- Must be deterministic.

---

### 5.2 `HashVerifier.sol`

Verifier for tasks where the poster knows the correct answer in advance and commits its hash.

**Encoding:**
- `params`: `abi.encode(bytes32 expectedHash)` where `expectedHash = keccak256(correctAnswer)`
- `result`: the raw answer bytes

**Logic:** `keccak256(result) == expectedHash`

**Example task payload (JSON stored off-chain):**
```json
{
  "type": "hash",
  "description": "Compute SHA-256 of the string 'hello world'",
  "input": "hello world"
}
```
The poster pre-computes `keccak256("hello world")` and stores it as `params`. The worker submits the UTF-8 bytes of `"hello world"` as `result`.

---

### 5.3 `PrefixVerifier.sol`

Verifier for tasks where the result must begin with a specific byte sequence. Models proof-of-work style tasks.

**Encoding:**
- `params`: `abi.encode(bytes prefix)`
- `result`: any bytes

**Logic:** `result.length >= prefix.length && result[0..prefix.length] == prefix`

**Example task payload:**
```json
{
  "type": "prefix",
  "description": "Find any string whose keccak256 starts with 0x0000",
  "requiredPrefix": "0x0000"
}
```

---

### 5.4 `ZkMlVerifier.sol`

Wraps an EZKL-generated Solidity verifier. Proves that a specific ONNX model was run on a specific input and produced a specific output.

**Encoding:**
- `params`: `abi.encode(uint256[] expectedOutput)` — the expected quantized model output
- `result`: `abi.encode(bytes proof, uint256[] instances)` — the ZK proof and public instances

**Logic:** Decodes the proof and instances from `result`, then calls `ezkl.verifyProof(proof, instances)` on the EZKL-generated contract. Additionally checks that `instances` includes the expected output values from `params`.

**Constructor:** Takes address of the deployed EZKL verifier contract.

---

### 5.5 `VerifierRegistry.sol`

A simple on-chain registry mapping human-readable names to verifier addresses.

**State:**
```solidity
mapping(string => address) public verifiers;
string[] public verifierNames;
address public owner;
```

**Functions:**
```solidity
// Register a new verifier (owner only)
function register(string calldata name, address verifier) external onlyOwner;

// Remove a verifier (owner only)
function unregister(string calldata name) external onlyOwner;

// Get verifier address by name. Reverts if not found.
function get(string calldata name) external view returns (address);

// Returns all registered names
function getAllNames() external view returns (string[] memory);
```

**Events:**
```solidity
event VerifierRegistered(string name, address verifier);
event VerifierUnregistered(string name);
```

---

### 5.6 `ComputeMarketplace.sol`

The core marketplace contract. Holds ETH in escrow, coordinates task lifecycle.

**Constructor:** `constructor(address registry_, address forfeitSink_)`
- `registry_`: optional `VerifierRegistry` for `postTaskWithRegisteredVerifier`; use `address(0)` if unused.
- `forfeitSink_`: recipient of escrow for abandoned `Open` tasks after the refund window; use `address(0)` for the default burn address (`0x…dEaD`).

**Structs:**
```solidity
enum TaskStatus { Open, Submitted, Finalized, Refunded, Forfeited }

struct Task {
    address poster;
    address worker;
    address verifier;         // must be a contract (has code)
    bytes payload;
    bytes verificationParams;
    bytes submittedResult;
    uint256 reward;
    uint256 deadline;          // last moment workers may submitResult
    uint256 refundDeadline;    // last moment poster may refund (must be > deadline)
    TaskStatus status;
}
```

**State:**
```solidity
VerifierRegistry public immutable verifierRegistry;
address public immutable forfeitSink;
mapping(uint256 => Task) public tasks;
uint256 public nextTaskId;
```

**Functions:**
```solidity
function postTask(
    bytes calldata payload,
    address verifier,
    bytes calldata verificationParams,
    uint256 deadline,
    uint256 refundDeadline
) external payable returns (uint256 taskId);

function postTaskWithRegisteredVerifier(
    bytes calldata payload,
    string calldata verifierName,
    bytes calldata verificationParams,
    uint256 deadline,
    uint256 refundDeadline
) external payable returns (uint256 taskId);

/// Poster cancels while Open and before deadline; full escrow returned.
function cancelOpen(uint256 taskId) external;

function submitResult(uint256 taskId, bytes calldata result) external;

function finalize(uint256 taskId) external;

/// Poster refunds while Open, after deadline, and not after refundDeadline.
function refund(uint256 taskId) external;

/// If still Open after refundDeadline, anyone sends escrow to forfeitSink (no poster refund).
function forfeitAbandonedTask(uint256 taskId) external;

/// Reverts if taskId >= nextTaskId.
function getTask(uint256 taskId) external view returns (Task memory);
```

**Events:**
```solidity
event TaskPosted(
    uint256 indexed taskId,
    address indexed poster,
    address indexed verifier,
    uint256 reward,
    uint256 deadline,
    uint256 refundDeadline,
    bytes payload
);
event ResultSubmitted(uint256 indexed taskId, address indexed worker);
event TaskFinalized(uint256 indexed taskId, address indexed worker, bool success);
event TaskRefunded(uint256 indexed taskId, address indexed poster);
event TaskForfeited(uint256 indexed taskId, uint256 amount);
```

**Security / lifecycle:**
- Checks-effects-interactions on ETH transfers; non-reentrant `finalize`, `refund`, `cancelOpen`, `forfeitAbandonedTask`.
- `finalize` treats reverting `verifier.verify()` as false.
- `verifier` at post time must have bytecode (EOAs rejected).
- Only the poster may `refund` or `cancelOpen`; `refund` only for `deadline < now ≤ refundDeadline`.
- After `refundDeadline`, abandoned `Open` tasks are forfeit to `forfeitSink` (disincentivizes “post and forget” spam).
- `submitResult` only while `Open` and `now ≤ deadline`.
- `finalize` only while `Submitted`.
- `getTask` reverts for unknown ids.

---

## 6. Worker Specification

### Overview

`worker.py` is a Python script that monitors the blockchain for `TaskPosted` events and automatically attempts to solve and submit tasks. Multiple instances can run simultaneously with different wallet keys — they race against each other.

### Entry Point

```bash
python worker/worker.py \
  --rpc-url https://sepolia.infura.io/v3/<KEY> \
  --private-key <WORKER_PRIVATE_KEY> \
  --marketplace <CONTRACT_ADDRESS> \
  --poll-interval 5
```

### Dependencies

```
web3==6.x
ezkl==x.x.x
onnxruntime
numpy
python-dotenv
```

### Task Handler Dispatch

The worker reads the `payload` bytes from each `TaskPosted` event, decodes it as UTF-8 JSON, and dispatches to the appropriate handler based on `payload["type"]`:

| `payload.type` | Handler | What it does |
|---|---|---|
| `"hash"` | `HashHandler` | Reads `payload.input`, encodes as UTF-8, submits raw bytes |
| `"prefix"` | `PrefixHandler` | Brute-forces a nonce until `keccak256(nonce)` starts with prefix |
| `"zkml"` | `ZkMlHandler` | Runs ONNX model on `payload.input`, generates EZKL proof, encodes `(proof, instances)` |

### Handler Interface

Each handler must implement:

```python
class BaseHandler:
    def can_handle(self, payload: dict) -> bool: ...
    def solve(self, payload: dict) -> bytes: ...
        # Returns ABI-encoded result bytes ready for submitResult()
```

### `ZkMlHandler` Detail

```python
def solve(self, payload: dict) -> bytes:
    # 1. Load input from payload["input"] (list of floats)
    # 2. Run ezkl.gen_witness(input, compiled_model, witness_path)
    # 3. Run ezkl.prove(witness, pk, proof_path, ...)
    # 4. Load proof bytes from proof_path
    # 5. Load instances from witness
    # 6. Return abi.encode(proof_bytes, instances)
```

EZKL artifacts (compiled model, proving key) are pre-generated during setup and stored in `worker/ezkl_artifacts/`. The worker does not regenerate them at runtime.

### Main Loop

```python
while True:
    latest_block = w3.eth.block_number
    events = marketplace.events.TaskPosted.get_logs(
        from_block=last_processed_block,
        to_block=latest_block
    )
    for event in events:
        task_id = event.args.taskId
        payload = json.loads(event.args.payload.decode())
        
        handler = get_handler(payload)
        if handler is None:
            continue  # unknown task type, skip
            
        result_bytes = handler.solve(payload)
        
        tx = marketplace.functions.submitResult(task_id, result_bytes).transact()
        w3.eth.wait_for_transaction_receipt(tx)
        
        tx = marketplace.functions.finalize(task_id).transact()
        w3.eth.wait_for_transaction_receipt(tx)
        
    last_processed_block = latest_block
    time.sleep(poll_interval)
```

### Error Handling

- If `submitResult` reverts (another worker got there first): log and move on.
- If `finalize` reverts (wrong result): log, no ETH lost.
- If proof generation fails: log, skip task.
- Never crash the loop — wrap each task in try/except.

---

## 7. Frontend Specification

### Overview

Single `index.html` file. No build step. Uses ethers.js v6 via CDN. Connects to MetaMask. Interacts directly with deployed contracts.

### Sections

**1. Header / Wallet Connection**
- "Connect Wallet" button
- Displays connected address and balance when connected
- Network indicator (warns if not on Sepolia)

**2. Task Feed**
- Fetches all `TaskPosted` events from contract deployment block to now
- For each task displays: task ID, type (from payload JSON), reward (ETH), deadline, status, verifier name (resolved from registry)
- Color-coded status badges: Open (green), Submitted (yellow), Finalized (grey), Refunded (grey)
- Auto-refreshes every 15 seconds

**3. Post Task Form**
- Verifier dropdown: populated from `VerifierRegistry.getAllNames()`
- When verifier selected: shows appropriate input fields per verifier type:
  - HashVerifier: "Input to hash" text field — auto-computes `keccak256` client-side as params
  - PrefixVerifier: "Required prefix (hex)" text field
  - ZkMlVerifier: "Input features (comma-separated floats)" text field
- Reward (ETH) number input
- Deadline: date/time picker
- "Post Task" button: calls `postTask()`, shows pending/confirmed/failed state

**4. Transaction Feedback**
- Toast notifications for: tx pending, tx confirmed, tx failed
- Link to Etherscan for each transaction hash

### JavaScript Structure

```javascript
// State
let provider, signer, marketplace, registry;
const MARKETPLACE_ADDRESS = "0x...";
const REGISTRY_ADDRESS = "0x...";
const MARKETPLACE_ABI = [...];
const REGISTRY_ABI = [...];

// Init
async function connectWallet() { ... }
async function loadTasks() { ... }
async function postTask(formData) { ... }

// Helpers
function encodeParams(verifierType, formValues) { ... }
function statusLabel(statusInt) { ... }
function formatEth(wei) { ... }
```

### ethers.js Usage

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/ethers/6.7.0/ethers.umd.min.js"></script>
```

---

## 8. zkML Verifier Specification

### Model Choice

**Iris flower classifier** — a 3-class classification MLP trained on the Iris dataset. Chosen because:
- Input: 4 floats (sepal/petal measurements)
- Output: 3 class probabilities
- Model size: ~500 parameters
- EZKL proof generation: ~20 seconds on a laptop
- Well-understood, easily demo-able

### EZKL Setup Pipeline

Run once during project setup. Outputs are committed to the repository.

```bash
# 1. Export model to ONNX
python worker/models/export_iris.py
# outputs: worker/models/iris.onnx

# 2. Generate EZKL settings
ezkl gen-settings -M worker/models/iris.onnx \
  --settings-path worker/ezkl_artifacts/settings.json

# 3. Calibrate
ezkl calibrate-settings -M worker/models/iris.onnx \
  --settings-path worker/ezkl_artifacts/settings.json \
  --data worker/models/sample_input.json

# 4. Compile circuit
ezkl compile-circuit -M worker/models/iris.onnx \
  --compiled-circuit worker/ezkl_artifacts/compiled_model.ezkl \
  --settings-path worker/ezkl_artifacts/settings.json

# 5. Trusted setup (downloads SRS from Hermez)
ezkl get-srs --settings-path worker/ezkl_artifacts/settings.json

# 6. Setup proving/verifying keys
ezkl setup \
  --compiled-circuit worker/ezkl_artifacts/compiled_model.ezkl \
  --vk-path worker/ezkl_artifacts/vk.key \
  --pk-path worker/ezkl_artifacts/pk.key

# 7. Generate Solidity verifier
ezkl create-evm-verifier \
  --vk-path worker/ezkl_artifacts/vk.key \
  --sol-code-path contracts/ezkl/IrisVerifier.sol \
  --settings-path worker/ezkl_artifacts/settings.json
```

### `ZkMlVerifier.sol` Structure

```solidity
contract ZkMlVerifier is IVerifier {
    // EZKL-generated verifier (do not edit IrisVerifier.sol)
    IEzklVerifier private immutable ezkl;

    constructor(address _ezkl) {
        ezkl = IEzklVerifier(_ezkl);
    }

    function verify(
        bytes calldata params,
        bytes calldata result
    ) external view override returns (bool) {
        // Decode expected output from params
        uint256[] memory expectedInstances = abi.decode(params, (uint256[]));
        
        // Decode proof and actual instances from result
        (bytes memory proof, uint256[] memory instances) = 
            abi.decode(result, (bytes, uint256[]));
        
        // Check instances match expected (model ran on correct input/output)
        if (instances.length != expectedInstances.length) return false;
        for (uint i = 0; i < instances.length; i++) {
            if (instances[i] != expectedInstances[i]) return false;
        }
        
        // Verify ZK proof on-chain
        try ezkl.verifyProof(proof, instances) returns (bool valid) {
            return valid;
        } catch {
            return false;
        }
    }
}
```

---

## 9. Tech Stack

| Layer | Technology | Reason |
|---|---|---|
| Smart contracts | Solidity ^0.8.24 | EVM standard |
| Contract toolchain | Foundry (forge, cast, anvil) | Solidity-native tests, scripts, and deployment |
| Contract testing | Forge (`forge test`) | Tests in Solidity (`.t.sol`); no TypeScript layer |
| Frontend | Plain HTML/CSS/JS | No build step, fast iteration |
| Blockchain library (frontend) | ethers.js v6 (CDN) | Industry standard |
| Worker runtime | Python 3.11 | EZKL has Python SDK |
| Blockchain library (worker) | web3.py 6.x | Mature Python Web3 library |
| zkML | EZKL | Only production-ready zkML toolchain |
| ML runtime | onnxruntime | ONNX model execution |
| Testnet | Ethereum Sepolia | Most supported testnet |
| Frontend hosting | Vercel / GitHub Pages | Free, instant, HTTPS |

---

## 10. Development Phases

Build in this order. Do not start the next phase until the current one is locally working.

### Phase 1 — Core Contracts (start here)

1. `IVerifier.sol`
2. `HashVerifier.sol` + local test: `verify(keccak256("hello"), "hello") == true`
3. `PrefixVerifier.sol` + local test
4. `VerifierRegistry.sol` + local test: register, get, getAllNames
5. `ComputeMarketplace.sol` — implement `postTask` + `submitResult` + `finalize` + `refund`
6. Full Forge test suite (see Phase 3)

### Phase 2 — Deploy to Sepolia

1. Write Foundry scripts under `script/` (e.g. `Deploy.s.sol`, `RegisterVerifiers.s.sol`)
2. Deploy all contracts: `VerifierRegistry`, `HashVerifier`, `PrefixVerifier`, `ComputeMarketplace` (`forge script … --broadcast`)
3. Run the register script to record HashVerifier and PrefixVerifier in the registry
4. Verify contracts on Etherscan (e.g. `forge verify-contract` with `--chain sepolia` and your API key)
5. Note all addresses — update `frontend/index.html` and `worker/worker.py`

### Phase 3 — Foundry (Forge) tests

Write tests covering at minimum:

| Test | Expected |
|---|---|
| Post task with reward, check escrow balance | Pass |
| Submit correct result, finalize, worker receives ETH | Pass |
| Submit wrong result, finalize, task reopens | Pass |
| Submit result from non-worker (another address submits second) | Revert |
| Poster calls refund before deadline | Revert |
| Poster calls refund after deadline | Pass, ETH returned |
| Finalize task that is still Open (no submission) | Revert |
| HashVerifier: correct preimage | Returns true |
| HashVerifier: wrong preimage | Returns false |
| HashVerifier: empty result | Returns false (no revert) |
| PrefixVerifier: matching prefix | Returns true |
| PrefixVerifier: non-matching prefix | Returns false |
| PrefixVerifier: result shorter than prefix | Returns false |

### Phase 4 — Python Worker

1. `worker.py` main loop with web3.py event polling
2. `HashHandler` — reads payload, encodes input as UTF-8 bytes
3. `PrefixHandler` — brute-force nonce loop
4. Test manually: run worker, post a task via `cast send` / a small script / the frontend, watch worker solve it

### Phase 5 — Frontend

1. Wallet connection + network check
2. Task feed from events
3. Post task form (Hash + Prefix verifiers only first)
4. Transaction status feedback
5. End-to-end test: post from frontend, worker auto-solves, task shows as Finalized

### Phase 6 — EZKL / zkML Verifier

1. Train and export `iris.onnx`
2. Run EZKL setup pipeline (see Section 8)
3. Deploy `IrisVerifier.sol` (EZKL-generated) to Sepolia
4. Deploy `ZkMlVerifier.sol`, constructor arg = `IrisVerifier` address
5. Register `ZkMlVerifier` in registry
6. Implement `ZkMlHandler` in worker
7. Add zkml input fields to frontend Post Task form
8. End-to-end test: post zkml task, worker generates proof, finalize on-chain

### Phase 7 — Polish

1. Deploy frontend to Vercel/GitHub Pages
2. Write final README sections (deployment details, learned, conclusion)
3. Run full demo flow with two worker terminals racing
4. Prepare presentation

---

## 11. Deployment Details

> _To be filled in after deployment._

| Contract | Address | Etherscan |
|---|---|---|
| VerifierRegistry | `TBD` | [link]() |
| HashVerifier | `TBD` | [link]() |
| PrefixVerifier | `TBD` | [link]() |
| IrisVerifier (EZKL) | `TBD` | [link]() |
| ZkMlVerifier | `TBD` | [link]() |
| ComputeMarketplace | `TBD` | [link]() |

**Network:** Ethereum Sepolia Testnet (Chain ID: 11155111)

**Frontend:** TBD (Vercel)

---

## 12. Setup Instructions

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`foundryup`)
- Python 3.11+
- MetaMask browser extension
- Sepolia ETH (from a faucet: https://sepoliafaucet.com)

### 1. Clone and Install

```bash
git clone <repo>
cd merezha
forge build
```

### 2. Environment

```bash
cp .env.example .env
# Fill in:
# SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/<KEY>
# PRIVATE_KEY=<deployer wallet private key>
# ETHERSCAN_API_KEY=<key for contract verification>
```

### 3. Run Tests

```bash
forge test
```

### 4. Deploy to Sepolia

```bash
# Example — adjust script contract names and RPC flags to match your repo
forge script script/Deploy.s.sol:DeployScript --rpc-url $SEPOLIA_RPC_URL --broadcast
forge script script/RegisterVerifiers.s.sol:RegisterVerifiersScript --rpc-url $SEPOLIA_RPC_URL --broadcast
```

### 5. Set Up Python Worker

```bash
cd worker
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 6. Run EZKL Setup (first time only)

```bash
python models/export_iris.py
# Then run EZKL commands from Section 8 in order
```

### 7. Run Worker

```bash
# Terminal 1
python worker.py --rpc-url $SEPOLIA_RPC_URL --private-key $WORKER_KEY_1 --marketplace $MARKETPLACE_ADDRESS

# Terminal 2 (optional: competing worker)
python worker.py --rpc-url $SEPOLIA_RPC_URL --private-key $WORKER_KEY_2 --marketplace $MARKETPLACE_ADDRESS
```

### 8. Open Frontend

Open `frontend/index.html` in a browser. Connect MetaMask to Sepolia.

---

## 13. Known Limitations

- **Task payload is public.** Posting a hash task requires committing the answer's hash, but the payload describes what to compute — in theory a worker can compute the answer. This is fine for most task types. For tasks where the answer needs to remain secret until reveal, a commit-reveal scheme would be required (not implemented).
- **Only one concurrent worker per task.** The current design allows only one active submission at a time. A task only re-opens if the current submission is finalized and wrong. A queue of submissions would be more efficient.
- **EZKL proof generation is slow** (~20-60s on a laptop for the Iris model). Larger models are not feasible to prove locally. This is a current limitation of zkML technology, not of the protocol.
- **No worker reputation.** A worker who repeatedly submits wrong answers wastes gas but faces no on-chain penalty. A staking/slashing mechanism would improve incentives.
- **Verifier registry is owner-controlled.** In a production system, verifier registration should go through governance. For this demo, a single deployer key controls registration.
- **No pagination on task feed.** Fetching all events from genesis is fine for a demo but will not scale.

---

## 14. What We Learned

> _To be filled in at project completion._

---

## 15. Use of AI Tools

Claude (Anthropic) was used throughout this project:

- **Architecture design:** Initial discussions about the pluggable verifier pattern, tradeoffs between on-chain vs optimistic verification, and how EZKL fits into the IVerifier interface.
- **Contract scaffolding:** First drafts of all Solidity contracts were generated with AI assistance, then manually reviewed, understood, and modified.
- **Worker code:** Python worker structure and web3.py event handling patterns were developed with AI assistance.
- **README:** This document was structured and partially drafted with AI assistance.

All code was reviewed and understood by the team. During the presentation, we can explain every design decision and line of non-trivial code.

---

## 16. Conclusion

> _To be filled in at project completion._

---

*Built for DMBLOCK Assignment 2 — Digital Currencies and Blockchain*