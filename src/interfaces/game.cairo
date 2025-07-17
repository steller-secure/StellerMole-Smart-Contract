use starknet::ContractAddress;

// Interface for core game mechanics
#[starknet::interface]
pub trait IStarkMoleGame<TContractState> {
    fn start_game(ref self: TContractState) -> u64;
    fn hit_mole(ref self: TContractState, game_id: u64, mole_position: u8) -> bool;
    fn end_game(ref self: TContractState, game_id: u64) -> u64;
    fn get_game_score(self: @TContractState, game_id: u64) -> u64;
    fn get_player_stats(self: @TContractState, player: ContractAddress) -> (u64, u64, u64);
    fn set_referral_contract(ref self: TContractState, referral_contract: ContractAddress);
}

// Public interface combining lightweight game access
#[starknet::interface]
pub trait IStarkMole<TContractState> {
    fn register(ref self: TContractState);
    fn submit_score(ref self: TContractState, score: u128);
    fn claim_reward(ref self: TContractState);
    fn get_leaderboard(self: @TContractState) -> (ContractAddress, u128, u64);
}
