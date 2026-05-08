// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VerifierRegistry} from "../contracts/VerifierRegistry.sol";
import {HashVerifier} from "../contracts/verifiers/HashVerifier.sol";
import {PrefixVerifier} from "../contracts/verifiers/PrefixVerifier.sol";
import {ComputeMarketplace} from "../contracts/ComputeMarketplace.sol";

/// @notice Deploy core contracts and register `hash` / `prefix` verifiers. Broadcast wallet must match registry owner (deployer).
contract DeployScript is Script {
    function run() external {
        address forfeitSink = vm.envOr("FORFEIT_SINK", address(0));

        vm.startBroadcast();
        VerifierRegistry registry = new VerifierRegistry();
        HashVerifier hashV = new HashVerifier();
        PrefixVerifier prefixV = new PrefixVerifier();
        ComputeMarketplace market = new ComputeMarketplace(address(registry), forfeitSink);

        registry.register("hash", address(hashV));
        registry.register("prefix", address(prefixV));
        vm.stopBroadcast();

        console2.log("VerifierRegistry:", address(registry));
        console2.log("HashVerifier:", address(hashV));
        console2.log("PrefixVerifier:", address(prefixV));
        console2.log("ComputeMarketplace:", address(market));
    }
}
