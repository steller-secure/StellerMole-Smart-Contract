use starknet::ContractAddress;

// Interface for core game mechanics
#[starknet::interface]
pub trait IStarkMoleGame<TContractState> {
    fn start_game(ref self: TContractState) -> u64;
    fn hit_mole(ref self: TContractState, game_id: u64, mole_position: u8) -> bool;
    fn end_game(ref self: TContractState, game_id: u64) -> u64;
    fn get_game_score(self: @TContractState, game_id: u64) -> u64;
    fn get_player_stats(self: @TContractState, player: ContractAddress) -> (u64, u64, u64);
}

// Interface for leaderboard functions
#[starknet::interface]
pub trait ILeaderboard<TContractState> {
    fn submit_score(ref self: TContractState, player: ContractAddress, score: u64);
    fn get_top_players(self: @TContractState, limit: u32) -> Array<(ContractAddress, u64)>;
    fn get_player_rank(self: @TContractState, player: ContractAddress) -> u32;
    fn get_season_winner(self: @TContractState, season: u32) -> ContractAddress;
    fn get_total_players(self: @TContractState) -> u32;
    fn get_player_score(self: @TContractState, player: ContractAddress) -> u64;
}

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

// Public interface combining lightweight game access
#[starknet::interface]
pub trait IStarkMole<TContractState> {
    fn register(ref self: TContractState);
    fn submit_score(ref self: TContractState, score: u128);
    fn claim_reward(ref self: TContractState);
    fn get_leaderboard(self: @TContractState) -> (ContractAddress, u128, u64);
}

// Reward tier structure
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct RewardTier {
    pub tier_name: felt252,
    pub min_rank: u32,
    pub max_rank: u32,
    pub reward_amount: u256,
    pub percentage_of_pool: u16, // out of 10000 (basis points)
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
