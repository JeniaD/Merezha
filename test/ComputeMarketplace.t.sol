// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ComputeMarketplace} from "../contracts/ComputeMarketplace.sol";
import {HashVerifier} from "../contracts/verifiers/HashVerifier.sol";
import {VerifierRegistry} from "../contracts/VerifierRegistry.sol";

contract ComputeMarketplaceTest is Test {
    uint256 internal constant SUBMISSION = 1 days;
    uint256 internal constant REFUND_AFTER = 7 days;

    ComputeMarketplace internal m;
    HashVerifier internal hashV;

    address internal poster = address(0xA11);
    address internal worker = address(0xB0B);

    function setUp() public {
        m = new ComputeMarketplace(address(0), address(0));
        hashV = new HashVerifier();
        vm.deal(poster, 100 ether);
        vm.deal(worker, 100 ether);
    }

    function _postHashTask(bytes memory answer, uint256 reward) internal returns (uint256 taskId) {
        bytes32 h = keccak256(answer);
        bytes memory payload = "json-off-chain";
        uint256 dl = block.timestamp + SUBMISSION;
        uint256 rd = dl + REFUND_AFTER;
        vm.prank(poster);
        taskId = m.postTask{value: reward}(payload, address(hashV), abi.encode(h), dl, rd);
    }

    function test_postTask_escrowAndId() public {
        uint256 taskId = _postHashTask("secret", 1 ether);
        assertEq(taskId, 0);
        assertEq(address(m).balance, 1 ether);
        assertEq(m.nextTaskId(), 1);
        ComputeMarketplace.Task memory t = m.getTask(0);
        assertEq(t.poster, poster);
        assertEq(t.reward, 1 ether);
        assertEq(uint256(t.status), uint256(ComputeMarketplace.TaskStatus.Open));
    }

    function test_getTask_unknown_reverts() public {
        vm.expectRevert(ComputeMarketplace.TaskNotFound.selector);
        m.getTask(0);
    }

    function test_postTask_revert_zeroVerifier() public {
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.ZeroVerifier.selector);
        m.postTask{value: 1 ether}("", address(0), "", block.timestamp + 1, block.timestamp + 2 days);
    }

    function test_postTask_revert_notContract() public {
        address eoa = address(0xBEEF);
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.VerifierNotContract.selector);
        m.postTask{value: 1 ether}("", eoa, "", block.timestamp + 1, block.timestamp + 2 days);
    }

    function test_postTask_revert_badRefundDeadline() public {
        uint256 dl = block.timestamp + 1 days;
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.BadRefundDeadline.selector);
        m.postTask{value: 1 ether}("", address(hashV), "", dl, dl);
    }

    function test_postTask_revert_zeroReward() public {
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.ZeroReward.selector);
        m.postTask("", address(hashV), "", block.timestamp + 1, block.timestamp + 2 days);
    }

    function test_postTask_revert_badDeadline() public {
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.BadDeadline.selector);
        m.postTask{value: 1 ether}("", address(hashV), "", block.timestamp, block.timestamp + 1);
    }

    function test_postTaskWithRegisteredVerifier() public {
        VerifierRegistry reg = new VerifierRegistry();
        reg.register("hash", address(hashV));
        ComputeMarketplace mReg = new ComputeMarketplace(address(reg), address(0));
        vm.deal(poster, 100 ether);
        uint256 dl = block.timestamp + SUBMISSION;
        uint256 rd = dl + REFUND_AFTER;
        vm.prank(poster);
        uint256 tid = mReg.postTaskWithRegisteredVerifier{value: 1 ether}(
            "payload", "hash", abi.encode(keccak256("x")), dl, rd
        );
        assertEq(mReg.getTask(tid).verifier, address(hashV));
    }

    function test_postTaskWithRegisteredVerifier_revert_noRegistry() public {
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.RegistryDisabled.selector);
        m.postTaskWithRegisteredVerifier{value: 1 ether}(
            "", "hash", "", block.timestamp + 1, block.timestamp + 2 days
        );
    }

    function test_cancelOpen_beforeDeadline() public {
        uint256 taskId = _postHashTask("x", 2 ether);
        uint256 beforeB = poster.balance;
        vm.prank(poster);
        m.cancelOpen(taskId);
        assertEq(poster.balance, beforeB + 2 ether);
        assertEq(uint256(m.getTask(taskId).status), uint256(ComputeMarketplace.TaskStatus.Refunded));
    }

    function test_cancelOpen_afterDeadline_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.warp(block.timestamp + SUBMISSION + 1);
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.TooLateToCancel.selector);
        m.cancelOpen(taskId);
    }

    function test_submitFinalize_payWorker() public {
        bytes memory ans = "hello";
        uint256 taskId = _postHashTask(ans, 2 ether);

        uint256 wBefore = worker.balance;
        vm.prank(worker);
        m.submitResult(taskId, ans);

        vm.prank(worker);
        m.finalize(taskId);

        assertEq(worker.balance, wBefore + 2 ether);
        ComputeMarketplace.Task memory t = m.getTask(taskId);
        assertEq(uint256(t.status), uint256(ComputeMarketplace.TaskStatus.Finalized));
        assertEq(address(m).balance, 0);
    }

    function test_finalize_wrongResult_reopens() public {
        bytes memory ans = "correct";
        uint256 taskId = _postHashTask(ans, 1 ether);

        vm.prank(worker);
        m.submitResult(taskId, "wrong");

        vm.prank(worker);
        m.finalize(taskId);

        ComputeMarketplace.Task memory t = m.getTask(taskId);
        assertEq(uint256(t.status), uint256(ComputeMarketplace.TaskStatus.Open));
        assertEq(t.worker, address(0));
        assertEq(address(m).balance, 1 ether);
    }

    function test_secondSubmit_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.prank(worker);
        m.submitResult(taskId, "x");
        vm.prank(worker);
        vm.expectRevert(ComputeMarketplace.TaskNotOpen.selector);
        m.submitResult(taskId, "y");
    }

    function test_finalize_open_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.expectRevert(ComputeMarketplace.TaskNotSubmitted.selector);
        m.finalize(taskId);
    }

    function test_refund_afterDeadline() public {
        uint256 taskId = _postHashTask("x", 3 ether);
        uint256 beforeB = poster.balance;
        vm.warp(block.timestamp + SUBMISSION + 1);
        vm.prank(poster);
        m.refund(taskId);
        assertEq(poster.balance, beforeB + 3 ether);
        ComputeMarketplace.Task memory t = m.getTask(taskId);
        assertEq(uint256(t.status), uint256(ComputeMarketplace.TaskStatus.Refunded));
    }

    function test_refund_beforeDeadline_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.TooEarlyToRefund.selector);
        m.refund(taskId);
    }

    function test_refund_afterRefundWindow_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.warp(block.timestamp + SUBMISSION + REFUND_AFTER + 1);
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.RefundWindowClosed.selector);
        m.refund(taskId);
    }

    function test_forfeitAbandonedTask() public {
        address sink = address(0xC0FFEE);
        ComputeMarketplace m2 = new ComputeMarketplace(address(0), sink);
        vm.deal(poster, 100 ether);
        bytes32 h = keccak256("a");
        uint256 dl = block.timestamp + SUBMISSION;
        uint256 rd = dl + REFUND_AFTER;
        vm.prank(poster);
        uint256 tid = m2.postTask{value: 1 ether}("p", address(hashV), abi.encode(h), dl, rd);

        vm.warp(block.timestamp + SUBMISSION + REFUND_AFTER + 1);
        uint256 sinkBefore = sink.balance;
        m2.forfeitAbandonedTask(tid);
        assertEq(sink.balance, sinkBefore + 1 ether);
        assertEq(uint256(m2.getTask(tid).status), uint256(ComputeMarketplace.TaskStatus.Forfeited));
    }

    function test_forfeit_tooEarly_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.expectRevert(ComputeMarketplace.RefundWindowStillOpen.selector);
        m.forfeitAbandonedTask(taskId);
    }

    function test_refund_notPoster_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.warp(block.timestamp + SUBMISSION + 1);
        vm.prank(worker);
        vm.expectRevert(ComputeMarketplace.NotPoster.selector);
        m.refund(taskId);
    }

    function test_submit_afterDeadline_reverts() public {
        uint256 taskId = _postHashTask("x", 1 ether);
        vm.warp(block.timestamp + SUBMISSION + 1);
        vm.prank(worker);
        vm.expectRevert(ComputeMarketplace.PastDeadline.selector);
        m.submitResult(taskId, "x");
    }

    function test_refund_notOpen_reverts() public {
        bytes memory ans = "ok";
        uint256 taskId = _postHashTask(ans, 1 ether);
        vm.prank(worker);
        m.submitResult(taskId, ans);
        vm.warp(block.timestamp + SUBMISSION + 1);
        vm.prank(poster);
        vm.expectRevert(ComputeMarketplace.NotOpenForRefund.selector);
        m.refund(taskId);
    }
}
