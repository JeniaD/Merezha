// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkMlVerifier} from "../contracts/verifiers/ZkMlVerifier.sol";
import {IrisVerifier} from "../contracts/ezkl/IrisVerifier.sol";

contract ZkMlVerifierTest is Test {
    function test_verify_stubIris_returnsFalse() public {
        IrisVerifier iris = new IrisVerifier();
        ZkMlVerifier zk = new ZkMlVerifier(address(iris));
        uint256[] memory inst = new uint256[](1);
        inst[0] = 42;
        bytes memory params = abi.encode(inst);
        bytes memory result = abi.encode(bytes(""), inst);
        assertFalse(zk.verify(params, result));
    }

    function test_verify_mismatchedInstancesLength() public {
        IrisVerifier iris = new IrisVerifier();
        ZkMlVerifier zk = new ZkMlVerifier(address(iris));
        uint256[] memory exp = new uint256[](1);
        exp[0] = 1;
        uint256[] memory got = new uint256[](2);
        got[0] = 1;
        got[1] = 2;
        bytes memory params = abi.encode(exp);
        bytes memory result = abi.encode(bytes(""), got);
        assertFalse(zk.verify(params, result));
    }
}
