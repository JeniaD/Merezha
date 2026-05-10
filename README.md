# Merezha — Decentralized Compute Marketplace

> DMBLOCK Assignment 2 · Digital Currencies and Blockchain

Merezha is a decentralized marketplace for small off-chain compute tasks. A user posts a task with an ETH reward, a worker solves it off-chain, and the smart contract releases the reward only if a verifier contract accepts the submitted result.

The project is motivated by academic and research compute networks: many groups need occasional compute, but trust is difficult when execution happens outside the blockchain. Re-running every task on-chain would be too expensive, especially for larger computations, so the important problem is not only "who runs the task?" but "how do we verify the answer?"

Merezha's answer is a pluggable verifier design. The marketplace does not hard-code one verification method. Each task points to an `IVerifier` contract, and the marketplace only asks that contract whether `(verificationParams, result)` is valid. This lets the same marketplace support simple hash preimage tasks, proof-of-work style prefix tasks, and future proof systems such as zkML without redeploying the marketplace itself.

For the live demo, the frontend posts tasks to Sepolia, a Python worker watches `TaskPosted` events, solves supported task types locally, submits the result, and calls `finalize`. The reward then moves from escrow to the worker wallet if the selected verifier accepts the result.

## Live Deployment

**Network:** Ethereum Sepolia testnet  
**Chain ID:** `11155111`  
**Deployment block:** `10828324`  
**Frontend:** run locally from `frontend/index.html` or `frontend/demo.html`

| Contract | Address | Explorer |
|---|---|---|
| `ComputeMarketplace` | `0x9973800216605B3bb21B68A86B9F286bd2b02042` | [Sepolia Etherscan](https://sepolia.etherscan.io/address/0x9973800216605B3bb21B68A86B9F286bd2b02042) |
| `VerifierRegistry` | `0x126fAD21a800A32bE1f43a7F56f0c85dC9FB4C05` | [Sepolia Etherscan](https://sepolia.etherscan.io/address/0x126fAD21a800A32bE1f43a7F56f0c85dC9FB4C05) |
| `VerifierGovernance` | `0x56e13893d8353Be727D37Da40d47C7c786b98f7B` | [Sepolia Etherscan](https://sepolia.etherscan.io/address/0x56e13893d8353Be727D37Da40d47C7c786b98f7B) |
| `HashVerifier` | `0x8cE1bA5bCa7Abf227C1cA35fAa97Ef49fb42fD12` | [Sepolia Etherscan](https://sepolia.etherscan.io/address/0x8cE1bA5bCa7Abf227C1cA35fAa97Ef49fb42fD12) |
| `PrefixVerifier` | `0x4513477340F4ea2A0842aa0CB1D9C355ABB3C79f` | [Sepolia Etherscan](https://sepolia.etherscan.io/address/0x4513477340F4ea2A0842aa0CB1D9C355ABB3C79f) |
| `MarketplaceBatchPoster` | `0x9bCf7a35f5c816aA697C9d0bE61B9eDF5C801960` | [Sepolia Etherscan](https://sepolia.etherscan.io/address/0x9bCf7a35f5c816aA697C9d0bE61B9eDF5C801960) |

Registered verifier names on Sepolia:

| Name | Contract |
|---|---|
| `hash` | `0x8cE1bA5bCa7Abf227C1cA35fAa97Ef49fb42fD12` |
| `prefix` | `0x4513477340F4ea2A0842aa0CB1D9C355ABB3C79f` |

Source verification on Etherscan should be completed before final grading if the explorer does not yet show verified Solidity source.

## Architecture

```text
User / browser
  | posts task + ETH reward
  v
ComputeMarketplace
  | stores task, reward, verifier, params
  | emits TaskPosted
  v
Python worker
  | reads TaskPosted events
  | solves payload off-chain
  | submitResult(taskId, result)
  v
ComputeMarketplace.finalize(taskId)
  | calls selected IVerifier.verify(params, result)
  | pays worker if accepted
```

Main contracts:

- `ComputeMarketplace` is the escrow and task lifecycle contract. It handles posting, submission, finalization, cancellation, refunds, and abandoned-task forfeits.
- `VerifierRegistry` maps names such as `hash` and `prefix` to verifier contract addresses.
- `VerifierGovernance` owns the registry after deployment and can register new verifiers through stake-weighted proposals.
- `HashVerifier` accepts a result if `keccak256(result)` equals the poster's committed hash.
- `PrefixVerifier` accepts a result if it begins with the required byte prefix.
- `MarketplaceBatchPoster` lets the UI post multiple tasks in one transaction and records the original beneficiary for refunds/cancellations.

Task lifecycle:

```text
Open -> Submitted -> Finalized
  |         |
  |         +-- if verification fails: Open again
  |
  +-- after deadline: Refunded or Forfeited
```

## Frontend

The frontend is intentionally simple: plain HTML/CSS/JavaScript using `ethers.js` from a CDN. There is no build step.

- `frontend/index.html` is the main explorer and task composer.
- `frontend/demo.html` is the Mandelbrot tile demo. It splits an image into tiles, posts each tile as a hash-verifier task, and paints the tile once a worker finalizes it.

For Sepolia, use these UI settings:

```text
Network: Sepolia (11155111)
Marketplace: 0x9973800216605B3bb21B68A86B9F286bd2b02042
Registry: 0x126fAD21a800A32bE1f43a7F56f0c85dC9FB4C05
Governance: 0x56e13893d8353Be727D37Da40d47C7c786b98f7B
Batch poster: 0x9bCf7a35f5c816aA697C9d0bE61B9eDF5C801960
Event scan from block: 10828324
```

Recommended Mandelbrot demo settings on Sepolia:

```text
Grid: 2 or 3
Tile px: 8 or 16
Max iterations: 64
Reward per tile: 0.00001 ETH
Mode: Sequential for reliability; batch mode is more gas-sensitive
```

Serve the frontend locally:

```bash
python3 -m http.server 8080 -d frontend
```

Then open `http://localhost:8080/index.html` or `http://localhost:8080/demo.html`.

### Quick Example: Post a Hash Task in `index.html`

1. Start the static frontend:

   ```bash
   python3 -m http.server 8080 -d frontend
   ```

2. Open `http://localhost:8080/index.html`, paste the Sepolia addresses listed above, set **Event scan from block** to `10828324`, and click **Save configuration**.

3. Connect MetaMask on Sepolia, then click **Reload verifier names**. The verifier dropdown should include `hash` and `prefix`.

4. In **Compose task**, choose **From registry** and select `hash`.

5. Fill the task:

   ```text
   Plaintext preimage: hello
   Payload JSON: {"type":"hash","input":"hello","description":"Demo hash task"}
   Reward: 0.00001
   Batch copies: 1
   Submission deadline: any future time
   Refund window ends: after the submission deadline
   ```

6. Click **Post task on-chain** and confirm the MetaMask transaction.

7. After the posting transaction is confirmed, run the worker:

   ```bash
   cd worker
   source venv/bin/activate

   python worker.py \
     --rpc-url "$SEPOLIA_RPC_URL" \
     --private-key "$PRIVATE_KEY" \
     --marketplace 0x9973800216605B3bb21B68A86B9F286bd2b02042 \
     --from-block 10828324
   ```

8. Refresh the Network explorer in `index.html`. The task should move from `Open` to `Finalized`, and the card should show that the reward was paid to the worker.

## Worker

The worker is a Python process that polls `TaskPosted` events, decodes the JSON payload, chooses a handler, submits the result, and finalizes the task.

Supported live handlers:

| Payload type | Handler | Behavior |
|---|---|---|
| `hash` | `HashHandler` | Reads `payload.input` and submits it as UTF-8 bytes. |
| `prefix` | `PrefixHandler` | Searches for a value whose `keccak256` output begins with the requested prefix. |

Set up and run the worker:

```bash
cd worker
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

python worker.py \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --marketplace 0x9973800216605B3bb21B68A86B9F286bd2b02042 \
  --from-block 10828324
```

For the cleanest live demo, use one wallet in MetaMask for posting tasks and a separate funded wallet for the worker. If the same wallet is used by both the UI and worker at the same time, transactions can compete for the same nonce.

## Repository Structure

```text
contracts/
  ComputeMarketplace.sol
  MarketplaceBatchPoster.sol
  VerifierGovernance.sol
  VerifierRegistry.sol
  interfaces/IVerifier.sol
  verifiers/HashVerifier.sol
  verifiers/PrefixVerifier.sol
  verifiers/ZkMlVerifier.sol
frontend/
  index.html
  demo.html
script/
  Deploy.s.sol
  PostDemoHashTask.s.sol
  RegisterVerifiers.s.sol
test/
  ComputeMarketplace.t.sol
  HashVerifier.t.sol
  MarketplaceBatchPoster.t.sol
  PrefixVerifier.t.sol
  VerifierGovernance.t.sol
  ZkMlVerifier.t.sol
worker/
  worker.py
  handlers/
```

## Setup

Prerequisites:

- Foundry (`forge`, `cast`, `anvil`)
- Python 3.9+; Python 3.11 is recommended
- MetaMask
- Sepolia ETH for deployment and demo transactions

Install and test:

```bash
forge build
forge test
```

Create a local `.env` from `.env.example`:

```bash
cp .env.example .env
```

Required values for Sepolia:

```bash
SEPOLIA_RPC_URL=https://your-sepolia-rpc
PRIVATE_KEY=your_private_key_for_deployment_or_worker
```

Optional for automatic contract verification:

```bash
ETHERSCAN_API_KEY=your_etherscan_api_key
```

Deploy to Sepolia:

```bash
source .env
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY" \
  -vvv
```

Post one simple hash task from a script:

```bash
source .env
export MARKETPLACE=0x9973800216605B3bb21B68A86B9F286bd2b02042

forge script script/PostDemoHashTask.s.sol:PostDemoHashTask \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --private-key "$PRIVATE_KEY" \
  -vvv
```

## Testing

The project uses Foundry tests for contract behavior.

```bash
forge test
```

The test suite covers:

- Posting tasks and escrow accounting.
- Correct result finalization and worker payout.
- Wrong result handling and task reopening.
- Refund and cancellation windows.
- Forfeiting abandoned tasks.
- Registry-based posting.
- Batch posting.
- Governance proposal, voting, and execution paths.
- Hash and prefix verifier success/failure cases.
- Basic `ZkMlVerifier` wrapper behavior with a stub verifier.

A local run before deployment passed `36` tests.

## Security Notes

- `ComputeMarketplace` uses a simple non-reentrancy guard around ETH-transfering functions.
- ETH transfers follow checks-effects-interactions: state is updated before external calls.
- Verifier contracts must have bytecode at task creation time, so EOAs cannot be used as verifiers.
- `finalize` catches verifier reverts and treats them as failed verification, reopening the task instead of locking it.
- Deadlines are timestamp-based and suitable for this demo; production systems should consider validator timestamp tolerance.

## Known Limitations

- Task payloads are public. For hash tasks, the demo includes the preimage in the payload so the worker can solve it automatically. A real secret-answer system would need commit-reveal or encrypted inputs.
- Only one active submission is tracked per task. If a worker submits a wrong result, the task reopens after finalization instead of keeping a queue of competing submissions.
- Workers do not stake collateral. A malicious worker can waste its own gas by submitting bad results, but there is no slashing mechanism.
- Batch posting large Mandelbrot tiles can exceed gas or RPC estimation limits on Sepolia. Sequential posting with small tiles is more reliable for live demos.
- The frontend is a local static page, not a hosted public deployment.
- `ZkMlVerifier` is included as an experimental extension point, but the deployed Sepolia demo focuses on `hash` and `prefix`. The current `IrisVerifier` file is a placeholder unless regenerated by the EZKL pipeline.
- Event scans require the deployment block (`10828324`) on public RPCs; scanning from block `0` often exceeds provider log limits.

## What We Learned

The main lesson was that decentralized compute is mostly a verification problem, not a scheduling problem. The contract that pays workers is relatively small; the hard part is designing a flexible way to decide whether an off-chain result should be trusted.

We also learned that public testnet deployment has practical constraints that do not appear in local tests: RPC log limits, gas estimation failures for large calldata, nonce conflicts when a browser wallet and worker share one account, and the need for clear deployment metadata in the UI.

## Use of AI Tools

Generative AI tools were used during the project as development assistance:

- To discuss the pluggable verifier architecture and trade-offs between hash verification, proof-of-work style verification, and zkML-style verification.
- To scaffold and review parts of the Solidity contracts, tests, Python worker, and frontend.
- To help debug deployment and demo issues such as RPC connectivity, event scan block ranges, batch gas limits, and wallet nonce conflicts.
- To draft and revise documentation.

All project code was reviewed and adapted by the team. The team is prepared to explain the contract lifecycle, verifier interface, worker flow, and deployment decisions during the presentation.

## Conclusion

Merezha demonstrates a working decentralized compute marketplace on Sepolia. Users can post ETH-backed tasks through the frontend, workers can complete them off-chain, and rewards are released only after on-chain verifier contracts accept the result. The most important design feature is the separation between marketplace logic and verification logic: new verifier contracts can be added without changing the core marketplace.

For a production version, the next steps would be worker staking/reputation, better private input handling, hosted frontend deployment, stronger batching/indexing infrastructure, and a completed zkML verifier pipeline.
