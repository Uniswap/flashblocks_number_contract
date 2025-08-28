// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {WorkloadId} from "@flashbots/flashtestations/interfaces/IBlockBuilderPolicy.sol";
import {IFlashtestationRegistry} from "@flashbots/flashtestations/interfaces/IFlashtestationRegistry.sol";
import {IBlockBuilderPolicy} from "@flashbots/flashtestations/interfaces/IBlockBuilderPolicy.sol";
import {IFlashblockNumber} from "./IFlashblockNumber.sol";

/**
 * @notice Cached workload information for gas optimization
 * @dev Stores computed workloadId and associated quoteHash to avoid expensive recomputation
 */
struct CachedWorkload {
    /// @notice The computed workload identifier
    WorkloadId workloadId;
    /// @notice The keccak256 hash of the raw quote used to compute this workloadId
    bytes32 quoteHash;
}

/**
 * @title FlashblockNumber
 * @notice Implementation contract for tracking whenever a remote builder builds a flashblock.
 * This allows bundles and onchain contracts to specify the range of flashblock number are valid for a
 * transaction to occur in, similar to Solidity's block.number
 * @dev The only addresses that are able to increment the flashblock number are TEE block builders permissioned
 * by Unichain + Flashbots. This ensures that only builders can increment the flashblock number, and that the
 * flashblock number is monotonically increasing.
 * @dev You can find the BlockBuilderPolicy contract at https://github.com/flashbots/flashtestations/blob/main/src/BlockBuilderPolicy.sol
 * @dev You can find the Flashbots builder code at https://github.com/flashbots/op-rbuilder/tree/main/crates/op-rbuilder
 * @dev The contract is upgradeable so that the code can be updated without requiring third-party contracts
 * that reference to point to the new implementation. This allows the contract to be updated without
 * requiring a new deployment, and without requiring a new deployment of the contracts that reference
 * the flashblock number.
 */
contract FlashblockNumber is IFlashblockNumber, Initializable, UUPSUpgradeable, OwnableUpgradeable, EIP712Upgradeable {
    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------
    /// @notice EIP-712 Typehash for the `permitIncrementFlashblockNumber` function
    bytes32 public constant PERMIT_INCREMENT_TYPEHASH =
        keccak256("PermitIncrementFlashblock(uint256 currentFlashblockNumber)");

    /// -----------------------------------------------------------------------
    /// Storage
    /// -----------------------------------------------------------------------

    /// @notice a monotonically increasing sequencer number that represents the count of flashblocks
    /// that have been built by the remote builder. This allows bundles and onchain contracts to specify
    /// the range of flashblock number are valid for a transaction to occur in, similar to Solidity's
    /// block.number
    uint256 public flashblockNumber;

    /// @dev Deprecated: this mapping is no longer used after we migrated to using the
    /// BlockBuilderPolicy contract to authorize builders. But we must keep it here
    /// to ensure upgraded contracts still function correctly
    mapping(address => bool) public isBuilder;

    /// @notice Address of the FlashtestationRegistry contract used to get the registration status of builders
    IFlashtestationRegistry private flashtestationRegistry;

    /// @notice Address of the BlockBuilderPolicy contract used to authorize builders
    IBlockBuilderPolicy private blockBuilderPolicy;

    /// @notice Cache of computed workloadIds to avoid expensive recomputation
    /// @dev Maps teeAddress to cached workload information for gas optimization
    mapping(address teeAddress => CachedWorkload) private cachedWorkloads;

    /// -----------------------------------------------------------------------
    /// Initializer/Reinitializers
    /// -----------------------------------------------------------------------

    /**
     * @notice Initialize the contract
     * @param _owner Address that will own this contract
     * @param _flashtestationRegistry Address of the FlashtestationRegistry contract used to get the registration status of builders
     * @param _blockBuilderPolicy Address of the BlockBuilderPolicy contract used to authorize builders
     */
    function initialize(address _owner, address _flashtestationRegistry, address _blockBuilderPolicy)
        public
        initializer
    {
        __Ownable_init(_owner);
        flashtestationRegistry = IFlashtestationRegistry(_flashtestationRegistry);
        blockBuilderPolicy = IBlockBuilderPolicy(_blockBuilderPolicy);
        __UUPSUpgradeable_init();
        __EIP712_init("FlashblockNumber", "1");
    }

    /**
     * @notice Sets the registry and policy contracts after the contract is upgraded. This should
     * only be called as the contract is upgraded for the first time (v1 -> v2)
     * @param _flashtestationRegistry Address of the FlashtestationRegistry contract used to get the registration status of builders
     * @param _blockBuilderPolicy Address of the BlockBuilderPolicy contract used to authorize builders
     * @custom:oz-upgrades-validate-as-initializer
     */
    function reinitializeV2(address _flashtestationRegistry, address _blockBuilderPolicy) public reinitializer(2) {
        __Ownable_init(owner());
        __UUPSUpgradeable_init();
        __EIP712_init("FlashblockNumber", "1");
        flashtestationRegistry = IFlashtestationRegistry(_flashtestationRegistry);
        blockBuilderPolicy = IBlockBuilderPolicy(_blockBuilderPolicy);
    }

    /// -----------------------------------------------------------------------
    /// Core Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function incrementFlashblockNumber() external override {
        _incrementFlashblockNumber(msg.sender);
    }

    /// @inheritdoc IFlashblockNumber
    function permitIncrementFlashblockNumber(uint256 currentFlashblockNumber, bytes memory signature)
        external
        override
    {
        // compare the flashblock number the caller _thinks_ is the current flashblock number
        // with the actual current flashblock number. This prevents EIP-712 replay attacks, because
        // the signature will be forever invalid once the flashblock number is incremented in
        // _incrementFlashblockNumber
        require(
            currentFlashblockNumber == flashblockNumber,
            MismatchedFlashblockNumber(currentFlashblockNumber, flashblockNumber)
        );

        bytes32 digest = hashTypedDataV4(computeStructHash(currentFlashblockNumber));
        address signer = ECDSA.recover(digest, signature);

        _incrementFlashblockNumber(signer);
    }

    /// @notice Increment the flashblock number and emit the FlashblockIncremented event
    /// @param builder The builder that is incrementing the flashblock number
    /// @custom:throws NonBuilderAddress if the builder is not an authorized builder
    function _incrementFlashblockNumber(address builder) internal {
        // Check if the caller is an authorized TEE block builder for our Policy and update cache
        bool allowed = _cachedIsAllowedPolicy(builder);
        require(allowed, NonBuilderAddress(builder));

        flashblockNumber++;
        emit FlashblockIncremented(flashblockNumber);
    }

    /// @notice Authorization function to check if the caller is a TEE block builder permissioned by the Policy
    /// to update the flashblock number
    /// @dev The FlashblockNumber contract relies on the BlockBuilderPolicy contract to authorize builders.
    /// This function uses caching to bring the gas cost down significantly
    /// @dev A careful reader will notice that this function does not delete stale cache entries. It overwrites them
    /// if the underlying TEE registration is still valid. But for stale cache entries in every other scenario, the
    /// cache entry persists indefinitely. This is because every other instance results in a return value of (false, 0)
    /// to the caller (which is always the _incrementFlashblockNumber function) and it immediately reverts. This is an unfortunate
    /// consequence of our need to make this function as gas-efficient as possible, otherwise we would try to cleanup
    /// stale cache entries
    /// @param teeAddress The TEE-controlled address
    /// @return True if the TEE is using an approved workload in the policy
    function _cachedIsAllowedPolicy(address teeAddress) private returns (bool) {
        // Get the current registration status (fast path)
        (bool isValid, bytes32 quoteHash) = flashtestationRegistry.getRegistrationStatus(teeAddress);
        if (!isValid) {
            return false;
        }

        // Now, check if we have a cached workload for this TEE
        CachedWorkload memory cached = cachedWorkloads[teeAddress];

        // Check if we've already fetched and computed the workloadId for this TEE
        if (WorkloadId.unwrap(cached.workloadId) != 0 && cached.quoteHash == quoteHash) {
            // Cache hit - verify the workload is still a part of this policy's approved workloads
            if (bytes(blockBuilderPolicy.getWorkloadMetadata(cached.workloadId).commitHash).length > 0) {
                return true;
            } else {
                // The workload is no longer approved, so the policy is no longer valid for this TEE\
                return false;
            }
        } else {
            // Cache miss or quote changed - use the view function to get the result
            (bool allowed, WorkloadId workloadId) = blockBuilderPolicy.isAllowedPolicy(teeAddress);

            if (allowed) {
                // Update cache with the new workload ID
                cachedWorkloads[teeAddress] = CachedWorkload({workloadId: workloadId, quoteHash: quoteHash});
            }

            return allowed;
        }
    }

    /// -----------------------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function getFlashblockNumber() external view override returns (uint256) {
        return flashblockNumber;
    }

    /// @inheritdoc IFlashblockNumber
    function registry() external view override returns (address) {
        return address(flashtestationRegistry);
    }

    /// @inheritdoc IFlashblockNumber
    function policy() external view override returns (address) {
        return address(blockBuilderPolicy);
    }

    /// -----------------------------------------------------------------------
    /// Upgrade Authorization
    /// -----------------------------------------------------------------------

    /// @notice Authorize an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation contract
    /// @custom:access onlyOwner
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// -----------------------------------------------------------------------
    /// EIP-712 Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Computes the struct hash for the EIP-712 signature
     * @dev This is useful for when both onchain and offchain users want to compute the struct hash
     * for the EIP-712 signature, and then use it to verify the signature
     * @param currentFlashblockNumber The current flashblock number to use as nonce
     * @return The struct hash for the EIP-712 signature
     */
    function computeStructHash(uint256 currentFlashblockNumber) public pure returns (bytes32) {
        return keccak256(abi.encode(PERMIT_INCREMENT_TYPEHASH, currentFlashblockNumber));
    }

    /**
     * @notice Computes the digest for the EIP-712 signature
     * @dev This is useful for when both onchain and offchain users want to compute the digest
     * for the EIP-712 signature, and then use it to verify the signature
     * @param structHash The struct hash for the EIP-712 signature
     * @return The digest for the EIP-712 signature
     */
    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }
}
