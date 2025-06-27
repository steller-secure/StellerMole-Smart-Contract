use starknet::ContractAddress;

#[starknet::interface]
pub trait IStarkMoleGame<TContractState> {
    fn start_game(ref self: TContractState) -> u64;
    fn hit_mole(ref self: TContractState, game_id: u64, mole_position: u8) -> bool;
    fn end_game(ref self: TContractState, game_id: u64) -> u64;
    fn get_game_score(self: @TContractState, game_id: u64) -> u64;
    fn get_player_stats(self: @TContractState, player: ContractAddress) -> (u64, u64, u64);
}

#[starknet::interface]
pub trait ILeaderboard<TContractState> {
    fn submit_score(ref self: TContractState, player: ContractAddress, score: u64);
    fn get_top_players(self: @TContractState, limit: u32) -> Array<(ContractAddress, u64)>;
    fn get_player_rank(self: @TContractState, player: ContractAddress) -> u32;
    fn get_season_winner(self: @TContractState, season: u32) -> ContractAddress;
}

#[starknet::interface]
pub trait IRewards<TContractState> {
    fn claim_reward(ref self: TContractState, player: ContractAddress) -> u256;
    fn get_pending_rewards(self: @TContractState, player: ContractAddress) -> u256;
    fn distribute_season_rewards(ref self: TContractState, season: u32);
    fn set_reward_multiplier(ref self: TContractState, multiplier: u256);
}
