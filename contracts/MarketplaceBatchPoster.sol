// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ComputeMarketplace} from "./ComputeMarketplace.sol";

/// @title MarketplaceBatchPoster
/// @notice Forward many `postTask` / `postTaskWithRegisteredVerifier` calls in a single transaction (one signature, one gas payer).
///         On-chain `Task.poster` is this contract (the marketplace requires `msg.sender` to be poster for cancel/refund).
///         The EOA that called `postBatch` is stored in `beneficiaryOf` so they can reclaim via `userCancelOpen` / `userRefund`.
contract MarketplaceBatchPoster {
    ComputeMarketplace public immutable marketplace;

    /// @notice taskId => EOA that paid for that task inside `postBatch`
    mapping(uint256 => address) public beneficiaryOf;

    struct TaskSpec {
        bool useRegistry;
        address verifier;
        string verifierName;
        bytes payload;
        bytes verificationParams;
        uint256 deadline;
        uint256 refundDeadline;
        uint256 reward;
    }

    error BadValue();
    error EmptyBatch();
    error NotBeneficiary();
    error ETHSendFailed();

    event BatchPosted(address indexed beneficiary, uint256 startTaskId, uint256 endTaskId, uint256 count);

    constructor(address marketplace_) {
        marketplace = ComputeMarketplace(marketplace_);
    }

    /// @dev `msg.value` must equal the sum of all `tasks[i].reward`.
    function postBatch(TaskSpec[] calldata tasks) external payable {
        uint256 n = tasks.length;
        if (n == 0) revert EmptyBatch();

        uint256 total;
        for (uint256 i = 0; i < n; i++) {
            total += tasks[i].reward;
        }
        if (msg.value != total) revert BadValue();

        address beneficiary = msg.sender;
        uint256 startId = marketplace.nextTaskId();
        for (uint256 i = 0; i < n; i++) {
            TaskSpec calldata t = tasks[i];
            uint256 taskId;
            if (t.useRegistry) {
                taskId = marketplace.postTaskWithRegisteredVerifier{value: t.reward}(
                    t.payload,
                    t.verifierName,
                    t.verificationParams,
                    t.deadline,
                    t.refundDeadline
                );
            } else {
                taskId = marketplace.postTask{value: t.reward}(
                    t.payload,
                    t.verifier,
                    t.verificationParams,
                    t.deadline,
                    t.refundDeadline
                );
            }
            beneficiaryOf[taskId] = beneficiary;
        }
        uint256 endId = marketplace.nextTaskId() - 1;
        emit BatchPosted(beneficiary, startId, endId, n);
    }

    /// @notice Cancel an open task posted via this batch contract; escrow goes to the beneficiary EOA.
    function userCancelOpen(uint256 taskId) external {
        if (beneficiaryOf[taskId] != msg.sender) revert NotBeneficiary();
        uint256 beforeBal = address(this).balance;
        marketplace.cancelOpen(taskId);
        uint256 received = address(this).balance - beforeBal;
        (bool sent,) = msg.sender.call{value: received}("");
        if (!sent) revert ETHSendFailed();
    }

    /// @notice Refund after deadline (same semantics as marketplace `refund`).
    function userRefund(uint256 taskId) external {
        if (beneficiaryOf[taskId] != msg.sender) revert NotBeneficiary();
        uint256 beforeBal = address(this).balance;
        marketplace.refund(taskId);
        uint256 received = address(this).balance - beforeBal;
        (bool sent,) = msg.sender.call{value: received}("");
        if (!sent) revert ETHSendFailed();
    }

    receive() external payable {}
}
