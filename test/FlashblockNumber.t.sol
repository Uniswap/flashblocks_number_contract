// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {FlashblockNumber} from "../src/FlashblockNumber.sol";
import {IFlashblockNumber} from "../src/IFlashblockNumber.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockFlashtestationRegistry} from "./mocks/MockFlashtestationRegistry.sol";
import {MockBlockBuilderPolicy, WorkloadId} from "./mocks/MockBlockBuilderPolicy.sol";

contract FlashblockNumberTest is Test {
    IFlashblockNumber public flashblockNumber;
    MockFlashtestationRegistry public registry;
    MockBlockBuilderPolicy public policy;

    address public owner = makeAddr("owner");
    address public builder1 = makeAddr("builder1");
    address public builder2 = makeAddr("builder2");
    address public nonBuilder = makeAddr("nonBuilder");
    address implementation = address(new FlashblockNumber());

    // private keys cannot be greater than or equal to this value
    uint256 public constant SECP256K1_CURVE_LIMIT =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;

    // WorkloadId for testing
    WorkloadId public testWorkloadId = WorkloadId.wrap(keccak256("test-workload"));
    bytes32 public testQuoteHash = keccak256("test-quote");

    function setUp() public {
        // Deploy mock contracts
        registry = new MockFlashtestationRegistry();
        policy = new MockBlockBuilderPolicy();

        // Set up mock state for builder1 and builder2
        registry.setRegistrationStatus(builder1, true, testQuoteHash);
        registry.setRegistrationStatus(builder2, true, testQuoteHash);

        policy.setPolicyStatus(builder1, true, testWorkloadId);
        policy.setPolicyStatus(builder2, true, testWorkloadId);

        // Set up workload metadata so the workload is considered valid
        string[] memory sourceLocators = new string[](1);
        sourceLocators[0] = "github.com/test/repo";
        policy.setWorkloadMetadata(testWorkloadId, "abc123", sourceLocators);

        // Deploy FlashblockNumber with the mock registry and policy
        vm.prank(owner);
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation, abi.encodeCall(FlashblockNumber.initialize, (owner, address(registry), address(policy)))
        );
        flashblockNumber = IFlashblockNumber(proxy);
    }

    function test_InitialState() public view {
        assertEq(flashblockNumber.registry(), address(registry));
        assertEq(flashblockNumber.policy(), address(policy));
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

    function test_AuthorizedBuilder_CanIncrement() public {
        // Test that an authorized builder can increment
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 1);
    }

    function test_UnauthorizedBuilder_CannotIncrement() public {
        // Test that a builder without registration cannot increment
        vm.prank(nonBuilder);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, nonBuilder));
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_RevokedRegistration_CannotIncrement() public {
        // Revoke builder1's registration
        registry.setRegistrationStatus(builder1, false, testQuoteHash);

        vm.prank(builder1);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, builder1));
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_RevokedPolicy_CannotIncrement() public {
        // Revoke builder1's policy status
        policy.setPolicyStatus(builder1, false, testWorkloadId);

        vm.prank(builder1);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, builder1));
        flashblockNumber.incrementFlashblockNumber();
    }

    function test_InvalidWorkload_CannotIncrement() public {
        // First increment to populate the cache
        vm.prank(builder1);
        flashblockNumber.incrementFlashblockNumber();
        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        // Remove workload metadata to make it invalid
        string[] memory emptyLocators = new string[](0);
        policy.setWorkloadMetadata(testWorkloadId, "", emptyLocators);

        // Now the cached workload check should fail
        vm.prank(builder1);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, builder1));
        flashblockNumber.incrementFlashblockNumber();
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

    // This test is to ensure that dynamic builder authorization is working as expected
    // by testing multiple builders with different authorization states
    function testFuzz_DynamicBuilderAuthorization(address[] memory newBuilders) public {
        vm.assume(newBuilders.length > 0 && newBuilders.length <= 10);

        for (uint256 i = 0; i < newBuilders.length; i++) {
            vm.assume(newBuilders[i] != address(0));
            vm.assume(newBuilders[i] != builder1 && newBuilders[i] != builder2);

            // Ensure no duplicates in the array
            bool duplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (newBuilders[i] == newBuilders[j]) {
                    duplicate = true;
                    break;
                }
            }
            vm.assume(!duplicate);

            // Set up authorization for the new builder
            registry.setRegistrationStatus(newBuilders[i], true, testQuoteHash);
            policy.setPolicyStatus(newBuilders[i], true, testWorkloadId);

            // Verify the new builder can increment
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

        // Set up authorization for the signer
        registry.setRegistrationStatus(signerBuilder, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder, true, testWorkloadId);

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

        // Set up authorization for the signer
        registry.setRegistrationStatus(signerBuilder, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder, true, testWorkloadId);

        // Create signature for flashblock number 5, but current is 0
        bytes memory signature = _signIncrement(builder1PrivateKey, 5);

        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.MismatchedFlashblockNumber.selector, 5, 0));
        flashblockNumber.permitIncrementFlashblockNumber(5, signature);
    }

    function test_permitIncrementFlashblockNumber_ReplayAttackPrevention() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        // Set up authorization for the signer
        registry.setRegistrationStatus(signerBuilder, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder, true, testWorkloadId);

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

        // Ensure the signer is not authorized (not registered or not in policy)
        // No need to set up authorization for this address

        bytes memory signature = _signIncrement(nonBuilderPrivateKey, 0);

        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, nonBuilderSigner));
        flashblockNumber.permitIncrementFlashblockNumber(0, signature);
    }

    function test_permitIncrementFlashblockNumber_AuthorizationRevocation() public {
        uint256 builder1PrivateKey = 0x1234;
        uint256 builder2PrivateKey = 0x5678;
        address signerBuilder1 = vm.addr(builder1PrivateKey);
        address signerBuilder2 = vm.addr(builder2PrivateKey);

        // Set up authorization for both builders with different workloads
        WorkloadId workloadId1 = WorkloadId.wrap(keccak256("builder1-workload"));
        WorkloadId workloadId2 = WorkloadId.wrap(keccak256("builder2-workload"));

        // Set up workload metadata for both
        string[] memory locators1 = new string[](1);
        locators1[0] = "github.com/builder1/repo";
        policy.setWorkloadMetadata(workloadId1, "abc123", locators1);

        string[] memory locators2 = new string[](1);
        locators2[0] = "github.com/builder2/repo";
        policy.setWorkloadMetadata(workloadId2, "def456", locators2);

        registry.setRegistrationStatus(signerBuilder1, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder1, true, workloadId1);
        registry.setRegistrationStatus(signerBuilder2, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder2, true, workloadId2);

        // Builder1 increments via meta-transaction
        bytes memory signature1 = _signIncrement(builder1PrivateKey, 0);
        flashblockNumber.permitIncrementFlashblockNumber(0, signature1);
        assertEq(flashblockNumber.getFlashblockNumber(), 1);

        // Revoke builder1's authorization by removing their workload metadata
        string[] memory emptyLocators = new string[](0);
        policy.setWorkloadMetadata(workloadId1, "", emptyLocators);

        // Builder1's old signature for flashblock 1 should now fail
        bytes memory oldSignature = _signIncrement(builder1PrivateKey, 1);
        vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, signerBuilder1));
        flashblockNumber.permitIncrementFlashblockNumber(1, oldSignature);

        // But builder2 can still increment (uses different workload)
        bytes memory signature2 = _signIncrement(builder2PrivateKey, 1);
        flashblockNumber.permitIncrementFlashblockNumber(1, signature2);
        assertEq(flashblockNumber.getFlashblockNumber(), 2);
    }

    function test_permitIncrementFlashblockNumber_MixedUsage() public {
        uint256 builder1PrivateKey = 0x1234;
        address signerBuilder = vm.addr(builder1PrivateKey);

        // Set up authorization for the signer
        registry.setRegistrationStatus(signerBuilder, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder, true, testWorkloadId);

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

        // Set up authorization for the signer
        registry.setRegistrationStatus(signerBuilder, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder, true, testWorkloadId);

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

        // Set up authorization for the signer
        registry.setRegistrationStatus(signerBuilder, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder, true, testWorkloadId);

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

        // Set up authorization for the signer
        registry.setRegistrationStatus(signerBuilder, true, testQuoteHash);
        policy.setPolicyStatus(signerBuilder, true, testWorkloadId);

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
