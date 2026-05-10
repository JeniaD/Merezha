// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifierRegistry} from "../contracts/VerifierRegistry.sol";
import {VerifierGovernance} from "../contracts/VerifierGovernance.sol";
import {HashVerifier} from "../contracts/verifiers/HashVerifier.sol";

contract VerifierGovernanceTest is Test {
    VerifierRegistry internal registry;
    VerifierGovernance internal gov;
    HashVerifier internal hashV;
    HashVerifier internal newV;

    address alice = address(0xA11);
    address bob = address(0xB0B);

    uint256 constant MIN = 0.01 ether;
    uint256 constant PERIOD = 1 hours;

    function setUp() public {
        registry = new VerifierRegistry();
        gov = new VerifierGovernance(registry, MIN, PERIOD);
        registry.transferOwnership(address(gov));
        hashV = new HashVerifier();
        newV = new HashVerifier();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_createProposal_and_execute() public {
        vm.prank(alice);
        uint256 id = gov.createProposal{value: MIN}("extra", address(newV));
        assertEq(id, 0);

        vm.prank(bob);
        gov.vote{value: 0.5 ether}(0, true);

        vm.warp(block.timestamp + PERIOD + 1);

        gov.execute(0);

        assertEq(registry.get("extra"), address(newV));
        (,,,,,, bool executed) = gov.proposals(0);
        assertTrue(executed);
    }

    function test_execute_reverts_if_no_wins() public {
        vm.prank(alice);
        gov.createProposal{value: MIN}("nope", address(newV));

        vm.prank(bob);
        gov.vote{value: 2 ether}(0, false);

        vm.warp(block.timestamp + PERIOD + 1);

        vm.expectRevert(VerifierGovernance.ProposalRejected.selector);
        gov.execute(0);
    }

    function test_vote_reverts_after_period() public {
        vm.prank(alice);
        gov.createProposal{value: MIN}("late", address(newV));

        vm.warp(block.timestamp + PERIOD + 1);

        vm.prank(bob);
        vm.expectRevert(VerifierGovernance.VotingClosed.selector);
        gov.vote{value: 1 ether}(0, true);
    }
}
