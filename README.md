
🎮 StarkMole Contracts
StarkMole Contracts is the Cairo-based smart contract suite powering StarkMole — a decentralized whack-a-mole game built on the StarkNet ecosystem. These contracts handle player sessions, game state updates, scoring, leaderboard logic, and reward distribution in a transparent and verifiable manner.

🧾 Overview
StarkMole merges fun, competition, and blockchain by using Cairo smart contracts to bring classic arcade mechanics to Web3. With on-chain scorekeeping, tamper-proof logic, and wallet-based rewards, players enjoy a play-to-earn experience backed by StarkNet's scalability and security.

📁 Project Structure
starkmole_contracts/
├── README.md
├── Scarb.lock               # Dependency lockfile
├── Scarb.toml               # Project config
├── snfoundry.toml           # SNFoundry test config
├── src/
│   ├── base/
│   │   └── types.cairo       # Shared type definitions (e.g., Score, Player)
│   ├── starkmole/
│   │   └── Game.cairo        # Main game logic: sessions, scoring, rewards
│   ├── interfaces/
│   │   └── IGame.cairo       # Interface declarations
│   └── lib.cairo             # Core game logic utilities
└── tests/
    └── test_Game.cairo       # Unit tests for game mechanics
🧰 Prerequisites
Scarb – Cairo package manager

SNFoundry – Testing framework for StarkNet smart contracts

⚙️ Installation
Clone the repository and install dependencies:

git clone https://github.com/StarkMole/starkmole_contracts.git
cd starkmole_contracts

🕹️ Contract Overview
🎯 Game Contract
The Game contract controls all gameplay logic:

Start Game Sessions – Initiate new player sessions on-chain

Score Tracking – Record player hits and session scores in real time

Leaderboard Management – Store and retrieve top player scores

Reward Distribution – Allocate tokens or NFTs to top performers

Fair Play Enforcement – Ensure tamper-proof and fair gameplay using Cairo logic

🏗️ Building the Project
To compile all contracts, run:
scarb build

🧪 Testing
Run all tests with SNFoundry:
snforge test

🚀 Join the GameFi Revolution
Whether you're a gamer or a Cairo dev, StarkMole invites you to play, build, and earn in the decentralized arcade of the future.

Happy Molding! 🐹🔨
StarkMole Team
