// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Workload identifier type
type WorkloadId is bytes32;

/**
 * @title MockBlockBuilderPolicy
 * @notice Mock implementation of IBlockBuilderPolicy for testing purposes
 * @dev This mock allows tests to simulate workload validation and policy checks
 * without requiring actual TEE attestation and policy verification
 */
contract MockBlockBuilderPolicy {
    /// @notice Metadata associated with a workload
    struct WorkloadMetadata {
        string commitHash;
        string[] sourceLocators;
    }

    /// @notice Storage for workload metadata by workloadId
    mapping(bytes32 => WorkloadMetadata) private workloadMetadata;

    /// @notice Storage for TEE address allowlist and associated workloadIds
    mapping(address => PolicyStatus) private teeAllowlist;

    /// @notice Struct to store policy status for a TEE address
    struct PolicyStatus {
        bool allowed;
        WorkloadId workloadId;
    }

    /**
     * @notice Mapping from workloadId to its metadata (commit hash and source locators)
     * @dev This is only updateable by governance (i.e. the owner) of the Policy contract
     * Adding and removing a workload is O(1)
     * @param workloadId The workload identifier to query
     * @return The metadata associated with the workload
     */
    function getWorkloadMetadata(WorkloadId workloadId) external view returns (WorkloadMetadata memory) {
        return workloadMetadata[WorkloadId.unwrap(workloadId)];
    }

    /**
     * @notice Check if this TEE-controlled address has registered a valid TEE workload with the registry, and
     * if the workload is approved under this policy
     * @param teeAddress The TEE-controlled address
     * @return allowed True if the TEE is using an approved workload in the policy
     * @return workloadId The workloadId of the TEE that is using an approved workload in the policy, or 0 if
     * the TEE is not using an approved workload in the policy
     */
    function isAllowedPolicy(address teeAddress) external view returns (bool allowed, WorkloadId workloadId) {
        PolicyStatus memory status = teeAllowlist[teeAddress];
        return (status.allowed, status.workloadId);
    }

    /**
     * @notice Sets workload metadata for a given workloadId (test helper)
     * @dev This function is only available in the mock for testing purposes
     * @param workloadId The workload identifier to set metadata for
     * @param commitHash The git commit hash of the workload source
     * @param sourceLocators Array of source location identifiers
     */
    function setWorkloadMetadata(WorkloadId workloadId, string memory commitHash, string[] memory sourceLocators)
        external
    {
        WorkloadMetadata storage metadata = workloadMetadata[WorkloadId.unwrap(workloadId)];
        metadata.commitHash = commitHash;

        // Clear existing sourceLocators and set new ones
        delete metadata.sourceLocators;
        for (uint256 i = 0; i < sourceLocators.length; i++) {
            metadata.sourceLocators.push(sourceLocators[i]);
        }
    }

    /**
     * @notice Sets policy status for a TEE address (test helper)
     * @dev This function is only available in the mock for testing purposes
     * @param teeAddress The TEE-controlled address to set policy status for
     * @param allowed Whether the TEE is allowed under this policy
     * @param workloadId The workloadId associated with this TEE
     */
    function setPolicyStatus(address teeAddress, bool allowed, WorkloadId workloadId) external {
        teeAllowlist[teeAddress] = PolicyStatus({allowed: allowed, workloadId: workloadId});
    }
}
