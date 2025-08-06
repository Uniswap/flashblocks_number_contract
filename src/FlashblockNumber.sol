// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
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
        require(isBuilder[msg.sender], NonBuilderAddress(msg.sender));

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
}
