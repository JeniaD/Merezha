// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VerifierRegistry} from "../contracts/VerifierRegistry.sol";
import {VerifierGovernance} from "../contracts/VerifierGovernance.sol";
import {HashVerifier} from "../contracts/verifiers/HashVerifier.sol";
import {PrefixVerifier} from "../contracts/verifiers/PrefixVerifier.sol";
import {ComputeMarketplace} from "../contracts/ComputeMarketplace.sol";
import {MarketplaceBatchPoster} from "../contracts/MarketplaceBatchPoster.sol";

/// @notice Deploy core contracts, register bootstrap verifiers, transfer registry to governance.
/// @dev Env: FORFEIT_SINK (optional), MIN_PROPOSAL_STAKE_WEI (default 0.01 ether), VOTING_PERIOD_SECONDS (default 300).
contract DeployScript is Script {
    function run() external {
        address forfeitSink = vm.envOr("FORFEIT_SINK", address(0));
        uint256 minStake = vm.envOr("MIN_PROPOSAL_STAKE_WEI", uint256(0.01 ether));
        uint256 votePeriod = vm.envOr("VOTING_PERIOD_SECONDS", uint256(300));

        vm.startBroadcast();
        VerifierRegistry registry = new VerifierRegistry();
        HashVerifier hashV = new HashVerifier();
        PrefixVerifier prefixV = new PrefixVerifier();
        ComputeMarketplace market = new ComputeMarketplace(address(registry), forfeitSink);

        registry.register("hash", address(hashV));
        registry.register("prefix", address(prefixV));

        VerifierGovernance gov = new VerifierGovernance(registry, minStake, votePeriod);
        registry.transferOwnership(address(gov));

        MarketplaceBatchPoster batchPoster = new MarketplaceBatchPoster(address(market));
        vm.stopBroadcast();

        console2.log("VerifierRegistry:", address(registry));
        console2.log("VerifierGovernance:", address(gov));
        console2.log("HashVerifier:", address(hashV));
        console2.log("PrefixVerifier:", address(prefixV));
        console2.log("ComputeMarketplace:", address(market));
        console2.log("MarketplaceBatchPoster:", address(batchPoster));
    }
}
