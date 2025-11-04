// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {WorkloadId} from "@flashbots/flashtestations/interfaces/IBlockBuilderPolicy.sol";
import {IFlashtestationRegistry} from "@flashbots/flashtestations/interfaces/IFlashtestationRegistry.sol";
import "./IFlashblockNumber.sol";

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
 * @dev The only addresses that are able to increment the flashblock number are the builder addresses, which
 * are created within a TEE operated by builders like Flashbots. This ensures that only builders can
 * increment the flashblock number, and that the flashblock number is monotonically increasing.
 * @dev The contract is upgradeable so that the code can be updated without requiring third-party contracts
 * that reference to point to the new implementation. This allows the contract to be updated without
 * requiring a new deployment, and without requiring a new deployment of the contracts that reference
 * the flashblock number.
 */
contract FlashblockNumber is IFlashblockNumber, Initializable, UUPSUpgradeable, OwnableUpgradeable, EIP712Upgradeable {
    /// -----------------------------------------------------------------------
    /// Storage
    /// -----------------------------------------------------------------------
    /// @notice a monotonically increasing sequencer number that represents the count of flashblocks
    /// that have been built by the remote builder. This allows bundles and onchain contracts to specify
    /// the range of flashblock number are valid for a transaction to occur in, similar to Solidity's
    /// block.number
    uint256 public flashblockNumber;

    /// @notice Cache of computed workloadIds to avoid expensive recomputation
    /// @dev Maps teeAddress to cached workload information for gas optimization
    mapping(address teeAddress => CachedWorkload) private cachedWorkloads;

    /// @inheritdoc IFlashblockNumber
    mapping(address => bool) public override isBuilder;

    /// @notice EIP-712 Typehash for the `permitIncrementFlashblockNumber` function
    bytes32 public constant PERMIT_INCREMENT_TYPEHASH =
        keccak256("PermitIncrementFlashblock(uint256 currentFlashblockNumber)");

    /// -----------------------------------------------------------------------
    /// Initializer
    /// -----------------------------------------------------------------------

    /**
     * @notice Initialize the contract
     * @param _owner Address that will own this contract
     */
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        __EIP712_init("FlashblockNumber", "1");
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
        (bool allowed, WorkloadId workloadId) = _cachedIsAllowedPolicy(builder);
        require(allowed, UnauthorizedBlockBuilder(builder));
        // require(isBuilder[builder], NonBuilderAddress(builder));

        flashblockNumber++;
        emit FlashblockIncremented(flashblockNumber);
    }

    /// @notice isAllowedPolicy but with caching to reduce gas costs
    /// @dev This function is only used by the verifyBlockBuilderProof function, which needs to be as efficient as possible
    /// because it is called onchain for every flashblock. The workloadId is cached to avoid expensive recomputation
    /// @dev A careful reader will notice that this function does not delete stale cache entries. It overwrites them
    /// if the underlying TEE registration is still valid. But for stale cache entries in every other scenario, the
    /// cache entry persists indefinitely. This is because every other instance results in a return value of (false, 0)
    /// to the caller (which is always the verifyBlockBuilderProof function) and it immediately reverts. This is an unfortunate
    /// consequence of our need to make this function as gas-efficient as possible, otherwise we would try to cleanup
    /// stale cache entries
    /// @param teeAddress The TEE-controlled address
    /// @return True if the TEE is using an approved workload in the policy
    /// @return The workloadId of the TEE that is using an approved workload in the policy, or 0 if
    /// the TEE is not using an approved workload in the policy
    function _cachedIsAllowedPolicy(address teeAddress) private returns (bool, WorkloadId) {
        // Get the current registration status (fast path)
        (bool isValid, bytes32 quoteHash) = IFlashtestationRegistry(registry).getRegistrationStatus(teeAddress);
        if (!isValid) {
            return (false, WorkloadId.wrap(0));
        }

        // Now, check if we have a cached workload for this TEE
        CachedWorkload memory cached = cachedWorkloads[teeAddress];

        // Check if we've already fetched and computed the workloadId for this TEE
        bytes32 cachedWorkloadId = WorkloadId.unwrap(cached.workloadId);
        if (cachedWorkloadId != 0 && cached.quoteHash == quoteHash) {
            // Cache hit - verify the workload is still a part of this policy's approved workloads
            if (bytes(IBlockBuilderPolicy(policy).getWorkloadMetadata(cachedWorkloadId).commitHash).length > 0) {
                return (true, cached.workloadId);
            } else {
                // The workload is no longer approved, so the policy is no longer valid for this TEE\
                return (false, WorkloadId.wrap(0));
            }
        } else {
            // Cache miss or quote changed - use the view function to get the result
            (bool allowed, WorkloadId workloadId) = IBlockBuilderPolicy(policy).isAllowedPolicy(teeAddress);

            if (allowed) {
                // Update cache with the new workload ID
                cachedWorkloads[teeAddress] = CachedWorkload({workloadId: workloadId, quoteHash: quoteHash});
            }

            return (allowed, workloadId);
        }
    }

    /// -----------------------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function getFlashblockNumber() external view override returns (uint256) {
        return flashblockNumber;
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
