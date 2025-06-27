#!/bin/bash

echo "🧪 Running StarkMole Smart Contract Tests..."

# Check if SNFoundry is installed
if ! command -v snforge &> /dev/null; then
    echo "❌ SNFoundry is not installed. Please install SNFoundry first."
    echo "Visit: https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html"
    exit 1
fi

echo "🔍 Running unit tests..."
snforge test

if [ $? -eq 0 ]; then
    echo "✅ All tests passed!"
else
    echo "❌ Some tests failed. Please review the output above."
    exit 1
fi

echo ""
echo "📊 Test Coverage Summary:"
echo "  - Game Contract: Core functionality tested"
echo "  - Leaderboard Contract: Score submission and ranking tested"
echo "  - Rewards Contract: Basic reward mechanics tested"
echo ""
echo "🔒 Security Note: These are basic tests. Additional security audits recommended."
