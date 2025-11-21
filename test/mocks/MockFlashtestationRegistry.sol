// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title MockFlashtestationRegistry
 * @notice Mock implementation of IFlashtestationRegistry for testing purposes
 * @dev This mock allows tests to simulate TEE registration validation without
 * requiring actual attestation verification
 */
contract MockFlashtestationRegistry {
    /// @notice Storage for registration status per TEE address
    mapping(address => RegistrationStatus) private registrations;

    /// @notice Struct to store registration data
    struct RegistrationStatus {
        bool isValid;
        bytes32 quoteHash;
    }

    /**
     * @notice Fetches only the validity status and quote hash for a given TEE address
     * @dev This is a gas-optimized version of getRegistration that only returns the minimal data
     * needed for caching optimizations in policy contracts
     * @param teeAddress The TEE-controlled address to check
     * @return isValid True if the TEE is registered and the attestation is valid
     * @return quoteHash The keccak256 hash of the raw quote
     */
    function getRegistrationStatus(address teeAddress) external view returns (bool isValid, bytes32 quoteHash) {
        RegistrationStatus memory status = registrations[teeAddress];
        return (status.isValid, status.quoteHash);
    }

    /**
     * @notice Sets the registration status for a TEE address (test helper)
     * @dev This function is only available in the mock for testing purposes
     * @param teeAddress The TEE-controlled address to set status for
     * @param _isValid The validity status to set
     * @param _quoteHash The quote hash to set
     */
    function setRegistrationStatus(address teeAddress, bool _isValid, bytes32 _quoteHash) external {
        registrations[teeAddress] = RegistrationStatus({isValid: _isValid, quoteHash: _quoteHash});
    }
}
