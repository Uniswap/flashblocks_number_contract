// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";
import {IFlashblockNumber} from "../src/IFlashblockNumber.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FlashblockNumberTest is Test {
    IFlashblockNumber public flashblockNumber;
    uint256 public numFlashblocksPerBlock = 5;

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
            implementation,
            abi.encodeCall(
                FlashblockNumber.initialize,
                (owner, initialBuilders, numFlashblocksPerBlock, numFlashblocksPerBlock - 1)
            )
        );
        flashblockNumber = IFlashblockNumber(proxy);
    }

    function test_InitialState() public view {
        assertEq(flashblockNumber.lastL2BlockNumber(), block.number);
        assertTrue(flashblockNumber.isBuilder(builder1));
        assertTrue(flashblockNumber.isBuilder(builder2));
        assertFalse(flashblockNumber.isBuilder(nonBuilder));
        assertEq(flashblockNumber.getFlashblockNumber(), numFlashblocksPerBlock - 1);
    }

    function test_IncrementFlashblockNumber_SameBlock() public {
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 0);
        assertEq(flashblockNumber.lastL2BlockNumber(), block.number);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 1);
        assertEq(flashblockNumber.lastL2BlockNumber(), block.number);
    }

    function test_IncrementFlashblockNumber_NewBlock() public {
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);

        vm.roll(block.number + 1);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 0);
        assertEq(flashblockNumber.lastL2BlockNumber(), block.number);
    }

    function test_IncrementFlashblockNumber_MultipleBlockGap() public {
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);

        vm.roll(block.number + 5);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 0);
        assertEq(flashblockNumber.lastL2BlockNumber(), block.number);
    }

    function test_IncrementFlashblockNumber_OnlyBuilder() public {
        vm.prank(nonBuilder);
        vm.expectRevert("NotBuilder");
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_RaceCondition_SameFlashblock() public {
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);

        vm.prank(builder2);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 1);
    }

    function test_AddBuilder() public {
        address newBuilder = makeAddr("newBuilder");

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IFlashblockNumber.BuilderAdded(newBuilder);
        flashblockNumber.addBuilder(newBuilder);

        assertTrue(flashblockNumber.isBuilder(newBuilder));

        vm.prank(newBuilder);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);
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
        vm.expectEmit(true, false, false, true);
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
        vm.expectEmit(false, false, false, true);
        emit IFlashblockNumber.FlashblockIncremented(0);
        flashblockNumber.incrementFlashblockNumber();

        vm.prank(builder1);
        vm.expectEmit(false, false, false, true);
        emit IFlashblockNumber.FlashblockIncremented(1);
        flashblockNumber.incrementFlashblockNumber();

        vm.roll(block.number + 1);

        vm.prank(builder1);
        vm.expectEmit(false, false, false, true);
        emit IFlashblockNumber.FlashblockIncremented(0);
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_GetFlashblockNumber() public {
        assertEq(flashblockNumber.getFlashblockNumber(), numFlashblocksPerBlock - 1);

        vm.roll(block.number + 1);
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);
    }

    function test_GetFlashblockNumberFailWithIndexGreaterThanFlashblockNumber() public {
        // This test ensures that getFlashblockNumber() does not return an index greater than numFlashblocksPerBlock - 1,
        // and that incrementFlashblockNumber() properly resets the index at block boundaries.

        // Initial state: flashblockIndex should be numFlashblocksPerBlock - 1 (see initialize in src/FlashblockNumber.sol)
        assertLe(flashblockNumber.getFlashblockNumber(), numFlashblocksPerBlock - 1);

        // Increment up to numFlashblocksPerBlock times in the same block
        for (uint256 i = 0; i < numFlashblocksPerBlock; i++) {
            vm.prank(builder1);
            flashblockNumber.incrementFlashblockNumber();
            uint256 flashblockNum = flashblockNumber.getFlashblockNumber();
            assertLe(
                flashblockNum, numFlashblocksPerBlock - 1, "FlashblockNumber: flashblock number exceeded max per block"
            );
        }

        // now try to increment again, it should revert
        vm.prank(builder1);
        vm.expectRevert((IFlashblockNumber.InvalidFlashblockNumberUpdate.selector));
        flashblockNumber.incrementFlashblockNumber();

        // Roll to next block and check reset
        vm.roll(block.number + 1);
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);
    }

    function testFuzz_MonotonicityWithinBlock(uint8 increments, uint256 builderIndex) public {
        vm.assume(increments > 0 && increments < 100);
        vm.assume(builderIndex < initialBuilders.length);

        for (uint256 i = 0; i < increments; i++) {
            uint256 expectedIndex = i % numFlashblocksPerBlock;

            if (i % numFlashblocksPerBlock == 0) {
                vm.roll(block.number + 1);
            }

            vm.prank(initialBuilders[builderIndex]);
            flashblockNumber.incrementFlashblockNumber();

            assertEq(flashblockNumber.getFlashblockNumber(), expectedIndex);
            assertEq(flashblockNumber.lastL2BlockNumber(), block.number);
        }
    }

    // This test is to ensure that the flashblock number is reset across blocks (aka block jumps).
    // It should be reset to 0 when the block number increases.
    // the `blockJumps` is the number of times the block number will increase.
    // the `incrementsPerBlock` is the number of times the builder will increment the flashblock number within a block.
    function testFuzz_ResetAcrossBlocks(uint8 blockJumps, uint8 incrementsPerBlock) public {
        vm.assume(blockJumps > 0 && blockJumps < 20);
        vm.assume(incrementsPerBlock > 0 && incrementsPerBlock < 10);

        uint256 currentBlock = block.number;

        for (uint256 blockIdx = 0; blockIdx < blockJumps; blockIdx++) {
            for (uint256 increment = 0; increment < incrementsPerBlock; increment++) {
                vm.prank(builder1);

                if (increment > numFlashblocksPerBlock - 1) {
                    // this means we're trying to increment past the max per block
                    vm.expectRevert(IFlashblockNumber.InvalidFlashblockNumberUpdate.selector);
                    flashblockNumber.incrementFlashblockNumber();
                } else {
                    // this is the normal case
                    flashblockNumber.incrementFlashblockNumber();
                    assertEq(flashblockNumber.getFlashblockNumber(), increment);
                }

                assertEq(flashblockNumber.lastL2BlockNumber(), currentBlock);
            }

            currentBlock++;
            vm.roll(currentBlock);
        }
    }

    // fuzz the invariant that the result of getFlashblockNumber should never be greater than
    // or equal to numFlashblocksPerBlock()
    function testFuzz_FlashblockNeverGreaterOrEqualToNumFlashblocksPerBlock(
        uint256 _numFlashblocksPerBlock,
        uint256 _numBlocksToTest,
        uint256 _probabilityMissFlashblock
    ) public {
        vm.assume(_numFlashblocksPerBlock >= 1 && _numFlashblocksPerBlock <= 10);
        // 1 to 10 blocks gives us good coverage while not blowing up the runtime
        // of the fuzz test
        vm.assume(_numBlocksToTest >= 1 && _numBlocksToTest <= 10);

        // better simulate reality by allowing some probability that a flashblock
        // increment will fail to occur
        vm.assume(_probabilityMissFlashblock >= 0 && _probabilityMissFlashblock <= 100);

        // make a new FlashblockNumber so we can ensure this property holds for different values of
        // numFlashblocksPerBlock
        vm.prank(owner);
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(
                FlashblockNumber.initialize,
                (owner, initialBuilders, _numFlashblocksPerBlock, _numFlashblocksPerBlock - 1)
            )
        );
        flashblockNumber = IFlashblockNumber(proxy);

        // advance to next block, since we set the initial flashblock index to be
        // _numFlashblocksPerBlock - 1 (a.k.a. the last flashblock in the block)
        vm.roll(block.number + 1);

        for (uint256 i = 0; i < _numBlocksToTest; i++) {
            for (uint256 j = 0; j < _numFlashblocksPerBlock; j++) {
                bool shouldMissFlashblock = vm.randomUint(0, 100) <= _probabilityMissFlashblock;
                vm.prank(builder1);
                if (!shouldMissFlashblock) {
                    flashblockNumber.incrementFlashblockNumber();
                }

                // after each call to increment we check the invariant
                assertTrue(flashblockNumber.getFlashblockNumber() < flashblockNumber.numFlashblocksPerBlock());
            }

            vm.roll(block.number + 1);
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

            if (flashblockNumber.getFlashblockNumber() == numFlashblocksPerBlock - 1) {
                vm.roll(block.number + 1);
            }
            vm.prank(newBuilders[i]);
            flashblockNumber.incrementFlashblockNumber();
        }
    }
}
