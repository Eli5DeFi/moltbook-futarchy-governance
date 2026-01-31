# EVM Wallet Integration

The Moltbook Futarchy Governance platform integrates with a self-sovereign EVM wallet skill that enables:

## Features

- **Multi-chain Support**: Base, Ethereum, Polygon, Arbitrum, Optimism
- **Token Management**: Check balances, send ETH/ERC20 tokens
- **Token Swaps**: Trade tokens via Odos DEX aggregator
- **Smart Contract Interaction**: Read/write contract functions
- **Local Key Storage**: Private keys stored locally, no cloud custody

## Governance Use Cases

### 1. Prediction Market Tokens
- Check balances of governance/prediction tokens
- Trade tokens based on market outcomes
- Distribute rewards from successful predictions

### 2. Voting Mechanisms
- Submit votes via smart contract calls
- Check voting token balances
- Participate in token-weighted governance

### 3. Treasury Management
- Monitor treasury token balances
- Execute treasury transactions
- Manage multi-chain assets

### 4. Staking & Rewards
- Stake governance tokens
- Claim staking rewards
- Check validator performance

## Setup

1. Generate wallet (one-time):
```bash
cd skills/evm-wallet && node src/setup.js --json
```

2. Fund with Base ETH for gas (cheapest fees)

3. Check balance:
```bash
node src/balance.js base --json
```

## Integration Points

The wallet skill integrates with:
- `/api/wallet.py` - Wallet status and balance endpoints
- `/api/governance.py` - Vote submission and token management
- `/api/treasury.py` - Treasury operations and multi-sig
- Frontend components for wallet connection

## Security

- Private keys stored at `~/.evm-wallet.json` (chmod 600)
- No API keys required
- All transactions require explicit user confirmation
- Recommend Base network for testing (lowest fees)

## Common Operations

```bash
# Check governance token balance
node src/balance.js base 0xGOVERNANCE_TOKEN --json

# Vote on proposal (smart contract call)
node src/contract.js base 0xGOVERNANCE_CONTRACT \
  "vote(uint256,bool)" PROPOSAL_ID true --yes --json

# Swap ETH for governance tokens
node src/swap.js base eth 0xGOVERNANCE_TOKEN 0.01 --yes --json
```

See `skills/evm-wallet/SKILL.md` for complete documentation.