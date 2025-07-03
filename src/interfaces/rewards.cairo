use starknet::ContractAddress;
use starkmole::types::{RewardTier, ChallengeCycle};

// Interface for reward and challenge cycle management
#[starknet::interface]
pub trait IRewards<TContractState> {
    // Core reward claiming
    fn claim_reward(ref self: TContractState, cycle_id: u32) -> u256;
    fn get_claimable_reward(self: @TContractState, player: ContractAddress, cycle_id: u32) -> u256;
    fn has_claimed_reward(self: @TContractState, player: ContractAddress, cycle_id: u32) -> bool;

    // Challenge cycle management
    fn create_challenge_cycle(ref self: TContractState, start_time: u64, end_time: u64, total_pool: u256) -> u32;
    fn finalize_challenge_cycle(ref self: TContractState, cycle_id: u32);
    fn get_challenge_cycle(self: @TContractState, cycle_id: u32) -> ChallengeCycle;
    fn get_current_cycle(self: @TContractState) -> u32;

    // Reward tier management
    fn set_reward_tiers(ref self: TContractState, tiers: Array<RewardTier>);
    fn get_reward_tiers(self: @TContractState) -> Array<RewardTier>;
    fn calculate_tier_rewards(self: @TContractState, cycle_id: u32, player: ContractAddress) -> u256;

    // Admin functions
    fn set_token_address(ref self: TContractState, token_address: ContractAddress);
    fn emergency_withdraw(ref self: TContractState, amount: u256);
    fn update_leaderboard_contract(ref self: TContractState, new_address: ContractAddress);

    // View functions
    fn get_total_rewards_distributed(self: @TContractState) -> u256;
    fn get_cycle_statistics(self: @TContractState, cycle_id: u32) -> (u32, u256, u32); // participants, total_pool, claims_made
} 