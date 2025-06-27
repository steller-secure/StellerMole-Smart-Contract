# 🐹 StarkMole Smart Contract Suite

> **Decentralized Whack-a-Mole Gaming on StarkNet** - Secure, Fast, and Fun! ⚡

[![CI/CD Pipeline](https://github.com/starkmole/smart-contracts/workflows/StarkMole%20CI/CD%20Pipeline/badge.svg)](https://github.com/starkmole/smart-contracts/actions)
[![Security Audit](https://github.com/starkmole/smart-contracts/workflows/Security%20Audit/badge.svg)](https://github.com/starkmole/smart-contracts/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 📚 Overview

StarkMole is a fully decentralized whack-a-mole game built on StarkNet using Cairo. This repository contains the smart contract suite that powers secure, transparent, and fair gameplay with on-chain leaderboards and reward distribution.

## 🏗️ Architecture

\`\`\`
starkmole/
├── contracts/
│   ├── game/           # Core game logic and mechanics
│   ├── leaderboard/    # On-chain rankings and seasons
│   └── rewards/        # Token rewards and distribution
├── src/                # Shared libraries and interfaces
├── tests/              # Comprehensive test suite
├── scripts/            # Build, test, and deployment utilities
└── .github/            # CI/CD workflows and templates
\`\`\`

## 🚀 Quick Start

### Prerequisites

- [Scarb](https://docs.swmansion.com/scarb/download.html) v2.6.3+
- [SNFoundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html) v0.30.0+
- [StarkNet CLI](https://github.com/starkware-libs/starknet.py) (for deployment)

### Installation

\`\`\`bash
# Clone the repository
git clone https://github.com/starkmole/smart-contracts.git
cd smart-contracts

# Build contracts
./scripts/build.sh

# Run tests
./scripts/test.sh
\`\`\`

### Deployment

\`\`\`bash
# Deploy to StarkNet Sepolia (testnet)
./scripts/deploy.sh sepolia

# Deploy to StarkNet Mainnet (production)
./scripts/deploy.sh mainnet
\`\`\`

## 🎮 Contract Overview

### Game Contract (`contracts/game/game.cairo`)
- **Game Session Management**: Start, play, and end game sessions
- **Hit Detection**: Validate mole hits with anti-cheat mechanisms
- **Score Calculation**: Dynamic scoring with combo multipliers
- **Cooldown Protection**: Prevent spam and ensure fair play

### Leaderboard Contract (`contracts/leaderboard/leaderboard.cairo`)
- **Global Rankings**: Track top players across seasons
- **Season Management**: Automated season transitions
- **Score Validation**: Only accept scores from verified game sessions

### Rewards Contract (`contracts/rewards/rewards.cairo`)
- **Token Distribution**: Automated reward calculations
- **Claim Mechanism**: Secure reward claiming for players
- **Season Rewards**: Special rewards for season winners

## 🔒 Security Features

- **Replay Protection**: Prevent transaction replay attacks
- **Cooldown Enforcement**: Anti-spam mechanisms
- **Access Control**: Role-based contract permissions
- **Randomness Security**: Secure pseudo-random mole positioning
- **Score Validation**: Cryptographic game state verification

## 🧪 Testing

Run the comprehensive test suite:

\`\`\`bash
# All tests
snforge test

# Specific test file
snforge test tests/test_game.cairo

# With coverage
snforge test --coverage
\`\`\`

### Test Coverage
- ✅ Game mechanics and state transitions
- ✅ Leaderboard ranking algorithms
- ✅ Reward distribution logic
- ✅ Security and access control
- ✅ Edge cases and error handling

## 📊 Gas Optimization

Our contracts are optimized for minimal gas usage:

- **Efficient Storage**: Packed structs and optimized mappings
- **Batch Operations**: Minimize transaction calls
- **Event Optimization**: Efficient event emission
- **Cairo Best Practices**: Following StarkNet optimization guidelines

## 🛠️ Development

### Environment Setup

\`\`\`bash
# Install development dependencies
scarb build

# Setup pre-commit hooks
pre-commit install

# Format code
scarb fmt

# Run linter
scarb build --check
\`\`\`

### Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m "feat: add amazing feature"`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for detailed guidelines.

## 🚀 Deployment Status

### Testnet (Sepolia)
- 🎮 Game Contract: `0x...` (Coming Soon)
- 🏆 Leaderboard: `0x...` (Coming Soon)
- 🎁 Rewards: `0x...` (Coming Soon)

### Mainnet
- 🎮 Game Contract: `0x...` (TBD)
- 🏆 Leaderboard: `0x...` (TBD)
- 🎁 Rewards: `0x...` (TBD)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Acknowledgments

- **StarkWare** for StarkNet and Cairo
- **OpenZeppelin** for security libraries
- **StarkNet Community** for ecosystem support

## 📞 Support

- 📧 Email: dev@starkmole.com
- 💬 Discord: [StarkMole Community](https://discord.gg/starkmole)
- 🐦 Twitter: [@StarkMole](https://twitter.com/starkmole)

---

**Built with ❤️ on StarkNet** - Let the moles pop and the fun begin! 🐹🎯
