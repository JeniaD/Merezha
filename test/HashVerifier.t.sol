// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HashVerifier} from "../contracts/verifiers/HashVerifier.sol";

contract HashVerifierTest is Test {
    HashVerifier internal verifier;

    function setUp() public {
        verifier = new HashVerifier();
    }

    function testCorrectPreimage() public view {
        bytes memory answer = "hello";
        bytes32 h = keccak256(answer);
        assertTrue(verifier.verify(abi.encode(h), answer));
    }

    function testWrongPreimage() public view {
        bytes32 h = keccak256("correct");
        assertFalse(verifier.verify(abi.encode(h), bytes("wrong")));
    }
}
