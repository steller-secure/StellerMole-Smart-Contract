use starknet::ContractAddress;
use starkmole::types::{
    ReferralCode, ReferralRelationship, ReferralStats, ReferralRewardConfig, ReferralRewardClaim
};

// Interface for referral system management
#[starknet::interface]
pub trait IReferral<TContractState> {
    // Referral Code Management
    fn create_referral_code(
        ref self: TContractState, code: felt252, max_uses: u32, expiry_time: u64
    ) -> bool;
    fn deactivate_referral_code(ref self: TContractState, code: felt252);
    fn update_referral_code(
        ref self: TContractState, code: felt252, max_uses: u32, expiry_time: u64
    );
    fn get_referral_code(self: @TContractState, code: felt252) -> ReferralCode;
    fn is_code_valid(self: @TContractState, code: felt252) -> bool;

    // Referral Registration and Tracking
    fn register_with_referral_code(ref self: TContractState, referral_code: felt252) -> bool;
    fn complete_referral(
        ref self: TContractState, referee: ContractAddress, game_score: u64
    ) -> bool;
    fn get_user_referral_relationship(
        self: @TContractState, referee: ContractAddress
    ) -> ReferralRelationship;
    fn has_referrer(self: @TContractState, referee: ContractAddress) -> bool;
    fn get_referrer(self: @TContractState, referee: ContractAddress) -> ContractAddress;

    // Referral Statistics
    fn get_user_stats(self: @TContractState, user: ContractAddress) -> ReferralStats;
    fn get_total_referrals(self: @TContractState, referrer: ContractAddress) -> u32;
    fn get_successful_referrals(self: @TContractState, referrer: ContractAddress) -> u32;
    fn get_pending_rewards(self: @TContractState, user: ContractAddress) -> u256;
    fn get_user_referral_codes(
        self: @TContractState, user: ContractAddress
    ) -> Array<felt252>;
    fn get_user_referrals(
        self: @TContractState, user: ContractAddress
    ) -> Array<ContractAddress>;

    // Reward Management
    fn claim_referral_rewards(ref self: TContractState) -> u256;
    fn calculate_referral_rewards(
        self: @TContractState, referrer: ContractAddress, referee: ContractAddress
    ) -> (u256, u256); // (referrer_reward, referee_reward)
    fn distribute_referral_rewards(
        ref self: TContractState, referrer: ContractAddress, referee: ContractAddress
    ) -> u32; // returns claim_id
    fn get_reward_claim(self: @TContractState, claim_id: u32) -> ReferralRewardClaim;
    fn get_user_reward_claims(
        self: @TContractState, user: ContractAddress
    ) -> Array<ReferralRewardClaim>;

    // Configuration Management
    fn set_reward_config(ref self: TContractState, config: ReferralRewardConfig);
    fn get_reward_config(self: @TContractState) -> ReferralRewardConfig;
    fn update_reward_amounts(
        ref self: TContractState, referrer_reward: u256, referee_reward: u256
    );
    fn update_min_score_requirement(ref self: TContractState, min_score: u64);

    // Integration Functions
    fn set_game_contract(ref self: TContractState, game_contract: ContractAddress);
    fn set_treasury_contract(ref self: TContractState, treasury_contract: ContractAddress);
    fn set_token_contract(ref self: TContractState, token_contract: ContractAddress);
    fn get_game_contract(self: @TContractState) -> ContractAddress;
    fn get_treasury_contract(self: @TContractState) -> ContractAddress;
    fn get_token_contract(self: @TContractState) -> ContractAddress;

    // Anti-abuse and Security
    fn is_self_referral(
        self: @TContractState, referrer: ContractAddress, referee: ContractAddress
    ) -> bool;
    fn check_referral_cooldown(self: @TContractState, user: ContractAddress) -> bool;
    fn get_last_referral_time(self: @TContractState, user: ContractAddress) -> u64;
    fn ban_user(ref self: TContractState, user: ContractAddress);
    fn unban_user(ref self: TContractState, user: ContractAddress);
    fn is_user_banned(self: @TContractState, user: ContractAddress) -> bool;

    // Admin Functions
    fn set_owner(ref self: TContractState, new_owner: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn pause_system(ref self: TContractState);
    fn unpause_system(ref self: TContractState);
    fn is_paused(self: @TContractState) -> bool;
    fn emergency_withdraw(ref self: TContractState, amount: u256);

    // Analytics and Metrics
    fn get_total_referral_codes_created(self: @TContractState) -> u32;
    fn get_total_referral_relationships(self: @TContractState) -> u32;
    fn get_total_rewards_distributed(self: @TContractState) -> u256;
    fn get_system_totals(self: @TContractState) -> (u32, u32, u256);
   
    // Bulk Operations
    fn batch_create_referral_codes(
        ref self: TContractState,
        codes: Array<felt252>,
        max_uses: Array<u32>,
        expiry_times: Array<u64>
    ) -> Array<bool>;
    fn batch_deactivate_referral_codes(ref self: TContractState, codes: Array<felt252>);
} 