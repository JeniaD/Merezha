// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVerifier} from "./interfaces/IVerifier.sol";
import {VerifierRegistry} from "./VerifierRegistry.sol";

/// @title ComputeMarketplace
/// @notice Escrow-based task market; verification delegated to pluggable `IVerifier` contracts.
contract ComputeMarketplace {
    /// @dev Default sink for forfeited escrow (common burn address). Override via constructor `forfeitSink_`.
    address private constant DEFAULT_FORFEIT_SINK = 0x000000000000000000000000000000000000dEaD;

    enum TaskStatus {
        Open,
        Submitted,
        Finalized,
        Refunded,
        Forfeited
    }

    struct Task {
        address poster;
        address worker;
        address verifier;
        bytes payload;
        bytes verificationParams;
        bytes submittedResult;
        uint256 reward;
        uint256 deadline;
        uint256 refundDeadline;
        TaskStatus status;
    }

    VerifierRegistry public immutable verifierRegistry;
    address public immutable forfeitSink;

    mapping(uint256 => Task) public tasks;
    uint256 public nextTaskId;

    bool private _entered;

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

    error Reentrancy();
    error ZeroVerifier();
    error VerifierNotContract();
    error ZeroReward();
    error BadDeadline();
    error BadRefundDeadline();
    error TaskNotFound();
    error TaskNotOpen();
    error TaskNotSubmitted();
    error NotPoster();
    error TooEarlyToRefund();
    error RefundWindowClosed();
    error NotOpenForRefund();
    error PastDeadline();
    error TooLateToCancel();
    error RefundWindowStillOpen();
    error ETHSendFailed();
    error RegistryDisabled();

    modifier nonReentrant() {
        if (_entered) revert Reentrancy();
        _entered = true;
        _;
        _entered = false;
    }

    /// @param registry_ Pass `address(0)` if you only use `postTask` with raw verifier addresses.
    /// @param forfeitSink_ Pass `address(0)` to use `DEFAULT_FORFEIT_SINK` (burn). Otherwise ETH from abandoned tasks goes here.
    constructor(address registry_, address forfeitSink_) {
        verifierRegistry = VerifierRegistry(registry_);
        forfeitSink = forfeitSink_ == address(0) ? DEFAULT_FORFEIT_SINK : forfeitSink_;
    }

    /// @notice Post a task; `refundDeadline` must be after `deadline` (submission cutoff).
    ///         Poster may `refund` only while `deadline < now <= refundDeadline`. After that, `forfeitAbandonedTask` sends escrow to `forfeitSink`.
    function postTask(
        bytes calldata payload,
        address verifier,
        bytes calldata verificationParams,
        uint256 deadline,
        uint256 refundDeadline
    ) external payable returns (uint256 taskId) {
        return _postTask(payload, verifier, verificationParams, deadline, refundDeadline);
    }

    /// @notice Same as `postTask`, but resolves verifier via `verifierRegistry.get(name)`. Requires non-zero registry in constructor.
    function postTaskWithRegisteredVerifier(
        bytes calldata payload,
        string calldata verifierName,
        bytes calldata verificationParams,
        uint256 deadline,
        uint256 refundDeadline
    ) external payable returns (uint256 taskId) {
        if (address(verifierRegistry) == address(0)) revert RegistryDisabled();
        address verifier = verifierRegistry.get(verifierName);
        return _postTask(payload, verifier, verificationParams, deadline, refundDeadline);
    }

    function _postTask(
        bytes calldata payload,
        address verifier,
        bytes calldata verificationParams,
        uint256 deadline,
        uint256 refundDeadline
    ) internal returns (uint256 taskId) {
        if (verifier == address(0)) revert ZeroVerifier();
        if (verifier.code.length == 0) revert VerifierNotContract();
        if (msg.value == 0) revert ZeroReward();
        if (deadline <= block.timestamp) revert BadDeadline();
        if (refundDeadline <= deadline) revert BadRefundDeadline();

        taskId = nextTaskId++;
        tasks[taskId] = Task({
            poster: msg.sender,
            worker: address(0),
            verifier: verifier,
            payload: payload,
            verificationParams: verificationParams,
            submittedResult: new bytes(0),
            reward: msg.value,
            deadline: deadline,
            refundDeadline: refundDeadline,
            status: TaskStatus.Open
        });

        emit TaskPosted(taskId, msg.sender, verifier, msg.value, deadline, refundDeadline, payload);
    }

    /// @notice Poster reclaims escrow before anyone can submit; only while `now < deadline`.
    function cancelOpen(uint256 taskId) external nonReentrant {
        if (taskId >= nextTaskId) revert TaskNotFound();
        Task storage t = tasks[taskId];
        if (msg.sender != t.poster) revert NotPoster();
        if (t.status != TaskStatus.Open) revert TaskNotOpen();
        if (block.timestamp >= t.deadline) revert TooLateToCancel();

        uint256 amt = t.reward;
        t.status = TaskStatus.Refunded;
        t.reward = 0;
        emit TaskRefunded(taskId, msg.sender);

        (bool sent,) = msg.sender.call{value: amt}("");
        if (!sent) revert ETHSendFailed();
    }

    function submitResult(uint256 taskId, bytes calldata result) external {
        if (taskId >= nextTaskId) revert TaskNotFound();
        Task storage t = tasks[taskId];
        if (t.status != TaskStatus.Open) revert TaskNotOpen();
        if (block.timestamp > t.deadline) revert PastDeadline();

        t.worker = msg.sender;
        t.submittedResult = result;
        t.status = TaskStatus.Submitted;
        emit ResultSubmitted(taskId, msg.sender);
    }

    function finalize(uint256 taskId) external nonReentrant {
        if (taskId >= nextTaskId) revert TaskNotFound();
        Task storage t = tasks[taskId];
        if (t.status != TaskStatus.Submitted) revert TaskNotSubmitted();

        address workerAddr = t.worker;
        bytes memory res = t.submittedResult;
        address ver = t.verifier;
        bytes memory vparams = t.verificationParams;

        bool accepted;
        try IVerifier(ver).verify(vparams, res) returns (bool v) {
            accepted = v;
        } catch {
            accepted = false;
        }

        if (accepted) {
            uint256 pay = t.reward;
            t.status = TaskStatus.Finalized;
            t.reward = 0;
            emit TaskFinalized(taskId, workerAddr, true);
            (bool sent,) = workerAddr.call{value: pay}("");
            if (!sent) revert ETHSendFailed();
        } else {
            t.worker = address(0);
            t.submittedResult = new bytes(0);
            t.status = TaskStatus.Open;
            emit TaskFinalized(taskId, workerAddr, false);
        }
    }

    /// @notice After submission `deadline`, poster can reclaim while `now <= refundDeadline`.
    function refund(uint256 taskId) external nonReentrant {
        if (taskId >= nextTaskId) revert TaskNotFound();
        Task storage t = tasks[taskId];
        if (msg.sender != t.poster) revert NotPoster();
        if (block.timestamp <= t.deadline) revert TooEarlyToRefund();
        if (block.timestamp > t.refundDeadline) revert RefundWindowClosed();
        if (t.status != TaskStatus.Open) revert NotOpenForRefund();

        uint256 amt = t.reward;
        t.status = TaskStatus.Refunded;
        t.reward = 0;
        emit TaskRefunded(taskId, msg.sender);

        (bool sent,) = msg.sender.call{value: amt}("");
        if (!sent) revert ETHSendFailed();
    }

    /// @notice If a task stays `Open` past `refundDeadline`, anyone can burn/send escrow to `forfeitSink` (no poster refund).
    function forfeitAbandonedTask(uint256 taskId) external nonReentrant {
        if (taskId >= nextTaskId) revert TaskNotFound();
        Task storage t = tasks[taskId];
        if (t.status != TaskStatus.Open) revert TaskNotOpen();
        if (block.timestamp <= t.refundDeadline) revert RefundWindowStillOpen();

        uint256 amt = t.reward;
        t.status = TaskStatus.Forfeited;
        t.reward = 0;
        emit TaskForfeited(taskId, amt);

        (bool sent,) = forfeitSink.call{value: amt}("");
        if (!sent) revert ETHSendFailed();
    }

    function getTask(uint256 taskId) external view returns (Task memory) {
        if (taskId >= nextTaskId) revert TaskNotFound();
        return tasks[taskId];
    }
}
