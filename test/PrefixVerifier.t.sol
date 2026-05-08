// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PrefixVerifier} from "../contracts/verifiers/PrefixVerifier.sol";

contract PrefixVerifierTest is Test {
    PrefixVerifier internal v;

    function setUp() public {
        v = new PrefixVerifier();
    }

    function test_matchingPrefix() public view {
        bytes memory prefix = hex"abcd";
        bytes memory result = hex"abcdef";
        assertTrue(v.verify(abi.encode(prefix), result));
    }

    function test_nonMatching() public view {
        bytes memory prefix = hex"ffff";
        bytes memory result = hex"0000";
        assertFalse(v.verify(abi.encode(prefix), result));
    }

    function test_resultShorterThanPrefix() public view {
        bytes memory prefix = hex"abcd";
        bytes memory result = hex"ab";
        assertFalse(v.verify(abi.encode(prefix), result));
    }
}
