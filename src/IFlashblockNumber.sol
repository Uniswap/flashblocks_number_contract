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
     * @param newFlashblockIndex The new flashblock index
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
    error AddressIsAlreadyABuilder(address addr);
    error BuilderDoesNotExist(address addr);
    error MismatchedFlashblockNumber(uint256 expectedFlashblockNumber, uint256 actualFlashblockNumber);

    /// -----------------------------------------------------------------------
    /// Core Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Increment the flashblock index once per flashblock
     * @dev Must be called by authorized builder as first tx in flashblock
     * @custom:throws NonBuilderAddress if caller is not an authorized builder
     */
    function incrementFlashblockNumber() external;

    /**
     * @notice Increment the flashblock index once per flashblock using a signature
     * @dev Must be called by authorized builder as first tx in flashblock
     * @dev The currentFlashblockNumber is used to prevent replay attacks
     * @param currentFlashblockNumber The current flashblock number
     * @param signature The signature of the builder
     * @custom:throws NonBuilderAddress if caller is not an authorized builder
     * @custom:throws MismatchedFlashblockNumber if the current flashblock number does not match the expected flashblock number
     */
    function permitIncrementFlashblockNumber(uint256 currentFlashblockNumber, bytes memory signature) external;

    /// -----------------------------------------------------------------------
    /// View Functions
    /// -----------------------------------------------------------------------

    /**
     * @notice Get the current flashblock number
     * @return The current flashblock index
     */
    function getFlashblockNumber() external view returns (uint256);

    /**
     * @notice Get the address of the FlashtestationRegistry contract
     * @dev This is used to verify that the builder is registered with the FlashtestationRegistry
     * @dev You can find the FlashtestationRegistry contract at https://github.com/flashbots/flashtestations/blob/main/src/FlashtestationRegistry.sol
     * @return The address of the FlashtestationRegistry contract
     */
    function registry() external view returns (address);

    /**
     * @notice Get the address of the BlockBuilderPolicy contract
     * @dev This is used to verify that the builder is authorized to build flashblocks
     * @dev You can find the BlockBuilderPolicy contract at https://github.com/flashbots/flashtestations/blob/main/src/BlockBuilderPolicy.sol
     * @return The address of the BlockBuilderPolicy contract
     */
    function policy() external view returns (address);
}
