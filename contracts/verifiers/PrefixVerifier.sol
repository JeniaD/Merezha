// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVerifier} from "../interfaces/IVerifier.sol";

contract PrefixVerifier is IVerifier {
    function verify(bytes calldata params, bytes calldata result) external pure returns (bool) {
        bytes memory prefix = abi.decode(params, (bytes));
        if (result.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (result[i] != prefix[i]) return false;
        }
        return true;
    }
}
