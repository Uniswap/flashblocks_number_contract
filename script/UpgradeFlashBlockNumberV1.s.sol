// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";

/**
 * @title UpgradeFlashblockNumberV1
 * @notice Upgrade script for FlashblockNumber contract from V1 to V2
 * @dev This script:
 *      1. Deploys a new FlashblockNumber implementation contract
 *      2. Upgrades the existing UUPS proxy to point to the new implementation
 *      3. Calls reinitializeV2 to set the flashtestation registry and block builder policy addresses
 */
contract UpgradeFlashblockNumberV1 is Script {
    function run() external {
        address proxyAddress = vm.envAddress("FLASHBLOCK_NUMBER_PROXY_ADDRESS");
        address flashtestationRegistry = vm.envAddress("FLASHTESTATION_REGISTRY_ADDRESS");
        address blockBuilderPolicy = vm.envAddress("BLOCK_BUILDER_POLICY_ADDRESS");
        run(proxyAddress, flashtestationRegistry, blockBuilderPolicy);
    }

    function run(address proxyAddress, address flashtestationRegistry, address blockBuilderPolicy) public {
        console.log("=== FlashblockNumber Upgrade Configuration ===");
        console.log("Proxy address:", proxyAddress);
        console.log("FlashtestationRegistry address:", flashtestationRegistry);
        console.log("BlockBuilderPolicy address:", blockBuilderPolicy);
        console.log("");

        // Verify the proxy exists and is a FlashblockNumber contract
        FlashblockNumber existingProxy = FlashblockNumber(proxyAddress);
        console.log("=== Pre-Upgrade State ===");
        console.log("Current flashblock number:", existingProxy.getFlashblockNumber());
        console.log("Current owner:", existingProxy.owner());
        console.log("");

        vm.startBroadcast();

        // Upgrade the proxy to the new implementation and call reinitializeV2
        Options memory opts;
        opts.referenceContract = "V1FlashblockNumber.sol:V1FlashblockNumber";
        Upgrades.upgradeProxy(
            proxyAddress,
            "FlashblockNumber.sol",
            abi.encodeCall(FlashblockNumber.reinitializeV2, (flashtestationRegistry, blockBuilderPolicy)),
            opts
        );

        vm.stopBroadcast();

        console.log("=== Upgrade Complete ===");
        console.log("");

        // Verify the upgrade
        console.log("=== Post-Upgrade Verification ===");
        FlashblockNumber upgradedProxy = FlashblockNumber(proxyAddress);

        // Verify state was preserved
        console.log("Flashblock number (should be unchanged):", upgradedProxy.getFlashblockNumber());
        console.log("Owner (should be unchanged):", upgradedProxy.owner());

        // Verify new functionality
        address registryAddress = upgradedProxy.registry();
        address policyAddress = upgradedProxy.policy();

        console.log("Registry address:", registryAddress);
        console.log("Policy address:", policyAddress);
        console.log("");

        // Validate the addresses were set correctly
        require(registryAddress == flashtestationRegistry, "Registry address mismatch");
        require(policyAddress == blockBuilderPolicy, "Policy address mismatch");

        console.log("=== Upgrade Successful ===");
        console.log("All verifications passed!");
    }
}
