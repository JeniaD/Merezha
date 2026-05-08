// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVerifier} from "../interfaces/IVerifier.sol";

interface IEzklVerifier {
    function verifyProof(bytes calldata proof, uint256[] calldata instances) external view returns (bool);
}

/// @title ZkMlVerifier
/// @notice Wraps an EZKL-generated verifier; `params` / `result` encoding per README §5.4 / §8.
contract ZkMlVerifier is IVerifier {
    IEzklVerifier private immutable ezkl;

    constructor(address _ezkl) {
        ezkl = IEzklVerifier(_ezkl);
    }

    function verify(bytes calldata params, bytes calldata result) external view returns (bool) {
        uint256[] memory expectedInstances = abi.decode(params, (uint256[]));
        (bytes memory proof, uint256[] memory instances) = abi.decode(result, (bytes, uint256[]));

        if (instances.length != expectedInstances.length) return false;
        for (uint256 i = 0; i < instances.length; i++) {
            if (instances[i] != expectedInstances[i]) return false;
        }

        try ezkl.verifyProof(proof, instances) returns (bool valid) {
            return valid;
        } catch {
            return false;
        }
    }
}
