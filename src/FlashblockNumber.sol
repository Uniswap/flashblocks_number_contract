// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./IFlashblockNumber.sol";

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
contract FlashblockNumber is
    IFlashblockNumber,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    EIP712Upgradeable
{
    /// -----------------------------------------------------------------------
    /// Storage
    /// -----------------------------------------------------------------------

    /// @notice a monotonically increasing sequencer number that represents the count of flashblocks
    /// that have been built by the remote builder. This allows bundles and onchain contracts to specify
    /// the range of flashblock number are valid for a transaction to occur in, similar to Solidity's
    /// block.number
    uint256 public flashblockNumber;

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
     * @param _initialBuilders Array of initial authorized builder addresses
     */
    function initialize(address _owner, address[] memory _initialBuilders) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        __EIP712_init("FlashblockNumber", "1");

        // Add initial builders
        for (uint256 i = 0; i < _initialBuilders.length; i++) {
            isBuilder[_initialBuilders[i]] = true;
            emit BuilderAdded(_initialBuilders[i]);
        }
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
        require(isBuilder[builder], NonBuilderAddress(builder));

        flashblockNumber++;
        emit FlashblockIncremented(flashblockNumber);
    }

    /// -----------------------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function getFlashblockNumber() external view override returns (uint256) {
        return flashblockNumber;
    }

    /// -----------------------------------------------------------------------
    /// Governance Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function addBuilder(address builder) external override onlyOwner {
        require(!isBuilder[builder], AddressIsAlreadyABuilder(builder));

        isBuilder[builder] = true;
        emit BuilderAdded(builder);
    }

    /// @inheritdoc IFlashblockNumber
    function removeBuilder(address builder) external override onlyOwner {
        require(isBuilder[builder], BuilderDoesNotExist(builder));

        delete isBuilder[builder];
        emit BuilderRemoved(builder);
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
