// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VerifierRegistry} from "./VerifierRegistry.sol";

/// @title VerifierGovernance
/// @notice Stake-weighted voting to register verifiers. `VerifierRegistry.owner` must be this contract.
///         All ETH sent with proposals and votes stays in this contract (treasury).
contract VerifierGovernance {
    VerifierRegistry public immutable registry;
    uint256 public immutable minProposalStake;
    uint256 public immutable votingPeriod;

    uint256 public nextProposalId;

    struct Proposal {
        string name;
        address verifier;
        address proposer;
        uint256 yesStake;
        uint256 noStake;
        uint256 endTime;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(
        uint256 indexed id, string name, address verifier, address indexed proposer, uint256 endTime
    );
    event Voted(uint256 indexed id, address indexed voter, bool support, uint256 amount);
    event ProposalExecuted(uint256 indexed id, string name, address verifier);

    error ZeroAddress();
    error NotContract();
    error StakeTooSmall();
    error ProposalNotFound();
    error VotingClosed();
    error VotingStillOpen();
    error AlreadyExecuted();
    error ProposalRejected();

    constructor(VerifierRegistry registry_, uint256 minProposalStake_, uint256 votingPeriod_) {
        if (address(registry_) == address(0)) revert ZeroAddress();
        registry = registry_;
        minProposalStake = minProposalStake_;
        votingPeriod = votingPeriod_;
    }

    /// @notice Opens a proposal; msg.value counts toward YES stake.
    function createProposal(string calldata name, address verifier) external payable returns (uint256 id) {
        if (verifier.code.length == 0) revert NotContract();
        if (msg.value < minProposalStake) revert StakeTooSmall();

        id = nextProposalId++;
        proposals[id] = Proposal({
            name: name,
            verifier: verifier,
            proposer: msg.sender,
            yesStake: msg.value,
            noStake: 0,
            endTime: block.timestamp + votingPeriod,
            executed: false
        });

        emit ProposalCreated(id, name, verifier, msg.sender, proposals[id].endTime);
    }

    /// @notice Vote YES or NO with ETH stake (locked in contract until treasury use).
    function vote(uint256 proposalId, bool support) external payable {
        if (proposalId >= nextProposalId) revert ProposalNotFound();
        Proposal storage p = proposals[proposalId];
        if (p.executed) revert AlreadyExecuted();
        if (block.timestamp >= p.endTime) revert VotingClosed();
        if (msg.value == 0) revert StakeTooSmall();

        if (support) {
            p.yesStake += msg.value;
        } else {
            p.noStake += msg.value;
        }

        emit Voted(proposalId, msg.sender, support, msg.value);
    }

    /// @notice After voting ends: register if YES stake strictly exceeds NO stake.
    function execute(uint256 proposalId) external {
        if (proposalId >= nextProposalId) revert ProposalNotFound();
        Proposal storage p = proposals[proposalId];
        if (p.executed) revert AlreadyExecuted();
        if (block.timestamp < p.endTime) revert VotingStillOpen();
        if (p.yesStake <= p.noStake) revert ProposalRejected();

        p.executed = true;
        registry.register(p.name, p.verifier);
        emit ProposalExecuted(proposalId, p.name, p.verifier);
    }

    receive() external payable {}
}
