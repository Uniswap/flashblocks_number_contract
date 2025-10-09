# CLAUDE.md - Deployment Scripts

## Overview

This directory contains deployment and management scripts for the FlashblockNumber contract system. The scripts handle UUPS proxy deployment with deterministic addresses, proper initialization, and post-deployment verification.

**Deployment Strategy**: Uses OpenZeppelin's UUPS proxy pattern with CREATE3 for deterministic cross-network addresses, ensuring consistent contract addresses across different blockchain networks.

## Key Components

### FlashblockNumber.s.sol
**Purpose**: Complete deployment script that handles UUPS proxy deployment, initialization, and verification in a single execution.

**Core Functionality**:
- **Environment Configuration**: Reads deployment parameters from environment variables
- **Address Parsing**: Converts comma-separated builder addresses to array format
- **UUPS Deployment**: Deploys upgradeable proxy with proper initialization
- **Post-Deployment Verification**: Confirms correct deployment and configuration
- **Console Logging**: Provides detailed deployment progress and results

## Deployment Architecture

### Environment-Driven Configuration
**Required Environment Variables** (from `.env` file):
- `FLASHBLOCK_NUMBER_OWNER`: Contract owner address (typically a multisig)
- `INITIAL_BUILDERS`: Comma-separated list of authorized builder addresses
- `RPC_URL`: Target network RPC endpoint
- `ETHERSCAN_API_KEY`: API key for contract verification

**Configuration Pattern**:
```solidity
address owner = vm.envAddress("FLASHBLOCK_NUMBER_OWNER");
string memory buildersEnv = vm.envString("INITIAL_BUILDERS");
address[] memory initialBuilders = parseBuilderAddresses(buildersEnv);
```

### UUPS Proxy Deployment
**Deployment Process**:
1. **Environment Loading**: Parse all required configuration from environment
2. **Address Validation**: Verify owner and builder addresses are valid
3. **Proxy Deployment**: Use OpenZeppelin's `Upgrades.deployUUPSProxy()`
4. **Initialization**: Call `initialize()` with owner and initial builders
5. **Verification**: Confirm deployment success and proper configuration

**Key Deployment Code**:
```solidity
address proxyAddress = Upgrades.deployUUPSProxy(
    "FlashblockNumber.sol",
    abi.encodeCall(FlashblockNumber.initialize, (owner, initialBuilders))
);
```

### Address Parsing Infrastructure
**Builder Address Parsing**: Handles comma-separated address strings with whitespace tolerance.

**Parsing Features**:
- **Comma Separation**: Splits on comma delimiters
- **Whitespace Handling**: Trims leading/trailing whitespace from each address
- **Address Validation**: Ensures proper hexadecimal format and checksum
- **Error Handling**: Clear error messages for malformed addresses

**Custom Parsing Logic**:
- Manual string parsing to avoid external dependencies
- Hex character conversion with case-insensitive support
- Address length and format validation (42 characters, 0x prefix)

## Deployment Features

### Deterministic Addresses
**CREATE3 Benefits**:
- Same contract address across different networks
- Address determination before actual deployment
- Independence from deployment account nonce
- Simplified cross-network integration

**Address Predictability**: External contracts can hardcode the FlashblockNumber address even before deployment, enabling seamless integration across multiple networks.

### Comprehensive Verification
**Post-Deployment Checks**:
```solidity
// Verify basic deployment
console.log("FlashblockNumber deployed at:", proxyAddress);
console.log("Flashblock number:", flashblock.getFlashblockNumber());
console.log("Owner:", flashblock.owner());

// Verify all builders
for (uint256 i = 0; i < initialBuilders.length; i++) {
    require(flashblock.isBuilder(initialBuilders[i]), "Builder not properly set");
    console.log("Builder", initialBuilders[i], "verified");
}
```

### Integration with Etherscan
**Automatic Verification**: The deployment script is designed to work with Forge's `--verify` flag for automatic contract verification on Etherscan-compatible explorers.

**Verification Command Pattern**:
```bash
forge script script/FlashblockNumber.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --interactives 1
```

## Usage Instructions

### Environment Setup
1. **Copy Template**: `cp env.sample .env`
2. **Configure Owner**: Set `FLASHBLOCK_NUMBER_OWNER` to multisig or EOA address
3. **Set Builders**: Configure `INITIAL_BUILDERS` with comma-separated builder addresses
4. **Network Configuration**: Set `RPC_URL` for target network
5. **Verification Setup**: Add `ETHERSCAN_API_KEY` for contract verification

### Deployment Execution
```bash
# Load environment variables
source .env

# Deploy to target network
forge script script/FlashblockNumber.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --interactives 1
```

### Network-Specific Deployment
**Multi-Network Strategy**:
- Same script works across all EVM-compatible networks
- Environment variables control network targeting
- Consistent addresses via CREATE3 deployment
- Network-specific RPC and verification endpoints

## Script Architecture Details

### Error Handling
**Validation Patterns**:
- Environment variable existence checking
- Address format validation with clear error messages
- Builder count validation (prevent empty builder lists)
- Post-deployment state verification

**Error Examples**:
```solidity
require(addressBytes.length == 42, "Invalid address length");
require(addressBytes[0] == "0" && (addressBytes[1] == "x" || addressBytes[1] == "X"),
        "Invalid address prefix");
require(flashblock.isBuilder(initialBuilders[i]), "Builder not properly set");
```

### Gas Optimization
**Deployment Efficiency**:
- Single transaction deployment via proxy pattern
- Batch initialization of all builders in constructor
- Minimal external calls during deployment
- Optimized for high gas limit networks

### Logging and Monitoring
**Console Output Structure**:
- Deployment parameters confirmation
- Progress indicators during execution
- Final deployment summary with addresses
- Builder verification status for each address

## Development and Maintenance

### Script Modification Guidelines
1. **Environment Variable Changes**: Update both script and `env.sample`
2. **Validation Logic**: Maintain strict input validation for security
3. **Console Logging**: Keep detailed logging for deployment transparency
4. **Error Messages**: Provide clear, actionable error descriptions

### Testing Deployment Scripts
**Local Testing**:
```bash
# Test on local Anvil network
anvil &
forge script script/FlashblockNumber.s.sol --rpc-url http://localhost:8545 --broadcast
```

**Testnet Validation**:
- Deploy to testnet first for validation
- Verify all functionality works correctly
- Test upgrade scenarios on testnet
- Confirm Etherscan verification works

### Upgrade Script Patterns
**Future Upgrade Scripts**: When contract upgrades are needed, follow similar patterns:
- Load existing proxy address from deployment artifacts
- Prepare new implementation deployment
- Use `Upgrades.upgradeProxy()` for seamless upgrades
- Verify upgrade success and functionality preservation

## Security Considerations

### Deployment Security
**Access Control Setup**:
- Owner address should be a secure multisig for production
- Initial builders should use hardware wallets or secure key management
- Private keys never stored in environment files or version control

**Network Security**:
- Use secure, reliable RPC providers
- Verify network ID matches intended deployment target
- Confirm gas price and limits appropriate for network conditions

### Post-Deployment Security
**Immediate Actions After Deployment**:
1. Verify contract bytecode on explorer
2. Test basic functionality with small transactions
3. Confirm all builders can successfully increment flashblock numbers
4. Validate ownership transfer if needed
5. Document deployment addresses for integration teams

### Operational Security
**Environment Management**:
- Use separate `.env` files for different networks
- Never commit actual private keys or sensitive data
- Implement secure key rotation for builder addresses
- Regular monitoring of deployed contract behavior