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
        // TODO: Implement increment logic
    }

    /// -----------------------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function getFlashblockNumber() external view override returns (uint256) {
        // TODO: Implement getter
        return 0;
    }

    /// -----------------------------------------------------------------------
    /// Governance Functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IFlashblockNumber
    function addBuilder(address builder) external override {
        // TODO: Implement add builder logic
    }

    /// @inheritdoc IFlashblockNumber
    function removeBuilder(address builder) external override {
        // TODO: Implement remove builder logic
    }

    /// -----------------------------------------------------------------------
    /// Upgrade Authorization
    /// -----------------------------------------------------------------------

    /// @notice Authorize an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation contract
    /// @custom:access onlyOwner
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
