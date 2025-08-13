# FlashblockNumber Contract

A smart contract for tracking flashblock indices on Unichain, enabling onchain contracts to be aware of their current flashblock position within L2 blocks

## Overview

The Flashblocks Number Contract provides a simple and onchain way to track and expose the current flashblock index within each L2 block on Unichain. Similar to how Solidity's `block.number` provides block-level granularity, this contract enables flashblock-level granularity for time-sensitive applications using the `FlashblockNumber.getFlashblockNumber()` function.

If you are new to Flashblocks, [see the specification for more details](https://github.com/flashbots/rollup-boost/blob/c16d1c187dc4bf7179a1d4727689a31cb0429de1/specs/flashblocks.md)

## Deploy

````
# fill out the .env with the intended arguments, such as whole the initial owner of the contract (i.e. who can modify the array of builders, and who can upgrade the contract) as well as the initial list of builder addresses (i.e. which addresses are allowed to call `incrementFlashblockNumber`)
cp env.sample .env

# load your environment variables
source .env

# deploy the FlashblockNumber contract using the arguments from .env. Replace the `--chain` argument with the chain id of the chain you want to deploy to; in this case we deploy to Unichain Sepolia
forge script script/FlashblockNumber.s.sol --rpc-url $RPC_URL --broadcast --verify --interactives 1 --chain 1301

### Key Features

- **Flashblock Tracking**: Maintains a monotonically increasing flashblock number which acts as a counter external contracts can use to track a range of flashblocks
- **Builder Authorization**: Only allowlisted builders can increment the flashblock counter, ensuring controlled and reliable updates from trusted builder (e.g. Flashbots)
- **Builder High Availability**: Multiple builder addresses are permissioned to update the onchain flashblock number, allowing multiple builders to fail and still allow for a healthy builder to update the onchain flashblock number
- **Robust Against Total Remote Builder Failure**: Even if all builders fail, or there is a network error between the Unichain sequencer and the remote builder, the FlashblockNumber contract will return a the latest flashblock number, which ensures that external smart contracts will still function correctly even when a block is built locally (i.e. not by a remote builder)
- **UUPS Upgradeable**: Implements the Universal Upgradeable Proxy Standard for future contract upgrades/improvements. Once the maintainers decide there are no need for further updates, and the contract has been battle-tested, they will transfer ownership to an address with no known private key (i.e. there will be no owner of the FlashblockNumber contract)
- **EIP-712 Support**: Includes meta-transaction capabilities to simplify TEE-builder gas concerns
- **Event Emission**: Emits events for flashblock increments and builder management for easy monitoring

### Use Cases

- **Time-Sensitive DeFi**: Applications like UniswapX that use flashblock numbers for order decay calculations
- **MEV Protection**: Contracts that need to enforce ordering constraints within flashblocks

## Constraints

### Technical Requirements

1. **Builder Limitations**

   - Strict monotonic flashblock number ordering enforced
   - updates to the onchain flashblock number must occur at the beginning of each flashblock

2. **Invariants**

   - Flashblock never decreases (except from reorgs)
   - Only allowlisted builders can call `incrementFlashblockNumber()`
   - Calls must occur exactly once per flashblock

3. **Security Considerations**
   - No external calls during state updates to prevent reentrancy
   - Access control via OpenZeppelin's battle-tested libraries

### Operational Constraints

- **Builder Reliability**: System depends on at least one active builder to maintain flashblock number liveness
- **Upgrade Governance**: Contract upgrades require multisig approval

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Node.js 16+ (for additional tooling)
- Git

### Installation

1. Clone the repository:

```bash
git clone https://github.com/uniswap/flashblocks_number_contract
cd flashblocks_number_contract
````

2. Install dependencies:

```bash
forge install
```

3. Build the project:

```bash
forge build
```

### Deployment

1. Set up environment variables:

```bash
cp .env.example .env
# Edit .env with your configuration
```

2. Deploy using the deployment script:

```bash
forge script script/Deploy.s.sol:DeployFlashblockNumber --rpc-url $RPC_URL --broadcast --verify
```

### Integration

To integrate with the Flashblocks Number Contract:

```solidity
import "./IFlashblockNumber.sol";

contract YourContract {
    IFlashblockNumber public flashblockNumber;

    function checkFlashblock() internal view returns (uint256) {
        return flashblockNumber.getFlashblockNumber();
    }
}
```

## Testing

### Running Tests

Execute the full test suite:

```bash
forge test
```

Run with verbosity for detailed output:

```bash
forge test -vvv
```

### Test Coverage

Generate coverage reports:

```bash
forge coverage
```

### Fuzz Testing

Run fuzz tests with extended runs:

```bash
forge test --match-test testFuzz -vvv --fuzz-runs 10000
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flashblocks specification by Flashbots
