# CLAUDE.md - Smart Contract Source Code

## Overview

This directory contains the core smart contract implementation for the FlashblockNumber system. The contracts provide a secure, upgradeable mechanism for tracking flashblock numbers on Unichain, enabling external contracts to enforce time-sensitive ordering constraints.

**Architecture**: Interface-first design with a main implementation contract following UUPS upgradeable proxy pattern.

## Key Components

### FlashblockNumber.sol
**Purpose**: Main implementation contract that tracks flashblock numbers and manages builder authorization.

**Core Functionality**:
- **Flashblock Tracking**: Maintains monotonically increasing `flashblockNumber` counter
- **Builder Authorization**: Manages whitelist of addresses permitted to increment flashblock numbers
- **EIP-712 Support**: Enables meta-transactions through cryptographic signatures
- **UUPS Upgradeability**: Supports contract upgrades while preserving state

**Key Functions**:
- `incrementFlashblockNumber()`: Direct increment by authorized builders
- `permitIncrementFlashblockNumber()`: Signature-based increment for meta-transactions
- `getFlashblockNumber()`: Public view function returning current flashblock number
- `addBuilder()` / `removeBuilder()`: Owner-only builder management
- `initialize()`: Proxy initialization with owner and initial builders

**Access Control Patterns**:
- **Builder-Only Operations**: `incrementFlashblockNumber()` functions require `isBuilder[msg.sender]`
- **Owner-Only Operations**: Builder management and contract upgrades require `onlyOwner`
- **Public View Access**: `getFlashblockNumber()` is publicly accessible for external integrations

### IFlashblockNumber.sol
**Purpose**: Interface definition that standardizes the public API for external contract integrations.

**Design Philosophy**:
- **Complete API Coverage**: Includes all public functions, events, and errors
- **Integration-Friendly**: Designed for easy import and use by external contracts
- **Event-Driven**: Comprehensive event definitions for monitoring and indexing
- **Error Handling**: Custom errors with descriptive parameters for better debugging

**Events**:
- `FlashblockIncremented(uint256 newFlashblockIndex)`: Emitted on each flashblock increment
- `BuilderAdded(address indexed builder)`: Emitted when new builder is authorized
- `BuilderRemoved(address indexed builder)`: Emitted when builder authorization is revoked

**Custom Errors**:
- `NonBuilderAddress(address addr)`: Thrown when unauthorized address attempts increment
- `AddressIsAlreadyABuilder(address addr)`: Thrown when adding existing builder
- `BuilderDoesNotExist(address addr)`: Thrown when removing non-existent builder
- `MismatchedFlashblockNumber(...)`: Thrown when EIP-712 signature contains stale flashblock number

## Implementation Details

### State Management
**Storage Layout** (UUPS-compatible):
```solidity
uint256 public flashblockNumber;           // Slot 0: Current flashblock counter
mapping(address => bool) public isBuilder; // Slot 1: Builder authorization mapping
// Additional slots reserved for EIP-712 and OpenZeppelin inherited contracts
```

**State Invariants**:
1. **Monotonic Increment**: `flashblockNumber` can only increase (except during blockchain reorgs)
2. **Authorization Consistency**: Only addresses with `isBuilder[addr] == true` can increment
3. **Single Increment**: Each flashblock should be incremented exactly once per flashblock period

### Security Patterns

**Access Control Implementation**:
```solidity
modifier onlyBuilder() {
    require(isBuilder[msg.sender], NonBuilderAddress(msg.sender));
    _;
}
```

**EIP-712 Replay Protection**:
- Uses current `flashblockNumber` as nonce in signature structure
- Signature becomes invalid immediately after successful use
- Prevents replay attacks across different flashblock periods

**Upgrade Safety**:
- UUPS pattern with `_authorizeUpgrade()` restricted to contract owner
- Storage layout compatibility must be maintained across upgrades
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

## Builder Integration

### Direct Integration (For Builder Infrastructure)
```solidity
// Direct call from authorized builder
flashblockNumber.incrementFlashblockNumber();
```

### Meta-Transaction Integration (For TEE Builders)
```solidity
// 1. Generate EIP-712 signature off-chain
uint256 currentFlashblock = flashblockNumber.getFlashblockNumber();
bytes32 structHash = flashblockNumber.computeStructHash(currentFlashblock);
bytes32 digest = flashblockNumber.hashTypedDataV4(structHash);
bytes memory signature = signDigest(digest, builderPrivateKey);

// 2. Submit via meta-transaction
flashblockNumber.permitIncrementFlashblockNumber(currentFlashblock, signature);
```

## Gas Optimization Notes

**Storage Access Patterns**:
- `isBuilder` mapping uses single storage slot per address
- `flashblockNumber` increment costs ~5,000 gas (SSTORE warm)
- View functions (`getFlashblockNumber`) are zero-cost for external calls

**Optimization Strategies**:
- High optimizer runs (44M) for deployment-time optimization
- Minimal external calls to prevent reentrancy and reduce gas costs
- Event emission optimized for indexing efficiency

## Development Guidelines

**Adding New Functions**:
1. Define function signature in `IFlashblockNumber.sol` first
2. Implement in `FlashblockNumber.sol` with appropriate access controls
3. Add comprehensive tests covering success and failure cases
4. Consider upgrade compatibility and storage layout impact

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
// Create test instance
FlashblockNumber implementation = new FlashblockNumber();
address proxy = UnsafeUpgrades.deployUUPSProxy(
    address(implementation),
    abi.encodeCall(FlashblockNumber.initialize, (owner, builders))
);
IFlashblockNumber flashblock = IFlashblockNumber(proxy);
```

**Common Test Patterns**:
- State verification after each operation
- Access control testing with unauthorized addresses
- Edge case testing (boundary conditions, overflow protection)
- Fuzz testing for property verification