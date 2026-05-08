// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

/// @dev TODO: deploy VerifierRegistry, HashVerifier, PrefixVerifier, ComputeMarketplace (and zkML stack later).
contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();
        // TODO: new VerifierRegistry(), new HashVerifier(), ...
        vm.stopBroadcast();
    }
}
