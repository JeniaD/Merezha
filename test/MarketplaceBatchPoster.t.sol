// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ComputeMarketplace} from "../contracts/ComputeMarketplace.sol";
import {VerifierRegistry} from "../contracts/VerifierRegistry.sol";
import {HashVerifier} from "../contracts/verifiers/HashVerifier.sol";
import {MarketplaceBatchPoster} from "../contracts/MarketplaceBatchPoster.sol";

contract MarketplaceBatchPosterTest is Test {
    VerifierRegistry internal reg;
    HashVerifier internal hashV;
    ComputeMarketplace internal market;
    MarketplaceBatchPoster internal batch;
    address internal poster = address(0xA11);

    function setUp() public {
        reg = new VerifierRegistry();
        hashV = new HashVerifier();
        market = new ComputeMarketplace(address(reg), address(0));
        batch = new MarketplaceBatchPoster(address(market));
        reg.register("hash", address(hashV));
        vm.deal(poster, 100 ether);
    }

    function test_postBatch_twoRegistryTasks() public {
        uint256 dl = block.timestamp + 1 days;
        uint256 rd = dl + 7 days;
        bytes32 h = keccak256("hi");
        bytes memory v0 = abi.encode(h);

        MarketplaceBatchPoster.TaskSpec[] memory specs = new MarketplaceBatchPoster.TaskSpec[](2);
        bytes memory payloadB = hex"7b2274797065223a2268617368222c22696e707574223a226869227d";
        specs[0] = MarketplaceBatchPoster.TaskSpec({
            useRegistry: true,
            verifier: address(0),
            verifierName: "hash",
            payload: payloadB,
            verificationParams: v0,
            deadline: dl,
            refundDeadline: rd,
            reward: 1 ether
        });
        specs[1] = MarketplaceBatchPoster.TaskSpec({
            useRegistry: true,
            verifier: address(0),
            verifierName: "hash",
            payload: payloadB,
            verificationParams: v0,
            deadline: dl,
            refundDeadline: rd,
            reward: 2 ether
        });

        vm.prank(poster);
        batch.postBatch{value: 3 ether}(specs);

        assertEq(market.nextTaskId(), 2);
        assertEq(market.getTask(0).reward, 1 ether);
        assertEq(market.getTask(1).reward, 2 ether);
        assertEq(market.getTask(0).poster, address(batch));
        assertEq(batch.beneficiaryOf(0), poster);
        assertEq(batch.beneficiaryOf(1), poster);
    }

    function test_postBatch_revert_wrongValue() public {
        MarketplaceBatchPoster.TaskSpec[] memory specs = new MarketplaceBatchPoster.TaskSpec[](1);
        specs[0] = MarketplaceBatchPoster.TaskSpec({
            useRegistry: true,
            verifier: address(0),
            verifierName: "hash",
            payload: hex"7b2274797065223a2268617368222c22696e707574223a2261227d",
            verificationParams: abi.encode(keccak256("a")),
            deadline: block.timestamp + 1,
            refundDeadline: block.timestamp + 2 days,
            reward: 1 ether
        });

        vm.prank(poster);
        vm.expectRevert(MarketplaceBatchPoster.BadValue.selector);
        batch.postBatch{value: 0.5 ether}(specs);
    }

    function test_postBatch_directVerifier() public {
        uint256 dl = block.timestamp + 1 days;
        uint256 rd = dl + 7 days;
        bytes memory v = abi.encode(keccak256("x"));

        MarketplaceBatchPoster.TaskSpec[] memory specs = new MarketplaceBatchPoster.TaskSpec[](1);
        specs[0] = MarketplaceBatchPoster.TaskSpec({
            useRegistry: false,
            verifier: address(hashV),
            verifierName: "",
            payload: hex"7b2274797065223a2268617368222c22696e707574223a2278227d",
            verificationParams: v,
            deadline: dl,
            refundDeadline: rd,
            reward: 0.5 ether
        });

        vm.prank(poster);
        batch.postBatch{value: 0.5 ether}(specs);
        assertEq(market.getTask(0).verifier, address(hashV));
    }
}
