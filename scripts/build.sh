#!/bin/bash

echo "🔨 Building StarkMole Smart Contracts..."

# Check if Scarb is installed
if ! command -v scarb &> /dev/null; then
    echo "❌ Scarb is not installed. Please install Scarb first."
    echo "Visit: https://docs.swmansion.com/scarb/download.html"
    exit 1
fi

# Check if SNFoundry is installed
if ! command -v snforge &> /dev/null; then
    echo "❌ SNFoundry is not installed. Please install SNFoundry first."
    echo "Visit: https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html"
    exit 1
fi

echo "📦 Installing dependencies..."
scarb build

if [ $? -eq 0 ]; then
    echo "✅ Build completed successfully!"
    echo "📄 Contract artifacts generated in target/dev/"
    
    echo ""
    echo "📋 Available contracts:"
    echo "  - StarkMoleGame: contracts/game/game.cairo"
    echo "  - Leaderboard: contracts/leaderboard/leaderboard.cairo"
    echo "  - Rewards: contracts/rewards/rewards.cairo"
else
    echo "❌ Build failed. Please check the errors above."
    exit 1
fi
