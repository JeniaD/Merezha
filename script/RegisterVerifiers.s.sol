// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VerifierRegistry} from "../contracts/VerifierRegistry.sol";

/// @notice Register one extra verifier (e.g. zkML after deploy). Requires env vars; broadcaster must be registry owner.
/// @dev After default deploy, the registry owner is `VerifierGovernance` — use governance proposals instead of this script,
///      unless you deploy without governance or transfer ownership back.
/// @dev VERIFIER_REGISTRY, VERIFIER_NAME (string), VERIFIER_ADDRESS
contract RegisterVerifiersScript is Script {
    function run() external {
        VerifierRegistry registry = VerifierRegistry(vm.envAddress("VERIFIER_REGISTRY"));
        string memory name = vm.envString("VERIFIER_NAME");
        address verifier = vm.envAddress("VERIFIER_ADDRESS");

        vm.startBroadcast();
        registry.register(name, verifier);
        vm.stopBroadcast();

        console2.log("Registered", name, "at", verifier);
    }
}
