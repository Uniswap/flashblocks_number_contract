# CLAUDE.md - FlashblockNumber Contract

## Project Overview

The FlashblockNumber Contract is a smart contract system for tracking flashblock ranges on Unichain, enabling smart contracts to revert if their function calls do not fall within specified flashblock bounds. This contract provides onchain access to flashblock granularity similar to how Solidity's `block.number` provides block-level granularity.

**Key Purpose**: Enable time-sensitive DeFi applications and MEV protection by providing reliable flashblock tracking that external contracts can query to enforce ordering constraints within flashblocks.

## Tech Stack

**Core Technologies:**
- **Solidity 0.8.28**: Smart contract implementation language
- **Foundry**: Development framework for building, testing, and deploying
- **OpenZeppelin Contracts Upgradeable**: Battle-tested upgradeable contract patterns
  - UUPS Upgradeable pattern for contract upgrades
  - Ownable pattern for access control
  - EIP-712 for meta-transaction support

**Development Tools:**
- **Forge**: Testing and building framework
- **GitHub Actions**: CI/CD pipeline for automated testing
- **Etherscan**: Contract verification and interaction

**Dependencies:**
- `@openzeppelin/contracts-upgradeable`: Upgradeable contract patterns
- `forge-std`: Foundry standard library for testing
- `openzeppelin-foundry-upgrades`: Foundry-specific upgrade tooling

## Repository Structure

```
/Users/melvillian/code/unichain/flashblocks_number_contract/
├── src/                     # Smart contract source code
│   ├── FlashblockNumber.sol # Main implementation contract
│   └── IFlashblockNumber.sol # Interface definition
├── test/                    # Test suite
│   └── FlashblockNumber.t.sol # Comprehensive contract tests
├── script/                  # Deployment and management scripts
│   └── FlashblockNumber.s.sol # UUPS proxy deployment script
├── lib/                     # External dependencies (git submodules)
│   ├── forge-std/          # Foundry testing utilities
│   ├── openzeppelin-contracts-upgradeable/ # OpenZeppelin upgradeable contracts
│   └── openzeppelin-foundry-upgrades/ # Foundry upgrade tooling
├── docs/                    # Documentation (mdBook format)
├── out/                     # Compiled contract artifacts
├── cache/                   # Build cache and deployment artifacts
├── broadcast/               # Deployment transaction logs
├── .github/workflows/       # CI/CD configuration
├── foundry.toml            # Foundry configuration
├── remappings.txt          # Import path mappings
└── env.sample              # Environment variable template
```

## Architecture

**Contract Architecture**: UUPS Upgradeable Proxy Pattern
- **Proxy Contract**: Deployed once, holds state, delegates calls to implementation
- **Implementation Contract**: Contains business logic, can be upgraded
- **Access Control**: Owner-based governance for upgrades and builder management

**Core Components**:
1. **FlashblockNumber Contract**: Main implementation with flashblock tracking logic
2. **IFlashblockNumber Interface**: Defines public API for external integrations
3. **Builder Authorization System**: Permissioned addresses that can increment flashblock numbers
4. **EIP-712 Support**: Meta-transaction capabilities for gas-efficient updates

**State Management**:
- **flashblockNumber**: Monotonically increasing counter (uint256)
- **isBuilder mapping**: Authorization registry for builder addresses
- **Owner**: Contract governance and upgrade authority

## Documentation Management

**CLAUDE.md Strategy**: This repository uses CLAUDE.md files to provide comprehensive documentation at appropriate levels:

- **Root CLAUDE.md** (this file): Project overview, architecture, and development guidelines
- **src/CLAUDE.md**: Smart contract implementation details and API documentation
- **test/CLAUDE.md**: Testing strategy, test organization, and coverage details
- **script/CLAUDE.md**: Deployment process and script documentation

**Maintenance Rules**:
1. Update CLAUDE.md files when adding new features or changing architecture
2. Keep documentation synchronized with code changes
3. Each level should complement, not duplicate, other documentation levels
4. Focus on "why" rather than "what" - code should be self-documenting for implementation details

## Development Workflow

**Setup Commands**:
```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv

# Generate coverage report
forge coverage

# Format code
forge fmt
```

**Deployment Process**:
1. Copy and configure environment: `cp env.sample .env`
2. Set owner address, builder addresses, RPC URL, and API key
3. Deploy with verification: `forge script script/FlashblockNumber.s.sol --rpc-url $RPC_URL --broadcast --verify --interactives 1`

**Key Configuration**:
- **Solidity Version**: 0.8.28 (Prague EVM)
- **Optimizer**: 44,444,444 runs (high optimization for gas efficiency)
- **Gas Limit**: 3B gas for complex operations
- **Fuzz Runs**: 10,000 for thorough property testing

## Conventions and Patterns

**Naming Conventions**:
- **Contracts**: PascalCase (e.g., `FlashblockNumber`)
- **Functions**: camelCase (e.g., `incrementFlashblockNumber`)
- **Variables**: camelCase with clear descriptive names
- **Constants**: UPPER_SNAKE_CASE (e.g., `PERMIT_INCREMENT_TYPEHASH`)

**Architecture Patterns**:
- **Interface-First Design**: All public APIs defined in interfaces first
- **Event-Driven Updates**: All state changes emit corresponding events
- **Access Control**: Consistent use of OpenZeppelin's access control patterns
- **Error Handling**: Custom errors with descriptive names and parameters

**Security Patterns**:
- **Checks-Effects-Interactions**: State updates before external calls
- **Access Control**: Strict permission checks for sensitive operations
- **Upgrade Safety**: UUPS pattern with owner-controlled upgrades
- **Replay Protection**: EIP-712 nonces prevent signature replay attacks

## Key Modules

### Core Smart Contracts (`/src/`)
- **FlashblockNumber.sol**: Main upgradeable contract with flashblock tracking logic
- **IFlashblockNumber.sol**: Interface defining the public API and events

### Testing Infrastructure (`/test/`)
- **FlashblockNumber.t.sol**: Comprehensive test suite covering all functionality

### Deployment Scripts (`/script/`)
- **FlashblockNumber.s.sol**: UUPS proxy deployment with CREATE3 for deterministic addresses

### External Dependencies (`/lib/`)
- **OpenZeppelin Upgradeable Contracts**: Security-audited upgradeable patterns
- **Foundry Standard Library**: Testing utilities and VM cheats
- **OpenZeppelin Foundry Upgrades**: Deployment tooling for upgradeable contracts

## Integration Guide

**For External Contracts**:
```solidity
import "./IFlashblockNumber.sol";

contract YourContract {
    IFlashblockNumber public flashblockNumber;

    function checkFlashblock() internal view returns (uint256) {
        return flashblockNumber.getFlashblockNumber();
    }

    modifier withinFlashblockRange(uint256 minFlashblock, uint256 maxFlashblock) {
        uint256 current = flashblockNumber.getFlashblockNumber();
        require(current >= minFlashblock && current <= maxFlashblock, "Outside flashblock range");
        _;
    }
}
```

**Deployment Addresses**: Check deployment artifacts in `/broadcast/` directory for network-specific addresses.

## Operational Notes

**Builder Management**:
- Only contract owner can add/remove authorized builders
- Multiple builders provide redundancy against single points of failure
- Builder authorization uses mapping for O(1) access control checks

**Upgrade Strategy**:
- UUPS pattern allows owner to upgrade implementation while preserving state
- Upgrades require careful consideration of storage layout compatibility
- Owner should be a multisig for production deployments

**Network Deployment**:
- Currently configured for Unichain Sepolia testnet
- Uses deterministic CREATE3 deployment for consistent addresses across networks
- Etherscan verification included in deployment process