// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";
import {IFlashblockNumber} from "../src/IFlashblockNumber.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FlashblockNumberTest is Test {
    IFlashblockNumber public flashblockNumber;

    address public owner = makeAddr("owner");
    address public builder1 = makeAddr("builder1");
    address public builder2 = makeAddr("builder2");
    address public nonBuilder = makeAddr("nonBuilder");
    address implementation = address(new FlashblockNumber());

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
}
