// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Placeholder until `ezkl create-evm-verifier` overwrites this path — keep `verifyProof` signature compatible with EZKL output.
contract IrisVerifier {
    function verifyProof(bytes calldata proof, uint256[] calldata instances) external pure returns (bool) {
        proof;
        instances;
        return false;
    }
}
