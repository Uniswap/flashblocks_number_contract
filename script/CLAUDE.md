# CLAUDE.md - Deployment Scripts

## Overview

This directory contains deployment and management scripts for the FlashblockNumber contract system. The scripts handle UUPS proxy deployment with deterministic addresses, proper initialization with TEE infrastructure references, and post-deployment verification.

**Deployment Strategy**: Uses OpenZeppelin's UUPS proxy pattern with CREATE3 for deterministic cross-network addresses, ensuring consistent contract addresses across different blockchain networks. V2 deployments require registry and policy contract addresses instead of initial builder addresses.

## Key Components

### FlashblockNumber.s.sol
**Purpose**: Deployment script for V2 contract with TEE-based authorization. Deploys upgradeable proxy with registry and policy initialization.

**Core Functionality**:
- **Environment Configuration**: Reads deployment parameters from environment variables
- **Registry/Policy Integration**: Initializes contract with FlashtestationRegistry and BlockBuilderPolicy addresses
- **UUPS Deployment**: Deploys upgradeable proxy with TEE infrastructure references
- **Post-Deployment Verification**: Confirms correct deployment and configuration
- **Console Logging**: Provides detailed deployment progress and results

## V2 Deployment Architecture

### Environment-Driven Configuration
**Required Environment Variables** (from `.env` file):
- `FLASHBLOCK_NUMBER_OWNER`: Contract owner address (typically a multisig)
- `FLASHTESTATION_REGISTRY_ADDRESS`: Address of deployed FlashtestationRegistry contract
- `BLOCK_BUILDER_POLICY_ADDRESS`: Address of deployed BlockBuilderPolicy contract
- `RPC_URL`: Target network RPC endpoint
- `ETHERSCAN_API_KEY`: API key for contract verification

**Configuration Pattern** (V2):
```solidity
address owner = vm.envAddress("FLASHBLOCK_NUMBER_OWNER");
address registry = vm.envAddress("FLASHTESTATION_REGISTRY_ADDRESS");
address policy = vm.envAddress("BLOCK_BUILDER_POLICY_ADDRESS");
```

**Removed Variables** (V1 only):
- `INITIAL_BUILDERS`: No longer needed - authorization managed by registry and policy

### UUPS Proxy Deployment (V2)
**Deployment Process**:
1. **Environment Loading**: Parse owner, registry, and policy addresses from environment
2. **Address Validation**: Verify all addresses are valid and non-zero
3. **Registry/Policy Pre-Check**: Optionally verify registry and policy contracts exist and are valid
4. **Proxy Deployment**: Use OpenZeppelin's `Upgrades.deployUUPSProxy()`
5. **Initialization**: Call `initialize()` with owner, registry, and policy addresses
6. **Verification**: Confirm deployment success and proper configuration

**Key Deployment Code** (V2):
```solidity
address proxyAddress = Upgrades.deployUUPSProxy(
    "FlashblockNumber.sol",
    abi.encodeCall(FlashblockNumber.initialize, (owner, registry, policy))
);
```

## Deployment Features

### Deterministic Addresses
**CREATE3 Benefits**:
- Same contract address across different networks
- Address determination before actual deployment
- Independence from deployment account nonce
- Simplified cross-network integration

**Address Predictability**: External contracts can hardcode the FlashblockNumber address even before deployment, enabling seamless integration across multiple networks.

### Comprehensive Verification
**Post-Deployment Checks** (V2):
```solidity
// Verify basic deployment
console.log("FlashblockNumber deployed at:", proxyAddress);
console.log("Flashblock number:", flashblock.getFlashblockNumber());
console.log("Owner:", flashblock.owner());
console.log("Registry:", flashblock.registry());
console.log("Policy:", flashblock.policy());

// Verify registry and policy are set correctly
require(flashblock.registry() == registry, "Registry not properly set");
require(flashblock.policy() == policy, "Policy not properly set");
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

### Environment Setup (V2)
1. **Copy Template**: `cp env.sample .env`
2. **Configure Owner**: Set `FLASHBLOCK_NUMBER_OWNER` to multisig or EOA address
3. **Set Registry**: Configure `FLASHTESTATION_REGISTRY_ADDRESS` with deployed registry address
4. **Set Policy**: Configure `BLOCK_BUILDER_POLICY_ADDRESS` with deployed policy address
5. **Network Configuration**: Set `RPC_URL` for target network
6. **Verification Setup**: Add `ETHERSCAN_API_KEY` for contract verification

**Prerequisites**:
- FlashtestationRegistry must be deployed first
- BlockBuilderPolicy must be deployed first
- Both contracts must be on the same network as FlashblockNumber deployment

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
- Registry and policy addresses may differ per network

**Network Deployment Checklist**:
1. Verify FlashtestationRegistry is deployed on target network
2. Verify BlockBuilderPolicy is deployed on target network
3. Update `.env` with correct registry and policy addresses for network
4. Update RPC_URL for target network
5. Deploy FlashblockNumber
6. Verify all three contracts interact correctly

## V1 to V2 Upgrade Script

**Upgrade Process** (for existing V1 deployments):
```solidity
// Upgrade script pattern
address proxyAddress = vm.envAddress("FLASHBLOCK_NUMBER_PROXY");
address registry = vm.envAddress("FLASHTESTATION_REGISTRY_ADDRESS");
address policy = vm.envAddress("BLOCK_BUILDER_POLICY_ADDRESS");

vm.startBroadcast();

// Upgrade to V2 implementation
Upgrades.upgradeProxy(proxyAddress, "FlashblockNumber.sol:FlashblockNumber", "");

// Reinitialize with registry and policy
FlashblockNumber(proxyAddress).reinitializeV2(registry, policy);

vm.stopBroadcast();

// Verify upgrade
FlashblockNumber flashblock = FlashblockNumber(proxyAddress);
require(flashblock.registry() == registry, "Registry not set");
require(flashblock.policy() == policy, "Policy not set");
```

## Script Architecture Details

### Error Handling
**Validation Patterns** (V2):
- Environment variable existence checking
- Address format validation with clear error messages
- Registry and policy address validation (non-zero checks)
- Post-deployment state verification

**Error Examples**:
```solidity
require(owner != address(0), "Owner address cannot be zero");
require(registry != address(0), "Registry address cannot be zero");
require(policy != address(0), "Policy address cannot be zero");
require(flashblock.registry() == registry, "Registry not properly set");
require(flashblock.policy() == policy, "Policy not properly set");
```

### Gas Optimization
**Deployment Efficiency**:
- Single transaction deployment via proxy pattern
- Initialization with registry and policy addresses (more gas efficient than multiple builders)
- Minimal external calls during deployment
- Optimized for high gas limit networks

### Logging and Monitoring
**Console Output Structure** (V2):
- Deployment parameters confirmation (owner, registry, policy)
- Progress indicators during execution
- Final deployment summary with all addresses
- Registry and policy verification status

## Development and Maintenance

### Script Modification Guidelines
1. **Environment Variable Changes**: Update both script and `env.sample`
2. **Validation Logic**: Maintain strict input validation for security
3. **Console Logging**: Keep detailed logging for deployment transparency
4. **Error Messages**: Provide clear, actionable error descriptions
5. **TEE Infrastructure**: Always verify registry and policy addresses are correct

### Testing Deployment Scripts
**Local Testing**:
```bash
# Test on local Anvil network
anvil &

# Deploy mock registry and policy first
forge script script/DeployMocks.s.sol --rpc-url http://localhost:8545 --broadcast

# Then deploy FlashblockNumber
forge script script/FlashblockNumber.s.sol --rpc-url http://localhost:8545 --broadcast
```

**Testnet Validation**:
- Deploy registry and policy to testnet first
- Deploy FlashblockNumber with correct registry and policy addresses
- Verify all functionality works correctly
- Test upgrade scenarios on testnet
- Confirm Etherscan verification works

### Upgrade Script Patterns
**Future Upgrade Scripts**: When contract upgrades are needed, follow similar patterns:
- Load existing proxy address from deployment artifacts or environment
- Prepare new implementation deployment
- Use `Upgrades.upgradeProxy()` for seamless upgrades
- If storage layout changes, create new `reinitialize_vX()` function
- Verify upgrade success and functionality preservation

## Security Considerations

### Deployment Security
**Access Control Setup**:
- Owner address should be a secure multisig for production
- Registry and policy contracts should be governance-controlled
- Private keys never stored in environment files or version control
- Verify registry and policy contracts are legitimate before deployment

**Registry and Policy Validation**:
- Verify registry contract implements IFlashtestationRegistry interface
- Verify policy contract implements IBlockBuilderPolicy interface
- Check registry and policy have appropriate governance controls
- Confirm registry and policy are not malicious or compromised

**Network Security**:
- Use secure, reliable RPC providers
- Verify network ID matches intended deployment target
- Confirm gas price and limits appropriate for network conditions

### Post-Deployment Security
**Immediate Actions After Deployment**:
1. Verify contract bytecode on explorer
2. Test basic functionality with small transactions
3. Confirm registry and policy addresses are correct and functional
4. Test that TEE-authorized builders can increment flashblock numbers
5. Validate ownership transfer if needed
6. Document deployment addresses for integration teams
7. Verify cache behavior with test increments

### Operational Security
**Environment Management**:
- Use separate `.env` files for different networks
- Never commit actual private keys or sensitive data
- Maintain secure documentation of registry and policy addresses per network
- Regular monitoring of deployed contract behavior
- Monitor registry and policy contract changes that may affect authorization

**TEE Infrastructure Dependencies**:
- Keep track of registry and policy contract upgrades
- Monitor for policy changes that may affect builder authorization
- Document approved workloads and their purposes
- Coordinate with Flashbots and Unichain teams for policy updates
