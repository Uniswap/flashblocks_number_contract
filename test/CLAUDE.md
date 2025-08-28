# CLAUDE.md - Testing Infrastructure

## Overview

This directory contains the comprehensive test suite for the FlashblockNumber contract system. The tests are built using Foundry's testing framework and ensure complete coverage of functionality, security properties, and edge cases, including the new TEE-based authorization system.

**Testing Philosophy**: Property-based testing combined with specific scenario testing to ensure contract behavior is correct under all conditions, with mock-based TEE authorization for isolated unit testing.

## Test Architecture

### FlashblockNumber.t.sol
**Purpose**: Complete test suite covering all contract functionality including initialization, core operations, TEE authorization, upgrades, and EIP-712 features.

**Test Organization**:
- **Setup Phase**: Contract deployment via UUPS proxy with mock TEE infrastructure
- **State Verification**: Initial conditions and invariant checking
- **Functionality Tests**: Core operations and business logic verification
- **TEE Authorization Tests**: Mock-based testing of registry and policy integration
- **Security Tests**: Access control, permission boundaries, and attack resistance
- **Edge Case Tests**: Boundary conditions, overflow protection, and error scenarios
- **Fuzz Tests**: Property-based testing with randomized inputs

### Mock Infrastructure (`test/mocks/`)
**Purpose**: Provide controllable TEE authorization components for unit testing without requiring actual attestation verification.

**Mock Contracts**:
- **MockFlashtestationRegistry.sol**: Simulates TEE registration and attestation validation
  - Allows tests to set registration status: `setRegistrationStatus(address, bool, bytes32)`
  - Returns validity status and quote hash: `getRegistrationStatus(address)`
- **MockBlockBuilderPolicy.sol**: Simulates workload-based authorization policies
  - Allows tests to set policy status: `setPolicyStatus(address, bool, WorkloadId)`
  - Allows tests to set workload metadata: `setWorkloadMetadata(WorkloadId, string, string[])`
  - Returns authorization status: `isAllowedPolicy(address)`
  - Returns workload metadata: `getWorkloadMetadata(WorkloadId)`

## Key Test Categories

### Initialization and State Tests
**Purpose**: Verify correct contract deployment and initial state setup with TEE infrastructure.

**Test Cases**:
- `test_InitialState()`: Confirms registry and policy addresses are set correctly and flashblock number starts at 0
- Registry and policy address verification
- Initial flashblock number verification (should be 0)
- Owner assignment verification

**Key Assertions**:
```solidity
assertEq(flashblockNumber.registry(), address(registry));
assertEq(flashblockNumber.policy(), address(policy));
assertEq(flashblockNumber.getFlashblockNumber(), 0);
```

**Setup Pattern**:
```solidity
// Deploy mock TEE infrastructure
MockFlashtestationRegistry registry = new MockFlashtestationRegistry();
MockBlockBuilderPolicy policy = new MockBlockBuilderPolicy();

// Configure mock authorization
registry.setRegistrationStatus(builder1, true, testQuoteHash);
policy.setPolicyStatus(builder1, true, testWorkloadId);
policy.setWorkloadMetadata(testWorkloadId, "commit-hash", sourceLocators);

// Deploy FlashblockNumber with mocks
address proxy = UnsafeUpgrades.deployUUPSProxy(
    implementation,
    abi.encodeCall(FlashblockNumber.initialize, (owner, address(registry), address(policy)))
);
```

### Core Functionality Tests
**Purpose**: Verify flashblock increment operations work correctly under various conditions.

**Test Scenarios**:
- **Single Increment**: Basic flashblock number increment by TEE-authorized builder
- **Multiple Increments**: Sequential increments by same builder within block
- **Multi-Builder Operations**: Different TEE-authorized builders incrementing in sequence
- **Cross-Block Behavior**: Increment operations across multiple blocks

**Invariant Verification**:
- Flashblock number increases monotonically
- Each increment increases value by exactly 1
- State consistency after each operation

### TEE Authorization Tests
**Purpose**: Ensure only TEE-authorized addresses can perform restricted operations.

**Authorization Scenarios Tested**:
- **Authorized Builder**: Builder with valid registration and policy approval can increment
  - `test_AuthorizedBuilder_CanIncrement()`
- **Revoked Registration**: Builder with revoked TEE registration cannot increment
  - `test_RevokedRegistration_CannotIncrement()`
- **Revoked Policy**: Builder with revoked policy approval cannot increment
  - `test_RevokedPolicy_CannotIncrement()`
- **Invalid Workload**: Builder with workload not in policy cannot increment
  - `test_InvalidWorkload_CannotIncrement()`
- **Unauthorized Builder**: Non-registered builder cannot increment
  - `test_IncrementFlashblockNumber_NonBuilder()`

**Mock-Based Authorization Testing**:
```solidity
// Authorize builder
registry.setRegistrationStatus(builder1, true, testQuoteHash);
policy.setPolicyStatus(builder1, true, testWorkloadId);

// Builder can now increment
vm.prank(builder1);
flashblockNumber.incrementFlashblockNumber();

// Revoke registration
registry.setRegistrationStatus(builder1, false, testQuoteHash);

// Builder can no longer increment
vm.prank(builder1);
vm.expectRevert(abi.encodeWithSelector(IFlashblockNumber.NonBuilderAddress.selector, builder1));
flashblockNumber.incrementFlashblockNumber();
```

**Cache Testing**:
- First increment: Cache miss, queries both registry and policy
- Subsequent increments: Cache hit, only queries registry + metadata check
- Quote change: Cache invalidation, re-queries policy
- Workload removal: Cached workload no longer valid

### EIP-712 Meta-Transaction Tests
**Purpose**: Verify signature-based flashblock increment functionality.

**Signature Testing Flow**:
1. **Struct Hash Generation**: Verify `computeStructHash()` produces correct hash
2. **Digest Creation**: Confirm `hashTypedDataV4()` generates valid EIP-712 digest
3. **Signature Verification**: Test valid signature acceptance and invalid signature rejection
4. **Replay Protection**: Ensure signatures become invalid after single use
5. **Nonce Behavior**: Verify current flashblock number acts as effective nonce

**Key Security Properties**:
- Valid signatures from TEE-authorized builders succeed
- Invalid signatures are rejected
- Stale signatures (wrong current flashblock number) are rejected
- Signature replay attacks are prevented
- Signer must have valid TEE registration and policy approval

### Dynamic Builder Authorization Tests
**Purpose**: Verify authorization changes take effect immediately without manual management.

**Test Coverage**:
- `testFuzz_DynamicBuilderAuthorization()`: Tests dynamic authorization changes
  - Builder starts authorized and can increment
  - Registration revoked → builder can no longer increment
  - Registration restored → builder can increment again
  - Policy revoked → builder can no longer increment
  - Policy restored → builder can increment again

**Key Difference from V1**:
- V1 required manual `addBuilder()`/`removeBuilder()` calls by owner
- V2 authorization controlled by external registry and policy contracts
- Changes in registry/policy take effect immediately without contract interaction

### Upgrade and Proxy Tests
**Purpose**: Verify UUPS upgrade functionality, proxy behavior, and V1→V2 migration.

**Upgrade Scenarios**:
- **Authorization**: Only owner can authorize upgrades
- **State Preservation**: Contract state maintained across upgrades
- **Function Continuity**: All functions continue working after upgrade
- **Storage Layout**: Storage slots remain compatible
- **V1→V2 Migration**: `reinitializeV2()` correctly sets registry and policy

**V1→V2 Upgrade Testing**:
```solidity
// Deploy V1 (with manual builder management)
// ... perform V1 operations ...

// Upgrade to V2
vm.prank(owner);
FlashblockNumber(proxy).reinitializeV2(address(registry), address(policy));

// Verify V2 functionality
assertEq(flashblockNumber.registry(), address(registry));
assertEq(flashblockNumber.policy(), address(policy));
// Old isBuilder mapping no longer used but still present for storage compatibility
```

### Fuzz Testing
**Purpose**: Property-based testing with randomized inputs to discover edge cases.

**Fuzz Test Properties**:
- **TEE Authorization**: Random addresses should only succeed if authorized by registry and policy
- **Increment Monotonicity**: Multiple random increments should always increase flashblock number
- **Signature Validity**: Only properly signed messages from TEE-authorized builders should succeed
- **Authorization Invariants**: Unauthorized operations should always fail regardless of input
- **Cache Consistency**: Cached workloads should only be valid when quote hash matches

**Fuzz Configuration**:
- **Runs**: 10,000 iterations (configured in `foundry.toml`)
- **Input Ranges**: Addresses, uint256 values, bytes arrays
- **Invariant Checking**: Properties must hold for all valid inputs

## Mock Contract Details

### MockFlashtestationRegistry
**Purpose**: Simulates TEE registration and attestation validation without requiring real attestation hardware.

**Key Functions**:
- `setRegistrationStatus(address teeAddress, bool isValid, bytes32 quoteHash)`: Test helper to set registration
- `getRegistrationStatus(address teeAddress) returns (bool isValid, bytes32 quoteHash)`: Returns mock registration status

**Usage in Tests**:
```solidity
// Authorize a builder
registry.setRegistrationStatus(builder1, true, keccak256("test-quote"));

// Revoke authorization
registry.setRegistrationStatus(builder1, false, bytes32(0));

// Change quote (invalidates cache)
registry.setRegistrationStatus(builder1, true, keccak256("new-quote"));
```

### MockBlockBuilderPolicy
**Purpose**: Simulates workload-based authorization policies without requiring real policy governance.

**Key Functions**:
- `setPolicyStatus(address teeAddress, bool allowed, WorkloadId workloadId)`: Test helper to set policy
- `setWorkloadMetadata(WorkloadId workloadId, string memory commitHash, string[] memory sourceLocators)`: Test helper to set workload metadata
- `isAllowedPolicy(address teeAddress) returns (bool allowed, WorkloadId workloadId)`: Returns mock policy status
- `getWorkloadMetadata(WorkloadId workloadId) returns (WorkloadMetadata memory)`: Returns mock workload metadata

**Usage in Tests**:
```solidity
// Approve a builder's workload
WorkloadId workloadId = WorkloadId.wrap(keccak256("test-workload"));
policy.setPolicyStatus(builder1, true, workloadId);

// Set workload metadata (makes workload "valid")
string[] memory sources = new string[](1);
sources[0] = "github.com/test/repo";
policy.setWorkloadMetadata(workloadId, "abc123", sources);

// Revoke policy approval
policy.setPolicyStatus(builder1, false, WorkloadId.wrap(0));

// Remove workload from policy (invalidates cached workload)
policy.setWorkloadMetadata(workloadId, "", new string[](0));
```

## Test Utilities and Helpers

### Test Setup Infrastructure
**Address Generation**:
```solidity
address public owner = makeAddr("owner");
address public builder1 = makeAddr("builder1");
address public builder2 = makeAddr("builder2");
address public nonBuilder = makeAddr("nonBuilder");
```

**Mock Deployment Pattern**:
```solidity
// Deploy mocks
MockFlashtestationRegistry registry = new MockFlashtestationRegistry();
MockBlockBuilderPolicy policy = new MockBlockBuilderPolicy();

// Configure mocks
registry.setRegistrationStatus(builder1, true, testQuoteHash);
policy.setPolicyStatus(builder1, true, testWorkloadId);
policy.setWorkloadMetadata(testWorkloadId, "commit", sources);

// Deploy FlashblockNumber
address proxy = UnsafeUpgrades.deployUUPSProxy(
    implementation,
    abi.encodeCall(FlashblockNumber.initialize, (owner, address(registry), address(policy)))
);
```

### EIP-712 Testing Utilities
**Signature Generation**:
- Private key management with SECP256K1 curve limits
- Proper digest creation following EIP-712 standard
- Invalid signature generation for negative test cases
- TEE-authorized signer validation

**Replay Attack Simulation**:
- Signature reuse attempts after successful increment
- Cross-flashblock signature testing
- Invalid nonce (flashblock number) testing

## Testing Best Practices

### Test Isolation
- Each test starts with fresh contract state via `setUp()`
- Mock contracts deployed fresh for each test
- No test dependencies on execution order
- Clear state verification at test completion

### Comprehensive Coverage
- **Happy Path**: Normal operations under expected conditions
- **Error Cases**: All revert conditions explicitly tested
- **Edge Cases**: Boundary values and limit conditions
- **Integration**: End-to-end workflows combining multiple operations
- **Authorization Changes**: Dynamic TEE authorization scenarios

### Gas Testing
- Gas usage verification for optimization validation
- Comparison of cache hit vs cache miss gas costs
- Identification of gas-expensive operations
- Cache optimization effectiveness measurement

### Event Testing
**Event Verification Pattern**:
```solidity
vm.expectEmit(true, true, false, true);
emit FlashblockIncremented(expectedFlashblockNumber);
flashblockNumber.incrementFlashblockNumber();
```

## Running Tests

### Basic Test Execution
```bash
# Run all tests
forge test

# Run with detailed output
forge test -vvv

# Run specific test
forge test --match-test test_AuthorizedBuilder_CanIncrement

# Run TEE authorization tests
forge test --match-test test_.*Authorization.*

# Run fuzz tests with extended runs
forge test --fuzz-runs 10000
```

### Coverage Analysis
```bash
# Generate coverage report
forge coverage

# Detailed coverage with line-by-line analysis
forge coverage --report lcov
```

### Gas Analysis
```bash
# Show gas usage for all tests
forge test --gas-report

# Compare cache hit vs miss gas costs
forge test --gas-report --match-test test_IncrementFlashblockNumber

# Build with size information
forge build --sizes
```

## Test Maintenance Guidelines

### Adding New Tests
1. **Follow Naming Convention**: `test_OperationName_Scenario()`
2. **Include Setup**: Ensure proper mock configuration
3. **Verify State Changes**: Check all relevant state modifications
4. **Test Both Success and Failure**: Include positive and negative cases
5. **Add Documentation**: Clear comments explaining test purpose
6. **Test Authorization**: Verify TEE authorization for protected operations

### Mock Configuration Best Practices
1. **Explicit Setup**: Always explicitly configure mocks for each test
2. **Complete Authorization**: Set both registration and policy status
3. **Workload Metadata**: Don't forget to set workload metadata for valid workloads
4. **State Changes**: Test scenarios where authorization changes mid-test
5. **Cache Testing**: Verify cache behavior with quote changes

### Fuzz Test Development
1. **Define Properties**: Clear invariants that should always hold
2. **Handle Edge Cases**: Account for boundary conditions in assumptions
3. **Validate Inputs**: Use appropriate input filtering for meaningful tests
4. **Check Gas Costs**: Ensure fuzz tests don't hit gas limits
5. **Mock Consistency**: Ensure mocks behave consistently across fuzz runs

### Integration Test Patterns
1. **Multi-Step Operations**: Test complete workflows
2. **Cross-Function Interactions**: Verify function combinations work correctly
3. **State Transitions**: Test valid state changes and invalid transitions
4. **Authorization Integration**: Combine TEE authorization with business logic testing
5. **Cache Behavior**: Test authorization caching across multiple operations
