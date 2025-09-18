use starknet::ContractAddress;

#[starknet::interface]
pub trait IAnalytics<TContractState> {
    // Writes
    fn log_session_start(ref self: TContractState, player: ContractAddress, day: u64);
    fn log_session_end(ref self: TContractState, player: ContractAddress, day: u64);
    fn log_achievement(ref self: TContractState, player: ContractAddress, achievement_id: felt252, day: u64);
    fn log_referral(ref self: TContractState, referrer: ContractAddress, referee: ContractAddress, day: u64);

    // Reads - player scoped
    fn get_player_sessions(self: @TContractState, player: ContractAddress, day: u64) -> u32;
    fn get_player_achievements(self: @TContractState, player: ContractAddress, day: u64) -> u32;
    fn get_player_referrals(self: @TContractState, player: ContractAddress, day: u64) -> u32;

    // Reads - aggregate per day
    fn get_dau(self: @TContractState, day: u64) -> u32;
    fn get_day_sessions(self: @TContractState, day: u64) -> u32;
    fn get_day_achievements(self: @TContractState, day: u64) -> u32;
    fn get_day_referrals(self: @TContractState, day: u64) -> u32;

    // Reads - week aggregates [day, day+6]
    fn get_week_sessions(self: @TContractState, start_day: u64) -> u64;
    fn get_week_dau(self: @TContractState, start_day: u64) -> u64;
}


