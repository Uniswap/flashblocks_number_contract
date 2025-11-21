// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";

contract DeployFlashblockNumber is Script {
    function run() external {
        // Read environment variables
        address owner = vm.envAddress("FLASHBLOCK_NUMBER_OWNER");
        address flashtestationRegistry = vm.envAddress("FLASHTESTATION_REGISTRY");
        address blockBuilderPolicy = vm.envAddress("BLOCK_BUILDER_POLICY");

        console.log("Deploying FlashblockNumber with owner:", owner);
        console.log("Flashtestation Registry:", flashtestationRegistry);
        console.log("Block Builder Policy:", blockBuilderPolicy);

        vm.startBroadcast();

        // Deploy UUPS proxy using CREATE3 for deterministic address
        address proxyAddress = Upgrades.deployUUPSProxy(
            "FlashblockNumber.sol",
            abi.encodeCall(FlashblockNumber.initialize, (owner, flashtestationRegistry, blockBuilderPolicy))
        );

        vm.stopBroadcast();

        console.log("FlashblockNumber deployed at:", proxyAddress);

        // Verify the deployment
        FlashblockNumber flashblock = FlashblockNumber(proxyAddress);
        console.log("Flashblock number:", flashblock.getFlashblockNumber());
        console.log("Owner:", flashblock.owner());
        console.log("Registry:", flashblock.registry());
        console.log("Policy:", flashblock.policy());
    }
}
