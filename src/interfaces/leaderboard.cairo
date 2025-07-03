use starknet::ContractAddress;

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