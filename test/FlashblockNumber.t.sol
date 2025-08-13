// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";
import {IFlashblockNumber} from "../src/IFlashblockNumber.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract FlashblockNumberTest is Test {
    IFlashblockNumber public flashblockNumber;

    address public owner = makeAddr("owner");
    address public builder1 = makeAddr("builder1");
    address public builder2 = makeAddr("builder2");
    address public nonBuilder = makeAddr("nonBuilder");
    address implementation = address(new FlashblockNumber());

    // private keys cannot be greater than or equal to this value
    uint256 public SECP256K1_CURVE_LIMIT =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;

    address[] public initialBuilders;

    function setUp() public {
        initialBuilders.push(builder1);
        initialBuilders.push(builder2);

        vm.prank(owner);
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation, abi.encodeCall(FlashblockNumber.initialize, (owner, initialBuilders))
        );
        flashblockNumber = IFlashblockNumber(proxy);
    }

    function test_InitialState() public view {
        assertTrue(flashblockNumber.isBuilder(builder1));
        assertTrue(flashblockNumber.isBuilder(builder2));
        assertFalse(flashblockNumber.isBuilder(nonBuilder));
        assertEq(flashblockNumber.getFlashblockNumber(), 0);
    }

    function test_IncrementFlashblockNumber_SameBlock() public {
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 2);
    }

    function test_IncrementFlashblockNumber_NewBlock() public {
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        vm.roll(block.number + 1);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 2);
    }

    function test_IncrementFlashblockNumber_MultipleBlockGap() public {
        vm.roll(block.number + 5);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_IncrementFlashblockNumber_NonBuilder() public {
        vm.prank(nonBuilder);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, nonBuilder));
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_AddBuilder() public {
        address newBuilder = makeAddr("newBuilder");

        vm.prank(owner);
        vm.expectEmit();
        emit IFlashblockNumber.BuilderAdded(newBuilder);
        flashblockNumber.addBuilder(newBuilder);

        assertTrue(flashblockNumber.isBuilder(newBuilder));

        vm.prank(newBuilder);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 1);
    }

    function test_AddBuilder_AlreadyExists() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.AddressIsAlreadyABuilder.selector, builder1));
        flashblockNumber.addBuilder(builder1);
    }

    function test_AddBuilder_OnlyOwner() public {
        address newBuilder = makeAddr("newBuilder");

        vm.prank(nonBuilder);
        vm.expectRevert();
        flashblockNumber.addBuilder(newBuilder);
    }

    function test_RemoveBuilder() public {
        vm.prank(owner);
        vm.expectEmit();
        emit IFlashblockNumber.BuilderRemoved(builder1);
        flashblockNumber.removeBuilder(builder1);

        assertFalse(flashblockNumber.isBuilder(builder1));

        vm.prank(builder1);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, builder1));
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_RemoveBuilder_NotExists() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.BuilderDoesNotExist.selector, nonBuilder));
        flashblockNumber.removeBuilder(nonBuilder);
    }

    function test_RemoveBuilder_OnlyOwner() public {
        vm.prank(nonBuilder);
        vm.expectRevert();
        flashblockNumber.removeBuilder(builder1);
    }

    function test_Events_FlashblockIncremented() public {
        vm.prank(builder1);
        vm.expectEmit();
        emit IFlashblockNumber.FlashblockIncremented(1);
        flashblockNumber.incrementFlashblockNumber();

        vm.prank(builder1);
        vm.expectEmit();
        emit IFlashblockNumber.FlashblockIncremented(2);
        flashblockNumber.incrementFlashblockNumber();

        vm.roll(block.number + 1);

        vm.prank(builder2);
        vm.expectEmit();
        emit IFlashblockNumber.FlashblockIncremented(3);
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_GetFlashblockNumber() public {
        assertEq(flashblockNumber.getFlashblockNumber(), 0);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 1);
    }

    // fuzz the invariant that the flashblock number should increase exactly equal to
    // the number of times flashblockNumber.incrementFlashblockNumber() is called
    function testFuzz_FlashblockIncrementsCorrectlyEvenWithMissingBlocks(
        uint256 numTimesToIncrement,
        uint8 probabilityMissFlashblock
    ) public {
        // limit the number of times we increment so we don't run out of gas in
        // this fuzz test
        vm.assume(numTimesToIncrement > 0 && numTimesToIncrement <= 1000);
        // better simulate reality by allowing some probability that a flashblock
        // increment will fail to occur
        vm.assume(probabilityMissFlashblock >= 0 && probabilityMissFlashblock <= 100);

        uint256 numTimesIncremented = 0;

        for (uint256 i = 0; i < numTimesToIncrement; i++) {
            bool shouldMissFlashblock = vm.randomUint(0, 100) <= probabilityMissFlashblock;

            if (!shouldMissFlashblock) {
                vm.roll(block.number + 1);
            } else {
                vm.prank(builder1);
                vm.expectEmit();
                emit IFlashblockNumber.FlashblockIncremented(++numTimesIncremented);
                flashblockNumber.incrementFlashblockNumber();
            }

            // after each call to increment we check the invariant
            assertEq(flashblockNumber.getFlashblockNumber(), numTimesIncremented);
        }
    }

    // This test is to ensure that the builder rotation is working as expected.
    // It should be able to add new builders and remove builders.
    // It should be able to increment the flashblock number for each builder.
    function testFuzz_BuilderRotation(address[] memory newBuilders) public {
        vm.assume(newBuilders.length > 0 && newBuilders.length <= 10);

        for (uint256 i = 0; i < newBuilders.length; i++) {
            vm.assume(newBuilders[i] != address(0));
            vm.assume(!flashblockNumber.isBuilder(newBuilders[i]));

            // this block is to ensure that the new builders are not the same as the initial builders
            bool duplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (newBuilders[i] == newBuilders[j]) {
                    duplicate = true;
                    break;
                }
            }
            vm.assume(!duplicate);

            vm.prank(owner);
            flashblockNumber.addBuilder(newBuilders[i]);
            assertTrue(flashblockNumber.isBuilder(newBuilders[i]));

            vm.prank(newBuilders[i]);
            flashblockNumber.incrementFlashblockNumber();
        }
    }

    /// -----------------------------------------------------------------------
    /// EIP-712 Meta-Transaction Tests
    /// -----------------------------------------------------------------------

    function _signIncrement(uint256 privateKey, uint256 currentFlashblockNumber) internal view returns (bytes memory) {
        bytes32 structHash = FlashblockNumber(address(flashblockNumber)).computeStructHash(currentFlashblockNumber);
        bytes32 digest = FlashblockNumber(address(flashblockNumber)).hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_permitIncrementFlashblockNumber_ValidSignature() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        // Add the signer as a builder
        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder);

        // Create signature for current flashblock number (0)
        bytes memory signature = _signIncrement(builder1PrivateKey, 0);

        // Execute meta-transaction via relayer
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        vm.expectEmit();
        emit IFlashblockNumber.FlashblockIncremented(1);
        flashblockNumber.permitIncrementFlashblockNumber(0, signature);

        assertEq(flashblockNumber.getFlashblockNumber(), 1);
    }

    function test_permitIncrementFlashblockNumber_NonBuilderSigner() public {
        uint256 wrongPrivateKey = 0x5678;

        bytes memory signature = _signIncrement(wrongPrivateKey, 0);

        address wrongSigner = vm.addr(wrongPrivateKey);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, wrongSigner));
        flashblockNumber.permitIncrementFlashblockNumber(0, signature);
    }

    function test_permitIncrementFlashblockNumber_MismatchedFlashblockNumber() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder);

        // Create signature for flashblock number 5, but current is 0
        bytes memory signature = _signIncrement(builder1PrivateKey, 5);

        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.MismatchedFlashblockNumber.selector, 5, 0));
        flashblockNumber.permitIncrementFlashblockNumber(5, signature);
    }

    function test_permitIncrementFlashblockNumber_ReplayAttackPrevention() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder);

        // Create signature for flashblock number 0
        bytes memory signature = _signIncrement(builder1PrivateKey, 0);

        // First execution should succeed
        flashblockNumber.permitIncrementFlashblockNumber(0, signature);
        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        // Try to replay the same signature - should fail
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.MismatchedFlashblockNumber.selector, 0, 1));
        flashblockNumber.permitIncrementFlashblockNumber(0, signature);
    }

    function test_permitIncrementFlashblockNumber_NonBuilderRejection() public {
        uint256 nonBuilderPrivateKey = 0x9999;
        address nonBuilderSigner = vm.addr(nonBuilderPrivateKey);

        // Ensure the signer is not a builder
        assertFalse(flashblockNumber.isBuilder(nonBuilderSigner));

        bytes memory signature = _signIncrement(nonBuilderPrivateKey, 0);

        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, nonBuilderSigner));
        flashblockNumber.permitIncrementFlashblockNumber(0, signature);
    }

    function test_permitIncrementFlashblockNumber_BuilderRotationCompatibility() public {
        uint256 builder1PrivateKey = 0x1234;
        uint256 builder2PrivateKey = 0x5678;
        address signerBuilder1 = vm.addr(builder1PrivateKey);
        address signerBuilder2 = vm.addr(builder2PrivateKey);

        // Add both builders
        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder1);
        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder2);

        // Builder1 increments via meta-transaction
        bytes memory signature1 = _signIncrement(builder1PrivateKey, 0);
        flashblockNumber.permitIncrementFlashblockNumber(0, signature1);
        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        // Remove builder1
        vm.prank(owner);
        flashblockNumber.removeBuilder(signerBuilder1);

        // Builder1's old signature for flashblock 1 should now fail
        bytes memory oldSignature = _signIncrement(builder1PrivateKey, 1);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, signerBuilder1));
        flashblockNumber.permitIncrementFlashblockNumber(1, oldSignature);

        // But builder2 can still increment
        bytes memory signature2 = _signIncrement(builder2PrivateKey, 1);
        flashblockNumber.permitIncrementFlashblockNumber(1, signature2);
        assertEq(flashblockNumber.getFlashblockNumber(), 2);
    }

    function test_permitIncrementFlashblockNumber_MixedUsage() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder);

        // Direct call first
        vm.prank(signerBuilder);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        // Meta-transaction call second
        bytes memory signature = _signIncrement(builder1PrivateKey, 1);
        flashblockNumber.permitIncrementFlashblockNumber(1, signature);
        assertEq(flashblockNumber.getFlashblockNumber(), 2);

        // Direct call third
        vm.prank(signerBuilder);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 3);

        // Meta-transaction call fourth
        bytes memory signature2 = _signIncrement(builder1PrivateKey, 3);
        flashblockNumber.permitIncrementFlashblockNumber(3, signature2);
        assertEq(flashblockNumber.getFlashblockNumber(), 4);
    }

    function test_permitIncrementFlashblockNumber_SequentialIncrements() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder);

        // Multiple sequential meta-transactions
        for (uint256 i = 0; i < 5; i++) {
            bytes memory signature = _signIncrement(builder1PrivateKey, i);
            flashblockNumber.permitIncrementFlashblockNumber(i, signature);
            assertEq(flashblockNumber.getFlashblockNumber(), i + 1);
        }
    }

    function test_permitIncrementFlashblockNumber_DifferentRelayers() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder);

        bytes memory signature = _signIncrement(builder1PrivateKey, 0);

        // Any address can act as relayer
        address relayer1 = makeAddr("relayer1");
        address relayer2 = makeAddr("relayer2");

        vm.prank(relayer1);
        flashblockNumber.permitIncrementFlashblockNumber(0, signature);
        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        // Different relayer for next increment
        bytes memory signature2 = _signIncrement(builder1PrivateKey, 1);
        vm.prank(relayer2);
        flashblockNumber.permitIncrementFlashblockNumber(1, signature2);
        assertEq(flashblockNumber.getFlashblockNumber(), 2);
    }

    function testFuzz_permitIncrementFlashblockNumber_ValidSequence(uint256 numIncrements, uint256 builderPrivateKey)
        public
    {
        vm.assume(numIncrements > 0 && numIncrements <= 100);
        vm.assume(builderPrivateKey > 0 && builderPrivateKey < SECP256K1_CURVE_LIMIT);

        address signerBuilder = vm.addr(builderPrivateKey);

        vm.prank(owner);
        flashblockNumber.addBuilder(signerBuilder);

        for (uint256 i = 0; i < numIncrements; i++) {
            bytes memory signature = _signIncrement(builderPrivateKey, i);
            flashblockNumber.permitIncrementFlashblockNumber(i, signature);
            assertEq(flashblockNumber.getFlashblockNumber(), i + 1);
        }
    }

    // Helper functions for EIP-712 testing
    function test_ComputeStructHash() public view {
        bytes32 structHash = FlashblockNumber(address(flashblockNumber)).computeStructHash(42);
        bytes32 expected =
            keccak256(abi.encode(keccak256("PermitIncrementFlashblock(uint256 currentFlashblockNumber)"), 42));
        assertEq(structHash, expected);
    }
}
