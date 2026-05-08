// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVerifier} from "../interfaces/IVerifier.sol";

contract HashVerifier is IVerifier {
    function verify(bytes calldata params, bytes calldata result) external pure returns (bool) {
        if (result.length == 0) return false;
        if (params.length < 32) return false;
        bytes32 expectedHash = abi.decode(params, (bytes32));
        return keccak256(result) == expectedHash;
    }
}
