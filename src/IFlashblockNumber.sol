// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlashblockNumber
 * @notice Interface for tracking flashblock indices within L2 blocks
 * @dev Provides onchain contracts access to current flashblock number, similar to block.number
 */
interface IFlashblockNumber {
    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /**
     * @notice Emitted when flashblock index is incremented
     * @param newFlashblockIndex The new flashblock index (0-indexed within each L2 block)
     */
    event FlashblockIncremented(uint256 newFlashblockIndex);

    /**
     * @notice Emitted when a builder is added to the authorized list
     * @param builder Address of the added builder
     */
    event BuilderAdded(address indexed builder);

    /**
     * @notice Emitted when a builder is removed from the authorized list
     * @param builder Address of the removed builder
     */
    event BuilderRemoved(address indexed builder);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error NonBuilderAddress(address addr);
    error InvalidFlashblockNumberUpdate(uint256 currentBlockNumber, uint256 lastL2BlockNumber);
    error AddressIsAlreadyABuilder(address addr);
    error BuilderDoesNotExist(address addr);

    /// -----------------------------------------------------------------------
    /// Core Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Increment the flashblock index once per flashblock
     * @dev Must be called by authorized builder as first tx in flashblock
     *      Automatically resets to 0 on new L2 block, otherwise increments by 1
     * @custom:throws NotBuilder if caller is not an authorized builder
     */
    function incrementFlashblockNumber() external;

    /// -----------------------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Get the current flashblock number
     * @return The current flashblock index (0-indexed within current L2 block)
     */
    function getFlashblockNumber() external view returns (uint256);

    /**
     * @notice Get the L2 block number when flashblock was last updated
     * @return The L2 block number of last update
     */
    function lastL2BlockNumber() external view returns (uint256);

    /**
     * @notice Check if an address is an authorized builder
     * @param builder Address to check
     * @return True if the address is an authorized builder
     */
    function isBuilder(address builder) external view returns (bool);

    /**
     * @notice Get the configured number of flashblocks per L2 block
     * @return The number of flashblocks per block
     */
    function numFlashblocksPerBlock() external view returns (uint256);

    /// -----------------------------------------------------------------------
    /// Governance Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Add a new authorized builder
     * @param builder Address of builder to add
     * @custom:throws Exists if builder is already authorized
     * @custom:access onlyOwner
     */
    function addBuilder(address builder) external;

    /**
     * @notice Remove an authorized builder
     * @param builder Address of builder to remove
     * @custom:throws Missing if builder is not currently authorized
     * @custom:access onlyOwner
     */
    function removeBuilder(address builder) external;
}
