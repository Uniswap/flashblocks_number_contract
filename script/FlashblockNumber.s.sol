// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";

contract DeployFlashblockNumber is Script {
    function run() external {
        // Read environment variables
        address owner = vm.envAddress("FLASHBLOCK_NUMBER_OWNER");
        string memory buildersEnv = vm.envString("INITIAL_BUILDERS");

        // Parse comma-separated builder addresses
        address[] memory initialBuilders = parseBuilderAddresses(buildersEnv);

        console.log("Deploying FlashblockNumber with owner:", owner);
        console.log("Initial builders count:", initialBuilders.length);
        for (uint256 i = 0; i < initialBuilders.length; i++) {
            console.log("  Builder", i, ":", initialBuilders[i]);
        }

        vm.startBroadcast();

        // Deploy UUPS proxy using CREATE3 for deterministic address
        address proxyAddress = Upgrades.deployUUPSProxy(
            "FlashblockNumber.sol", abi.encodeCall(FlashblockNumber.initialize, (owner, initialBuilders))
        );

        vm.stopBroadcast();

        console.log("FlashblockNumber deployed at:", proxyAddress);

        // Verify the deployment
        FlashblockNumber flashblock = FlashblockNumber(proxyAddress);
        console.log("Flashblock number:", flashblock.getFlashblockNumber());
        console.log("Owner:", flashblock.owner());

        // Verify builders
        for (uint256 i = 0; i < initialBuilders.length; i++) {
            require(flashblock.isBuilder(initialBuilders[i]), "Builder not properly set");
            console.log("Builder", initialBuilders[i], "verified");
        }
    }

    function parseBuilderAddresses(string memory buildersStr) internal pure returns (address[] memory) {
        bytes memory data = bytes(buildersStr);
        if (data.length == 0) {
            return new address[](0);
        }

        // Count commas to determine array size
        uint256 commaCount = 0;
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] == ",") {
                commaCount++;
            }
        }

        address[] memory addresses = new address[](commaCount + 1);
        uint256 addressIndex = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= data.length; i++) {
            if (i == data.length || data[i] == ",") {
                // Extract substring from start to i
                bytes memory addressBytes = new bytes(i - start);
                for (uint256 j = 0; j < i - start; j++) {
                    addressBytes[j] = data[start + j];
                }

                // Trim whitespace and convert to address
                string memory addressStr = string(trimWhitespace(addressBytes));
                console.log("parsing the address", addressStr);
                addresses[addressIndex] = parseAddress(addressStr);
                addressIndex++;
                start = i + 1;
            }
        }

        return addresses;
    }

    function trimWhitespace(bytes memory data) internal pure returns (bytes memory) {
        uint256 start = 0;
        uint256 end = data.length;

        // Find start (skip leading whitespace)
        while (start < data.length && (data[start] == " " || data[start] == "\t" || data[start] == "\n")) {
            start++;
        }

        // Find end (skip trailing whitespace)
        while (end > start && (data[end - 1] == " " || data[end - 1] == "\t" || data[end - 1] == "\n")) {
            end--;
        }

        bytes memory result = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            result[i] = data[start + i];
        }

        return result;
    }

    function parseAddress(string memory addressStr) internal pure returns (address) {
        bytes memory addressBytes = bytes(addressStr);
        require(addressBytes.length == 42, "Invalid address length");
        require(addressBytes[0] == "0" && (addressBytes[1] == "x" || addressBytes[1] == "X"), "Invalid address prefix");

        bytes memory addr = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addr[i] = bytes1(fromHex(addressBytes[2 + i * 2]) * 16 + fromHex(addressBytes[3 + i * 2]));
        }

        return address(uint160(bytes20(addr)));
    }

    function fromHex(bytes1 char) internal pure returns (uint8) {
        uint8 byteValue = uint8(char);
        if (byteValue >= uint8(bytes1("0")) && byteValue <= uint8(bytes1("9"))) {
            return byteValue - uint8(bytes1("0"));
        } else if (byteValue >= uint8(bytes1("a")) && byteValue <= uint8(bytes1("f"))) {
            return 10 + byteValue - uint8(bytes1("a"));
        } else if (byteValue >= uint8(bytes1("A")) && byteValue <= uint8(bytes1("F"))) {
            return 10 + byteValue - uint8(bytes1("A"));
        }
        revert("Invalid hex character");
    }
}
