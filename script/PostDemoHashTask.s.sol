// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ComputeMarketplace} from "../contracts/ComputeMarketplace.sol";

/// @dev Local / CI: post a single hash task matching worker `HashHandler` expectations.
/// @notice Set MARKETPLACE=0x... (ComputeMarketplace). Optional: REWARD_WEI (default 0.01 ether).
contract PostDemoHashTask is Script {
    function run() external {
        address market = vm.envAddress("MARKETPLACE");
        uint256 reward = vm.envOr("REWARD_WEI", uint256(0.01 ether));

        // UTF-8: {"type":"hash","input":"hello"}
        bytes memory payload = hex"7b2274797065223a2268617368222c22696e707574223a2268656c6c6f227d";
        bytes32 h = keccak256("hello");
        bytes memory vp = abi.encode(h);
        uint256 dl = block.timestamp + 1 hours;
        uint256 rdl = block.timestamp + 7 days;

        vm.startBroadcast();
        uint256 tid = ComputeMarketplace(market).postTaskWithRegisteredVerifier{value: reward}(
            payload, "hash", vp, dl, rdl
        );
        vm.stopBroadcast();
        console2.log("Posted hash demo task id:", tid);
    }
}
