// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";
import {IFlashblockNumber} from "../src/IFlashblockNumber.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract FlashblockNumberTest is Test {
    IFlashblockNumber public flashblockNumber;
    uint256 public numFlashblocksPerBlock = 5; // this is the value we intend to use on Unichain

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

        // Since in the call to FlashblockNumber.initialize above we set the initial
        // flashblockIndex to be the final flashblock (numFlashblocksPerBlock - 1),
        // the next flashblock to exist will be in the following block. So we update
        // the block number accordingly. This saves us from having to do this in every test,
        // just to get the the blockchain into a sane state for us to test how FlashblockNumber
        // works
        vm.roll(block.number + 1);
    }

    function test_InitialState() public view {
        assertTrue(block.number - 1 == flashblockNumber.lastL2BlockNumber());
        assertTrue(flashblockNumber.isBuilder(builder1));
        assertTrue(flashblockNumber.isBuilder(builder2));
        assertFalse(flashblockNumber.isBuilder(nonBuilder));
        assertEq(flashblockNumber.getFlashblockNumber(), 0);
    }

    function test_InvalidInitialize(uint256 _numFlashblocksPerBlock, uint256 initialFlashblockIndex) public {
        vm.assume(initialFlashblockIndex >= _numFlashblocksPerBlock);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlashblockNumber.FlashblockIndexTooLarge.selector, initialFlashblockIndex, _numFlashblocksPerBlock
            )
        );
        UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeCall(
                FlashblockNumber.initialize, (owner, initialBuilders, _numFlashblocksPerBlock, initialFlashblockIndex)
            )
        );
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
        assertEq(flashblockNumber.lastL2BlockNumber(), block.number);
    }

    function test_IncrementFlashblockNumber_MultipleBlockGap() public {
        vm.roll(block.number + 5);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();

        assertEq(flashblockNumber.getFlashblockNumber(), 0);
        assertEq(flashblockNumber.lastL2BlockNumber(), block.number);
    }

    function test_IncrementFlashblockNumber_OnlyBuilder() public {
        vm.prank(nonBuilder);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, nonBuilder));
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
        vm.expectEmit();
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
        emit IFlashblockNumber.FlashblockIncremented(0);
        flashblockNumber.incrementFlashblockNumber();

        vm.prank(builder1);
        vm.expectEmit();
        emit IFlashblockNumber.FlashblockIncremented(1);
        flashblockNumber.incrementFlashblockNumber();

        vm.roll(block.number + 1);

        vm.prank(builder2);
        vm.expectEmit();
        emit IFlashblockNumber.FlashblockIncremented(0);
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_GetFlashblockNumber() public {
        assertEq(flashblockNumber.getFlashblockNumber(), 0);

        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);
    }

    // This test ensures that getFlashblockNumber() does not return an index greater than numFlashblocksPerBlock - 1,
    // and that incrementFlashblockNumber() properly resets the index at block boundaries
    function test_GetFlashblockNumberFailWithIndexGreaterThanFlashblockNumber() public {
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
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.InvalidFlashblockNumberUpdate.selector));

        flashblockNumber.incrementFlashblockNumber();

        // Roll to next block and check reset
        vm.roll(block.number + 1);
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);
    }

    function testFuzz_AlwaysRevertsWhenFlashblockIndexExceedsNumFlashblocksPerBlock(
        uint8 _numFlashblocksPerBlock,
        uint256 numIncrements
    ) public {
        vm.assume(_numFlashblocksPerBlock > 1 && _numFlashblocksPerBlock <= 10);
        vm.assume(numIncrements > 0 && numIncrements <= 100);

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
        vm.roll(block.number + 1);

        // we'll increment the flashblock number `numIncrements` times, and we'll
        for (uint256 i = 0; i < numIncrements; i++) {
            if (flashblockNumber.getFlashblockNumber() == _numFlashblocksPerBlock - 1) {
                vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.InvalidFlashblockNumberUpdate.selector));
                vm.prank(builder1);
                flashblockNumber.incrementFlashblockNumber();

                // we saw the expected revert, now let's advance the block and continue to
                // test the next increment
                vm.roll(block.number + 1);
            } else {
                vm.prank(builder1);
                flashblockNumber.incrementFlashblockNumber();
            }
        }
    }

    function testFuzz_MonotonicityWithinBlock(uint8 increments, uint256 builderIndex) public {
        vm.assume(increments > 0 && increments < 100);
        vm.assume(builderIndex < initialBuilders.length); // use arbitrary builder for increased fuzz coverage

        vm.prank(initialBuilders[builderIndex]);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 0);

        for (uint256 i = 1; i < increments; i++) {
            uint256 expectedIndex = i % numFlashblocksPerBlock;

            // simulate the builder checking offchain that it's time
            // for a new block, which happens every multiple of
            // `numFlashblocksPerBlock` increments (e.g. every 5th, 10th,
            // 15th, etc... increment if numFlashblocksPerBlock == 5)
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
    // the `blockJumps` is the number of times the block number will advance.
    // the `numBlocksToJump` is the gap size of the number of blocks to jump forward. This
    // helps fuzz the case where the remote builder fails to build a block for `numBlocksToJump` blocks
    function testFuzz_ResetAcrossBlocks(uint8 blockJumps, uint8 numBlocksToJump) public {
        vm.assume(blockJumps > 0 && blockJumps < 20);
        vm.assume(numBlocksToJump >= 1 && numBlocksToJump <= 5);

        uint256 currentBlock = block.number;

        for (uint256 i = 0; i < blockJumps; i++) {
            for (uint256 increment = 0; increment < numFlashblocksPerBlock; increment++) {
                vm.prank(builder1);
                vm.expectEmit();
                emit IFlashblockNumber.FlashblockIncremented(increment);
                flashblockNumber.incrementFlashblockNumber();

                assertEq(flashblockNumber.getFlashblockNumber(), increment);
                assertEq(flashblockNumber.lastL2BlockNumber(), currentBlock);
            }

            currentBlock += numBlocksToJump;
            vm.roll(currentBlock);
        }
    }

    // fuzz the invariant that the result of getFlashblockNumber should never be greater than
    // or equal to numFlashblocksPerBlock()
    function testFuzz_FlashblockNeverGreaterOrEqualToNumFlashblocksPerBlock(
        uint8 _numFlashblocksPerBlockUint8,
        uint8 _numBlocksToTestUint8,
        uint8 _probabilityMissFlashblockUint8
    ) public {
        // Note: we need the fuzzer to generate uint8 versions of our fuzzed inputs because
        // if we use uint256, we'll get the error:
        // `vm.assume` rejected too many inputs (65536 allowed)
        // because our assumed range of valid inputs is such a small subset
        // of the range of uint256 values :shrug

        vm.assume(_numFlashblocksPerBlockUint8 >= 1 && _numFlashblocksPerBlockUint8 <= 10);
        uint256 _numFlashblocksPerBlock = uint256(_numFlashblocksPerBlockUint8);

        // 1 to 10 blocks gives us good coverage while not blowing up the runtime
        // of the fuzz test
        vm.assume(_numBlocksToTestUint8 >= 1 && _numBlocksToTestUint8 <= 10);
        uint256 _numBlocksToTest = uint256(_numBlocksToTestUint8);

        // better simulate reality by allowing some probability that a flashblock
        // increment will fail to occur
        vm.assume(_probabilityMissFlashblockUint8 >= 0 && _probabilityMissFlashblockUint8 <= 100);
        uint256 _probabilityMissFlashblock = uint256(_probabilityMissFlashblockUint8);

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
        vm.roll(block.number + 1); // bump the block so that we start in a sane state for a newly
        // deployed FlashblockNumber

        for (uint256 i = 0; i < _numBlocksToTest; i++) {
            for (uint256 j = 0; j < _numFlashblocksPerBlock; j++) {
                bool shouldMissFlashblock = vm.randomUint(0, 100) <= _probabilityMissFlashblock;

                if (!shouldMissFlashblock) {
                    vm.prank(builder1);
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
