#!/bin/bash

echo "🚀 StarkMole Smart Contract Deployment Script"

# Default network
NETWORK=${1:-"sepolia"}
ACCOUNT=${2:-"user"}

if [ "$NETWORK" != "sepolia" ] && [ "$NETWORK" != "mainnet" ]; then
    echo "❌ Invalid network. Use 'sepolia' or 'mainnet'"
    exit 1
fi

echo "🌐 Deploying to StarkNet $NETWORK..."
echo "👤 Using account: $ACCOUNT"

# Check if contracts are built
if [ ! -d "target/dev" ]; then
    echo "📦 Building contracts first..."
    ./scripts/build.sh
fi

echo ""
echo "🎯 Deploying Game Contract..."
GAME_ADDRESS=$(sncast deploy --class-hash $(cat target/dev/starkmole_StarkMoleGame.contract_class.json | jq -r '.class_hash') --constructor-calldata 0x1234 --account $ACCOUNT --network $NETWORK)

echo "🏆 Deploying Leaderboard Contract..."
LEADERBOARD_ADDRESS=$(sncast deploy --class-hash $(cat target/dev/starkmole_Leaderboard.contract_class.json | jq -r '.class_hash') --constructor-calldata 0x1234 $GAME_ADDRESS --account $ACCOUNT --network $NETWORK)

echo "🎁 Deploying Rewards Contract..."
REWARDS_ADDRESS=$(sncast deploy --class-hash $(cat target/dev/starkmole_Rewards.contract_class.json | jq -r '.class_hash') --constructor-calldata 0x1234 $LEADERBOARD_ADDRESS --account $ACCOUNT --network $NETWORK)

echo ""
echo "✅ Deployment completed!"
echo "📝 Contract Addresses:"
echo "  🎮 Game Contract: $GAME_ADDRESS"
echo "  🏆 Leaderboard Contract: $LEADERBOARD_ADDRESS"
echo "  🎁 Rewards Contract: $REWARDS_ADDRESS"
echo ""
echo "💾 Saving addresses to deployments.json..."

cat > deployments.json << EOF
{
  "network": "$NETWORK",
  "deployed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "contracts": {
    "game": "$GAME_ADDRESS",
    "leaderboard": "$LEADERBOARD_ADDRESS",
    "rewards": "$REWARDS_ADDRESS"
  }
}
EOF

echo "🎉 Deployment information saved to deployments.json"
