# CLAUDE.md - Smart Contract Source Code

## Overview

This directory contains the core smart contract implementation for the FlashblockNumber system. The contracts provide a secure, upgradeable mechanism for tracking flashblock numbers on Unichain through TEE-based builder authorization, enabling external contracts to enforce time-sensitive ordering constraints.

**Architecture**: Interface-first design with a main implementation contract following UUPS upgradeable proxy pattern and decentralized TEE attestation verification.

## Key Components

### FlashblockNumber.sol
**Purpose**: Main implementation contract that tracks flashblock numbers and validates builder authorization through Flashbots' TEE attestation framework.

**Core Functionality**:
- **Flashblock Tracking**: Maintains monotonically increasing `flashblockNumber` counter
- **TEE Authorization**: Validates builders through FlashtestationRegistry and BlockBuilderPolicy integration
- **Gas-Optimized Caching**: Caches workload verification results to minimize expensive external calls
- **EIP-712 Support**: Enables meta-transactions through cryptographic signatures
- **UUPS Upgradeability**: Supports contract upgrades while preserving state

**Key Functions**:
- `incrementFlashblockNumber()`: Direct increment by TEE-authorized builders
- `permitIncrementFlashblockNumber()`: Signature-based increment for meta-transactions
- `getFlashblockNumber()`: Public view function returning current flashblock number
- `registry()`: Returns address of FlashtestationRegistry contract
- `policy()`: Returns address of BlockBuilderPolicy contract
- `initialize()`: Proxy initialization with owner, registry, and policy addresses
- `reinitializeV2()`: V1→V2 upgrade function to set registry and policy addresses

**Authorization Patterns**:
- **TEE Verification**: `_cachedIsAllowedPolicy()` validates builder through registry and policy
- **Cache Optimization**: Stores workloadId and quoteHash to avoid redundant verification
- **Owner-Only Operations**: Contract upgrades require `onlyOwner`
- **Public View Access**: `getFlashblockNumber()`, `registry()`, `policy()` are publicly accessible

### IFlashblockNumber.sol
**Purpose**: Interface definition that standardizes the public API for external contract integrations.

**Design Philosophy**:
- **Complete API Coverage**: Includes all public functions, events, and errors
- **Integration-Friendly**: Designed for easy import and use by external contracts
- **Event-Driven**: Comprehensive event definitions for monitoring and indexing
- **Error Handling**: Custom errors with descriptive parameters for better debugging

**Events**:
- `FlashblockIncremented(uint256 newFlashblockIndex)`: Emitted on each flashblock increment

**Custom Errors**:
- `NonBuilderAddress(address addr)`: Thrown when unauthorized address attempts increment
- `MismatchedFlashblockNumber(...)`: Thrown when EIP-712 signature contains stale flashblock number

## Implementation Details

### State Management
**Storage Layout** (UUPS-compatible, with V2 additions):
```solidity
uint256 public flashblockNumber;                          // Slot 0: Current flashblock counter
mapping(address => bool) public isBuilder;                // Slot 1: DEPRECATED - kept for storage compatibility
IFlashtestationRegistry private flashtestationRegistry;   // Slot 2: TEE registry contract
IBlockBuilderPolicy private blockBuilderPolicy;           // Slot 3: Policy contract
mapping(address => CachedWorkload) private cachedWorkloads; // Slot 4: Gas optimization cache
// Additional slots reserved for EIP-712 and OpenZeppelin inherited contracts
```

**CachedWorkload Struct**:
```solidity
struct CachedWorkload {
    WorkloadId workloadId;  // Computed workload identifier
    bytes32 quoteHash;      // Hash of TEE attestation quote
}
```

**State Invariants**:
1. **Monotonic Increment**: `flashblockNumber` can only increase (except during blockchain reorgs)
2. **TEE Authorization**: Only TEE addresses with valid attestation and approved workloads can increment
3. **Single Increment**: Each flashblock should be incremented exactly once per flashblock period
4. **Cache Consistency**: Cached workloadIds are valid only when quoteHash matches current registration

### TEE Authorization System

**Authorization Flow** (`_cachedIsAllowedPolicy()`):
1. **Fast Path - Registry Check**: Query `flashtestationRegistry.getRegistrationStatus(teeAddress)`
   - Returns `(bool isValid, bytes32 quoteHash)`
   - If `isValid == false`, immediately reject
2. **Cache Lookup**: Check `cachedWorkloads[teeAddress]`
   - If cache hit (workloadId exists and quoteHash matches):
     - Verify workload still approved: `blockBuilderPolicy.getWorkloadMetadata(workloadId).commitHash != ""`
     - Return true if approved, false otherwise
3. **Cache Miss**: Query `blockBuilderPolicy.isAllowedPolicy(teeAddress)`
   - Returns `(bool allowed, WorkloadId workloadId)`
   - If allowed, update cache: `cachedWorkloads[teeAddress] = CachedWorkload(workloadId, quoteHash)`
   - Return `allowed` status

**Gas Optimization Strategy**:
- **First call**: 2 external calls (registry + policy) + 1 cache write
- **Cached calls**: 1 external call (registry) + 1 cache read + 1 view call (metadata check)
- **Cache invalidation**: Automatic when TEE quote changes (quoteHash mismatch)
- **Stale cache**: Not cleaned up (acceptable since failed attempts revert anyway)

**External Contracts**:
- **FlashtestationRegistry**: Validates TEE attestation quotes and registration status
  - Provides `getRegistrationStatus(address)` for fast validation
  - Returns validity and current quote hash
- **BlockBuilderPolicy**: Enforces workload-based authorization policies
  - Provides `isAllowedPolicy(address)` to check TEE authorization
  - Provides `getWorkloadMetadata(WorkloadId)` to verify workload approval
  - Returns workloadId for approved TEEs

### Security Patterns

**TEE Attestation Verification**:
- Builders must provide valid TEE attestation registered with FlashtestationRegistry
- Only approved workloads (verified through BlockBuilderPolicy) can increment flashblocks
- Decentralized authorization - no single party controls builder access
- Workload-based policies enable governance over which TEE code versions are authorized

**EIP-712 Replay Protection**:
- Uses current `flashblockNumber` as nonce in signature structure
- Signature becomes invalid immediately after successful use
- Prevents replay attacks across different flashblock periods

**Upgrade Safety**:
- UUPS pattern with `_authorizeUpgrade()` restricted to contract owner
- V2 upgrade maintains storage compatibility by keeping deprecated `isBuilder` mapping
- `reinitializeV2()` function enables safe migration from V1 to V2
- Critical state variables positioned in early storage slots for stability

### Integration Patterns

**External Contract Integration**:
```solidity
// Recommended integration pattern
contract ExternalContract {
    IFlashblockNumber immutable flashblockTracker;

    constructor(address _flashblockTracker) {
        flashblockTracker = IFlashblockNumber(_flashblockTracker);
    }

    modifier flashblockRange(uint256 min, uint256 max) {
        uint256 current = flashblockTracker.getFlashblockNumber();
        require(current >= min && current <= max, "Outside valid flashblock range");
        _;
    }

    function checkTEEComponents() external view returns (address, address) {
        // Query registry and policy for off-chain verification
        return (flashblockTracker.registry(), flashblockTracker.policy());
    }
}
```

**Event Monitoring**:
```solidity
// Listen for flashblock increments
contract FlashblockMonitor {
    function onFlashblockIncremented(uint256 newFlashblock) external {
        // React to flashblock changes
        // Update internal state, trigger time-sensitive operations, etc.
    }
}
```

## TEE Builder Integration

### Direct Integration (For Builder Infrastructure)
```solidity
// Direct call from TEE-authorized builder
// Builder must be registered in FlashtestationRegistry with valid attestation
// Builder's workload must be approved in BlockBuilderPolicy
flashblockNumber.incrementFlashblockNumber();
```

### Meta-Transaction Integration (For TEE Builders)
```solidity
// 1. Generate EIP-712 signature off-chain (in TEE)
uint256 currentFlashblock = flashblockNumber.getFlashblockNumber();
bytes32 structHash = flashblockNumber.computeStructHash(currentFlashblock);
bytes32 digest = flashblockNumber.hashTypedDataV4(structHash);
bytes memory signature = signDigest(digest, builderPrivateKey);

// 2. Submit via meta-transaction (can be done by anyone)
flashblockNumber.permitIncrementFlashblockNumber(currentFlashblock, signature);
```

### Builder Registration Requirements
**Prerequisites for Incrementing Flashblocks**:
1. **TEE Registration**: Builder must register with FlashtestationRegistry
   - Provide valid TEE attestation quote
   - Attestation must verify TEE identity and workload
2. **Workload Approval**: Builder's workload must be in BlockBuilderPolicy's approved list
   - Workload identified by deterministic WorkloadId (computed from attestation)
   - Policy governance controls which workloads are approved
3. **Ongoing Validity**: Both registration and policy approval must remain valid
   - Registration can be revoked by registry governance
   - Policy approval can be revoked by policy governance
   - Cache invalidation happens automatically on quote changes

## Gas Optimization Notes

**Storage Access Patterns**:
- `cachedWorkloads` mapping uses single storage slot per TEE address
- `flashblockNumber` increment costs ~5,000 gas (SSTORE warm)
- View functions (`getFlashblockNumber`, `registry`, `policy`) are zero-cost for external calls
- Cache hit path: ~15,000 gas (1 external call + 1 storage read + 1 view call)
- Cache miss path: ~50,000 gas (2 external calls + 1 storage write)

**Optimization Strategies**:
- High optimizer runs (44M) for deployment-time optimization
- Caching minimizes expensive TEE verification on repeated calls from same builder
- Minimal external calls to prevent reentrancy and reduce gas costs
- Event emission optimized for indexing efficiency

## Development Guidelines

**Adding New Functions**:
1. Define function signature in `IFlashblockNumber.sol` first
2. Implement in `FlashblockNumber.sol` with appropriate access controls
3. Add comprehensive tests covering success and failure cases
4. Consider upgrade compatibility and storage layout impact
5. If function interacts with TEE system, test with mock contracts first

**Error Handling Standards**:
- Use custom errors instead of string revert messages for gas efficiency
- Include relevant parameters in error definitions for debugging
- Follow consistent naming: describe the condition that failed

**Event Design**:
- Index addresses for efficient filtering
- Include all relevant state changes in event data
- Emit events after state changes to ensure consistency

## Testing Integration

**Mock Usage in Tests**:
```solidity
// Create mock TEE infrastructure
MockFlashtestationRegistry registry = new MockFlashtestationRegistry();
MockBlockBuilderPolicy policy = new MockBlockBuilderPolicy();

// Configure mock authorization for test builders
registry.setRegistrationStatus(builder1, true, testQuoteHash);
policy.setPolicyStatus(builder1, true, testWorkloadId);
policy.setWorkloadMetadata(testWorkloadId, "commit-hash", sourceLocators);

// Create test instance
FlashblockNumber implementation = new FlashblockNumber();
address proxy = UnsafeUpgrades.deployUUPSProxy(
    address(implementation),
    abi.encodeCall(FlashblockNumber.initialize, (owner, address(registry), address(policy)))
);
IFlashblockNumber flashblock = IFlashblockNumber(proxy);
```

**Common Test Patterns**:
- State verification after each operation
- TEE authorization testing with mock registry and policy
- Cache behavior testing (hit/miss scenarios)
- Edge case testing (revoked registration, revoked policy, invalid workload)
- Fuzz testing for property verification

**V1→V2 Upgrade Testing**:
- Deploy V1 contract with manual builder management
- Verify V1 functionality works
- Upgrade to V2 using `reinitializeV2()`
- Verify V2 TEE authorization works
- Verify storage compatibility maintained
