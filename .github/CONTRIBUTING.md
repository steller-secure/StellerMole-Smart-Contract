# 🤝 Contributing to StarkMole Smart Contracts

Thank you for your interest in contributing to StarkMole! This document provides guidelines and instructions for contributing to our smart contract suite.

## 📋 Prerequisites

Before contributing, ensure you have:

- [Scarb](https://docs.swmansion.com/scarb/download.html) v2.6.3+
- [SNFoundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html) v0.30.0+
- Basic knowledge of Cairo and StarkNet
- Understanding of smart contract security principles

## 🔄 Development Workflow

### 1. Fork and Clone

\`\`\`bash
# Fork the repository on GitHub
# Clone your fork
git clone https://github.com/YOUR_USERNAME/starkmole-smart-contracts.git
cd starkmole-smart-contracts

# Add upstream remote
git remote add upstream https://github.com/starkmole/smart-contracts.git
\`\`\`

### 2. Set Up Development Environment

\`\`\`bash
# Install dependencies and build
./scripts/build.sh

# Run tests to ensure everything works
./scripts/test.sh
\`\`\`

### 3. Create Feature Branch

\`\`\`bash
# Create and switch to feature branch
git checkout -b feature/your-feature-name

# Keep branch updated with upstream
git fetch upstream
git rebase upstream/main
\`\`\`

## 📝 Coding Standards

### Cairo Code Style

```cairo
// ✅ Good: Clear, descriptive naming
#[storage]
struct Storage {
    game_sessions: LegacyMap<u64, GameSession>,
    player_scores: LegacyMap<ContractAddress, u64>,
}

// ❌ Bad: Unclear, abbreviated naming
#[storage]
struct Storage {
    gs: LegacyMap<u64, GS>,
    ps: LegacyMap<ContractAddress, u64>,
}
