# CLAUDE.md - Testing Infrastructure

## Overview

This directory contains the comprehensive test suite for the FlashblockNumber contract system. The tests are built using Foundry's testing framework and ensure complete coverage of functionality, security properties, and edge cases.

**Testing Philosophy**: Property-based testing combined with specific scenario testing to ensure contract behavior is correct under all conditions.

## Test Architecture

### FlashblockNumber.t.sol
**Purpose**: Complete test suite covering all contract functionality including initialization, core operations, access control, upgrades, and EIP-712 features.

**Test Organization**:
- **Setup Phase**: Contract deployment via UUPS proxy with initial state configuration
- **State Verification**: Initial conditions and invariant checking
- **Functionality Tests**: Core operations and business logic verification
- **Security Tests**: Access control, permission boundaries, and attack resistance
- **Edge Case Tests**: Boundary conditions, overflow protection, and error scenarios
- **Fuzz Tests**: Property-based testing with randomized inputs

## Key Test Categories

### Initialization and State Tests
**Purpose**: Verify correct contract deployment and initial state setup.

**Test Cases**:
- `test_InitialState()`: Confirms initial builders are registered and flashblock number starts at 0
- Builder authorization verification for all initial addresses
- Non-builder addresses correctly excluded from authorization
- Owner assignment verification

**Key Assertions**:
```solidity
assertTrue(flashblockNumber.isBuilder(builder1));
assertTrue(flashblockNumber.isBuilder(builder2));
assertFalse(flashblockNumber.isBuilder(nonBuilder));
assertEq(flashblockNumber.getFlashblockNumber(), 0);
```

### Core Functionality Tests
**Purpose**: Verify flashblock increment operations work correctly under various conditions.

**Test Scenarios**:
- **Single Increment**: Basic flashblock number increment by authorized builder
- **Multiple Increments**: Sequential increments by same builder within block
- **Multi-Builder Operations**: Different builders incrementing in sequence
- **Cross-Block Behavior**: Increment operations across multiple blocks

**Invariant Verification**:
- Flashblock number increases monotonically
- Each increment increases value by exactly 1
- State consistency after each operation

### Access Control Tests
**Purpose**: Ensure only authorized addresses can perform restricted operations.

**Security Boundaries Tested**:
- **Builder Authorization**: Only `isBuilder[address] == true` addresses can increment
- **Owner Operations**: Only contract owner can add/remove builders
- **Unauthorized Access**: Non-builders cannot increment flashblock numbers
- **Builder Management**: Adding/removing builders with proper access controls

**Attack Vector Testing**:
- Unauthorized increment attempts (should revert with `NonBuilderAddress`)
- Non-owner builder management attempts (should revert with ownership error)
- Duplicate builder addition/removal (should revert with specific errors)

### EIP-712 Meta-Transaction Tests
**Purpose**: Verify signature-based flashblock increment functionality.

**Signature Testing Flow**:
1. **Struct Hash Generation**: Verify `computeStructHash()` produces correct hash
2. **Digest Creation**: Confirm `hashTypedDataV4()` generates valid EIP-712 digest
3. **Signature Verification**: Test valid signature acceptance and invalid signature rejection
4. **Replay Protection**: Ensure signatures become invalid after single use
5. **Nonce Behavior**: Verify current flashblock number acts as effective nonce

**Key Security Properties**:
- Valid signatures from authorized builders succeed
- Invalid signatures are rejected
- Stale signatures (wrong current flashblock number) are rejected
- Signature replay attacks are prevented

### Builder Management Tests
**Purpose**: Verify administrative functions for builder authorization work correctly.

**Management Operations**:
- **Adding Builders**: `addBuilder()` function with owner restrictions
- **Removing Builders**: `removeBuilder()` function with proper cleanup
- **Duplicate Prevention**: Cannot add existing builders or remove non-existent ones
- **Event Emission**: Proper events emitted for all management operations

**State Consistency**:
- Builder mapping correctly updated after add/remove operations
- Authorization changes immediately effective for increment operations
- Historical flashblock numbers unaffected by builder changes

### Upgrade and Proxy Tests
**Purpose**: Verify UUPS upgrade functionality and proxy behavior.

**Upgrade Scenarios**:
- **Authorization**: Only owner can authorize upgrades
- **State Preservation**: Contract state maintained across upgrades
- **Function Continuity**: All functions continue working after upgrade
- **Storage Layout**: Storage slots remain compatible

### Fuzz Testing
**Purpose**: Property-based testing with randomized inputs to discover edge cases.

**Fuzz Test Properties**:
- **Builder Authorization**: Random addresses should only succeed if in builder set
- **Increment Monotonicity**: Multiple random increments should always increase flashblock number
- **Signature Validity**: Only properly signed messages from builders should succeed
- **Access Control Invariants**: Unauthorized operations should always fail regardless of input

**Fuzz Configuration**:
- **Runs**: 10,000 iterations (configured in `foundry.toml`)
- **Input Ranges**: Addresses, uint256 values, bytes arrays
- **Invariant Checking**: Properties must hold for all valid inputs

## Test Utilities and Helpers

### Test Setup Infrastructure
**Address Generation**:
```solidity
address public owner = makeAddr("owner");
address public builder1 = makeAddr("builder1");
address public builder2 = makeAddr("builder2");
address public nonBuilder = makeAddr("nonBuilder");
```

**Proxy Deployment Pattern**:
```solidity
address proxy = UnsafeUpgrades.deployUUPSProxy(
    implementation,
    abi.encodeCall(FlashblockNumber.initialize, (owner, initialBuilders))
);
flashblockNumber = IFlashblockNumber(proxy);
```

### EIP-712 Testing Utilities
**Signature Generation**:
- Private key management with SECP256K1 curve limits
- Proper digest creation following EIP-712 standard
- Invalid signature generation for negative test cases

**Replay Attack Simulation**:
- Signature reuse attempts after successful increment
- Cross-flashblock signature testing
- Invalid nonce (flashblock number) testing

## Testing Best Practices

### Test Isolation
- Each test starts with fresh contract state via `setUp()`
- No test dependencies on execution order
- Clear state verification at test completion

### Comprehensive Coverage
- **Happy Path**: Normal operations under expected conditions
- **Error Cases**: All revert conditions explicitly tested
- **Edge Cases**: Boundary values and limit conditions
- **Integration**: End-to-end workflows combining multiple operations

### Gas Testing
- Gas usage verification for optimization validation
- Comparison of different operation patterns
- Identification of gas-expensive operations

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
forge test --match-test test_IncrementFlashblockNumber

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

# Build with size information
forge build --sizes
```

## Test Maintenance Guidelines

### Adding New Tests
1. **Follow Naming Convention**: `test_OperationName_Scenario()`
2. **Include Setup**: Ensure proper state initialization
3. **Verify State Changes**: Check all relevant state modifications
4. **Test Both Success and Failure**: Include positive and negative cases
5. **Add Documentation**: Clear comments explaining test purpose

### Fuzz Test Development
1. **Define Properties**: Clear invariants that should always hold
2. **Handle Edge Cases**: Account for boundary conditions in assumptions
3. **Validate Inputs**: Use appropriate input filtering for meaningful tests
4. **Check Gas Costs**: Ensure fuzz tests don't hit gas limits

### Integration Test Patterns
1. **Multi-Step Operations**: Test complete workflows
2. **Cross-Function Interactions**: Verify function combinations work correctly
3. **State Transitions**: Test valid state changes and invalid transitions
4. **Access Control Integration**: Combine authorization with business logic testing