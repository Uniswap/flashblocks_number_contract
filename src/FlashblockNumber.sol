// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "./IFlashblockNumber.sol";

/**
 * @title FlashblockNumber
 * @notice Implementation contract for tracking flashblock indices within L2 blocks
 * @dev Upgradeable contract that provides onchain contracts access to current flashblock number
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

    /// @inheritdoc IFlashblockNumber
    uint256 public override numFlashblocksPerBlock;

    uint256 public flashblockIndex;

    /// @inheritdoc IFlashblockNumber
    uint256 public override lastL2BlockNumber;

    /// @inheritdoc IFlashblockNumber
    mapping(address => bool) public override isBuilder;

    /// -----------------------------------------------------------------------
    /// Initializer
    /// -----------------------------------------------------------------------

    /**
     * @notice Initialize the contract
     * @notice It is the duty of the deployer to specify the flashblock index so that no matter which
     * flashblock this contract is deployed on, the flashblock index will match the actual flashblock
     * index within the block. If we didn't do this, the flashblock index might be different from the
     * actual flashblock index within the block, and all flashblock numbers will be off by the difference
     * between the flashblock index and the actual flashblock index within the block. The simplest way
     * to set the flashblock index is for the deployer to set the flashblock index to `_numFlashblocksPerBlock   - 1`,
     * and always deploy this contract in the last flashblock of the block. Then, all future calls to `incrementFlashblockNumber`
     * will increment the flashblock index by 1, and the flashblock number will match the flashblock index.
     * @dev The flashblock index is the index of the flashblock within the block when this
     * contract is first deployed. We need the deployer to specify the flashblock index so that
     * so that no matter which flashblock this contract is deployed on, the flashblock index will
     * set on FlashblockNumber will match the actual flashblock index within the block. If we didn't
     * do this, the flashblock index might be different from the actual flashblock index within the block,
     * and all flashblock numbers will be off by the difference between the flashblock index and the
     * actual flashblock index within the block
     * @param _owner Address that will own this contract
     * @param _initialBuilders Array of initial authorized builder addresses
     * @param _numFlashblocksPerBlock Number of flashblocks per block
     * @param _flashblockIndex Initial flashblock index
     */
    function initialize(
        address _owner,
        address[] memory _initialBuilders,
        uint256 _numFlashblocksPerBlock,
        uint256 _flashblockIndex
    ) public initializer {
        require(
            _flashblockIndex < _numFlashblocksPerBlock,
            "FlashblockNumber: flashblock index must be less than numFlashblocksPerBlock"
        );

        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        __EIP712_init("FlashblockNumber", "1");

        // Add initial builders
        for (uint256 i = 0; i < _initialBuilders.length; i++) {
            isBuilder[_initialBuilders[i]] = true;
            emit BuilderAdded(_initialBuilders[i]);
        }

        lastL2BlockNumber = block.number;
        numFlashblocksPerBlock = _numFlashblocksPerBlock;
        flashblockIndex = _flashblockIndex;
    }

    /// -----------------------------------------------------------------------
    /// Core Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function incrementFlashblockNumber() external override {
        require(isBuilder[msg.sender], NonBuilderAddress(msg.sender));

        if (flashblockIndex == numFlashblocksPerBlock - 1) {
            // the current index is at the largest value it can be (according to numFlashblocksPerBlock),
            // so this call to `incrementFlashblockNumber()` must be happening in a new block, and
            // we should reset the index back to 0 to indicate we're storing the index for a new
            // block. If we didn't make this check, then the index could be incremented to a value
            // greater than the number of flashblocks in a block, which doesn't make any sense and must
            // never happen
            require(block.number > lastL2BlockNumber, InvalidFlashblockNumberUpdate(block.number, lastL2BlockNumber));
            flashblockIndex = 0;
        } else {
            // this is the common case where the builder has called incrementFlashblockNumber
            // at the beginning of the flashblock and it's not the last flashblock, so we simply
            // increment
            assert(flashblockIndex < numFlashblocksPerBlock - 1);
            flashblockIndex++;
        }

        emit FlashblockIncremented(flashblockIndex);
    }

    /// -----------------------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function getFlashblockNumber() external view override returns (uint256) {
        if (block.number != lastL2BlockNumber) {
            // this check ensures the contract is robust against failures in the remote builder.
            // Specifically it handles the edge-case where the remote builder failed to build a
            // block and the L2 sequencer fell back to building locally, and thus the builder did
            // not make a call to `incrementFlashblockNumber` (which sets `lastL2BlockNumber` equal to
            // `block.number`). In this scenario our contract cannot make any claim to what the
            // flashblockNumber is, so we default to `0` which represents a regular non-flashblock
            // block
            return 0;
        }

        // since the `block.number` and `lastL2BlockNumber` are the same, we know the
        // builder must have called `incrementFlashblockNumber` within this transaction's
        // block, so we can confidently return the current `flashblockIndex`
        return flashblockIndex;
    }

    /// -----------------------------------------------------------------------
    /// Governance Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function addBuilder(address builder) external override onlyOwner {
        require(!isBuilder[builder], AddressIsAlreadyABuilder(builder));

        isBuilder[builder] = true;
    }

    /// @inheritdoc IFlashblockNumber
    function removeBuilder(address builder) external override onlyOwner {
        require(isBuilder[builder], BuilderDoesNotExist(builder));

        delete isBuilder[builder];
    }

    /// -----------------------------------------------------------------------
    /// Upgrade Authorization
    /// -----------------------------------------------------------------------

    /// @notice Authorize an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation contract
    /// @custom:access onlyOwner
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
