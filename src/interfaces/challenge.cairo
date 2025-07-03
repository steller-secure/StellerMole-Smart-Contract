use starknet::ContractAddress;

// Challenge types
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct Challenge {
    pub challenge_id: u32,
    pub challenge_type: felt252, // 'daily' or 'weekly'
    pub start_time: u64,
    pub end_time: u64,
    pub is_active: bool,
    pub participant_count: u32,
    pub max_participants: u32,
}

#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct ChallengeParticipant {
    pub challenge_id: u32,
    pub participant: ContractAddress,
    pub joined_at: u64,
    pub score: u128,
    pub has_claimed_reward: bool,
}

// Interface for challenge scheduling and management
#[starknet::interface]
pub trait IChallengeScheduler<TContractState> {
    // Challenge Management
    fn create_challenge(
        ref self: TContractState,
        challenge_type: felt252,
        start_time: u64,
        end_time: u64,
        max_participants: u32,
    ) -> u32;

    fn cancel_challenge(ref self: TContractState, challenge_id: u32);

    // Participation Functions
    fn join_challenge(ref self: TContractState, challenge_id: u32);
    fn leave_challenge(ref self: TContractState, challenge_id: u32);
    fn submit_score(ref self: TContractState, challenge_id: u32, score: u128);

    // Query Functions
    fn get_challenge(self: @TContractState, challenge_id: u32) -> Challenge;
    fn get_active_challenges(self: @TContractState) -> Array<Challenge>;
    fn get_historical_challenges(
        self: @TContractState, start_index: u32, count: u32,
    ) -> Array<Challenge>;
    fn get_challenge_participants(
        self: @TContractState, challenge_id: u32,
    ) -> Array<ChallengeParticipant>;
    fn is_participant(
        self: @TContractState, challenge_id: u32, participant: ContractAddress,
    ) -> bool;
    fn get_participant_score(
        self: @TContractState, challenge_id: u32, participant: ContractAddress,
    ) -> u128;

    // Time and Status Functions
    fn is_challenge_active(self: @TContractState, challenge_id: u32) -> bool;
    fn get_current_time(self: @TContractState) -> u64;
    fn get_next_challenge_id(self: @TContractState) -> u32;

    // Admin Functions
    fn set_game_contract(ref self: TContractState, game_contract: ContractAddress);
    fn set_leaderboard_contract(ref self: TContractState, leaderboard_contract: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
}
