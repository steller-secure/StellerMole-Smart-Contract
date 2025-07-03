use starknet::ContractAddress;

// Reward tier structure
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct RewardTier {
    pub tier_name: felt252,
    pub min_rank: u32,
    pub max_rank: u32,
    pub reward_amount: u256,
    pub percentage_of_pool: u16 // out of 10000 (basis points)
}

// Challenge cycle information
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct ChallengeCycle {
    pub cycle_id: u32,
    pub start_time: u64,
    pub end_time: u64,
    pub total_pool: u256,
    pub is_finalized: bool,
    pub participant_count: u32,
}

// Treasury and Fee Management Structures

// Fee collection record
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct FeeCollection {
    pub fee_type: felt252,
    pub amount: u256,
    pub payer: ContractAddress,
}

// Fee distribution configuration
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct FeeDistribution {
    pub pool_type: felt252,
    pub percentage_bps: u16 // basis points (1/10000)
}

// Pool information
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct PoolInfo {
    pub pool_type: felt252,
    pub balance: u256,
    pub total_inflows: u256,
    pub total_outflows: u256,
}

// Withdrawal proposal for multi-sig operations
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct WithdrawalProposal {
    pub proposal_id: u32,
    pub pool_type: felt252,
    pub amount: u256,
    pub recipient: ContractAddress,
    pub proposer: ContractAddress,
    pub created_at: u64,
    pub executed: bool,
    pub approval_count: u32,
    pub required_approvals: u32,
}

// Fee record for transparency and auditing
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct FeeRecord {
    pub id: u32,
    pub fee_type: felt252,
    pub amount: u256,
    pub payer: ContractAddress,
    pub collector: ContractAddress,
    pub timestamp: u64,
    pub transaction_hash: felt252,
}

// Access control roles
pub mod Roles {
    pub const OWNER: felt252 = 'OWNER';
    pub const ADMIN: felt252 = 'ADMIN';
    pub const FEE_COLLECTOR: felt252 = 'FEE_COLLECTOR';
    pub const EMERGENCY_ROLE: felt252 = 'EMERGENCY_ROLE';
}

// Pool types
pub mod PoolTypes {
    pub const REWARDS_POOL: felt252 = 'REWARDS_POOL';
    pub const DAO_POOL: felt252 = 'DAO_POOL';
    pub const DEV_FUND: felt252 = 'DEV_FUND';
    pub const MARKETING_POOL: felt252 = 'MARKETING_POOL';
    pub const LIQUIDITY_POOL: felt252 = 'LIQUIDITY_POOL';
    pub const INSURANCE_POOL: felt252 = 'INSURANCE_POOL';
}

// Fee types
pub mod FeeTypes {
    pub const GAME_START_FEE: felt252 = 'GAME_START_FEE';
    pub const REWARD_CLAIM_FEE: felt252 = 'REWARD_CLAIM_FEE';
    pub const LEADERBOARD_SUBMIT_FEE: felt252 = 'LEADERBOARD_SUBMIT_FEE';
    pub const BRIDGE_FEE: felt252 = 'BRIDGE_FEE';
    pub const STAKING_FEE: felt252 = 'STAKING_FEE';
    pub const TRANSACTION_FEE: felt252 = 'TRANSACTION_FEE';
}
