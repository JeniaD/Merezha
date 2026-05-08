// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

/// @dev TODO: register verifier names in VerifierRegistry (owner broadcast).
contract RegisterVerifiersScript is Script {
    function run() external {
        vm.startBroadcast();
        // TODO: VerifierRegistry(registry).register("hash", hashVerifierAddr);
        vm.stopBroadcast();
    }
}
