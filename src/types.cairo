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

// Governance types and structures
pub mod governance {
    use starknet::ContractAddress;

    // Proposal structure (core data)
    #[derive(Drop, Serde, starknet::Store, Copy)]
    pub struct Proposal {
        pub id: u256,
        pub proposer: ContractAddress,
        pub description: felt252,
        pub start_time: u64,
        pub end_time: u64,
        pub for_votes: u256,
        pub against_votes: u256,
        pub abstain_votes: u256,
        pub canceled: bool,
        pub executed: bool,
        pub queued: bool,
        pub queue_time: u64,
        pub targets_count: u32,
    }

    // Proposal action structure (stored separately for each action)
    #[derive(Drop, Serde, starknet::Store, Copy)]
    pub struct ProposalAction {
        pub proposal_id: u256,
        pub action_index: u32,
        pub target: ContractAddress,
        pub value: u256,
        pub calldata_hash: felt252 // hash of the calldata for verification
    }

    // Vote receipt structure
    #[derive(Drop, Serde, starknet::Store, Copy)]
    pub struct VoteReceipt {
        pub voter: ContractAddress,
        pub proposal_id: u256,
        pub support: u8, // 0 = against, 1 = for, 2 = abstain
        pub voting_power: u256,
        pub reason: felt252,
        pub timestamp: u64,
    }

    // Governance configuration
    #[derive(Drop, Serde, starknet::Store, Copy)]
    pub struct GovernanceConfig {
        pub voting_delay: u64, // delay before voting starts (in seconds)
        pub voting_period: u64, // voting period duration (in seconds)
        pub proposal_threshold: u256, // minimum tokens needed to propose
        pub quorum_percentage: u16, // quorum percentage (basis points)
        pub timelock_delay: u64, // execution delay (in seconds)
        pub min_proposal_interval: u64 // minimum time between proposals from same user
    }

    // Proposal states
    pub mod ProposalState {
        pub const PENDING: u8 = 0; // proposal created but voting not started
        pub const ACTIVE: u8 = 1; // voting is active
        pub const CANCELED: u8 = 2; // proposal was canceled
        pub const DEFEATED: u8 = 3; // proposal was defeated
        pub const SUCCEEDED: u8 = 4; // proposal succeeded but not queued
        pub const QUEUED: u8 = 5; // proposal queued for execution
        pub const EXPIRED: u8 = 6; // proposal expired without execution
        pub const EXECUTED: u8 = 7; // proposal executed
    }

    // Vote types
    pub mod VoteType {
        pub const AGAINST: u8 = 0;
        pub const FOR: u8 = 1;
        pub const ABSTAIN: u8 = 2;
    }
}

// Challenge constants
pub mod ChallengeConstants {
    pub const MIN_CHALLENGE_DURATION: u64 = 3600; // 1 hour in seconds
    pub const MAX_CHALLENGE_DURATION: u64 = 604800; // 1 week in seconds
    pub const MAX_PARTICIPANTS_DEFAULT: u32 = 1000;
    pub const CHALLENGE_CREATION_FEE: u256 = 1000000000000000000; // 1 token
}

// Referral System Types

// Referral code structure
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct ReferralCode {
    pub code: felt252,
    pub referrer: ContractAddress,
    pub created_at: u64,
    pub is_active: bool,
    pub max_uses: u32,
    pub current_uses: u32,
    pub expiry_time: u64, // 0 means no expiry
}

// Referral relationship between referrer and referee
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct ReferralRelationship {
    pub referrer: ContractAddress,
    pub referee: ContractAddress,
    pub referral_code: felt252,
    pub timestamp: u64,
    pub rewards_claimed: bool,
    pub first_game_completed: bool,
}

// Referral statistics for each user
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct ReferralStats {
    pub total_referrals: u32,
    pub successful_referrals: u32, // referrals who completed first game
    pub total_rewards_earned: u256,
    pub pending_rewards: u256,
    pub last_referral_time: u64,
}

// Referral reward configuration
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct ReferralRewardConfig {
    pub referrer_reward: u256, // reward for the referrer
    pub referee_reward: u256, // reward for the referee
    pub min_game_score: u64, // minimum score required to trigger rewards
    pub reward_delay: u64, // delay before rewards can be claimed (anti-spam)
    pub is_active: bool,
}

// Referral reward claim record
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct ReferralRewardClaim {
    pub claim_id: u32,
    pub referrer: ContractAddress,
    pub referee: ContractAddress,
    pub referrer_amount: u256,
    pub referee_amount: u256,
    pub claimed_at: u64,
    pub transaction_hash: felt252,
}

// Referral system constants
pub mod ReferralConstants {
    pub const DEFAULT_REFERRER_REWARD: u256 = 10000000000000000000; // 10 tokens
    pub const DEFAULT_REFEREE_REWARD: u256 = 5000000000000000000; // 5 tokens
    pub const DEFAULT_MIN_SCORE: u64 = 1000; // minimum score to trigger rewards
    pub const DEFAULT_REWARD_DELAY: u64 = 300; // 5 minutes delay
    pub const MAX_REFERRAL_CODE_LENGTH: u32 = 31; // max length for felt252
    pub const DEFAULT_CODE_EXPIRY: u64 = 2592000; // 30 days
    pub const MAX_CODE_USES: u32 = 1000;
    pub const ANTI_SPAM_COOLDOWN: u64 = 86400; // 24 hours between referrals from same address
}

// Referral types for events and function parameters
pub mod ReferralTypes {
    pub const CODE_CREATED: felt252 = 'CODE_CREATED';
    pub const CODE_USED: felt252 = 'CODE_USED';
    pub const REWARD_DISTRIBUTED: felt252 = 'REWARD_DISTRIBUTED';
    pub const REFERRAL_COMPLETED: felt252 = 'REFERRAL_COMPLETED';
}
