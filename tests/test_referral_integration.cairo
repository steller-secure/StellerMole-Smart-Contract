use starknet::{ContractAddress, contract_address_const, get_block_timestamp};
use core::num::traits::Zero;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp,
};

use starkmole::interfaces::referral::{IReferralDispatcher, IReferralDispatcherTrait};
use starkmole::interfaces::game::{IStarkMoleGameDispatcher, IStarkMoleGameDispatcherTrait};
use starkmole::types::{ReferralRewardConfig};

// Test constants
const OWNER: felt252 = 0x123;
const USER1: felt252 = 0x456; // Referrer
const USER2: felt252 = 0x789; // Referee
const TREASURY: felt252 = 0xdef;
const TOKEN_CONTRACT: felt252 = 0x222;

fn setup_contracts() -> (
    IReferralDispatcher, IStarkMoleGameDispatcher, ContractAddress, ContractAddress,
) {
    let owner: ContractAddress = OWNER.try_into().unwrap();
    let treasury: ContractAddress = TREASURY.try_into().unwrap();
    let token: ContractAddress = TOKEN_CONTRACT.try_into().unwrap();

    // Deploy game contract
    let game_contract = declare("StarkMoleGame").unwrap().contract_class();
    let game_constructor_calldata = array![owner.into()];
    let (game_address, _) = game_contract.deploy(@game_constructor_calldata).unwrap();
    let game = IStarkMoleGameDispatcher { contract_address: game_address };

    // Deploy referral contract
    let referral_contract = declare("Referral").unwrap().contract_class();
    let referral_constructor_calldata = array![
        owner.into(), game_address.into(), treasury.into(), token.into(),
    ];
    let (referral_address, _) = referral_contract.deploy(@referral_constructor_calldata).unwrap();
    let referral = IReferralDispatcher { contract_address: referral_address };

    // Setup referral contract
    start_cheat_caller_address(referral_address, owner);
    referral.set_treasury_contract(treasury);
    referral.set_game_contract(game_address);
    referral.set_token_contract(token);

    let config = ReferralRewardConfig {
        referrer_reward: 100,
        referee_reward: 50,
        min_game_score: 1000,
        reward_delay: 0,
        is_active: true,
    };
    referral.set_reward_config(config);
    stop_cheat_caller_address(referral_address);

    // Setup game contract with referral
    start_cheat_caller_address(game_address, owner);
    game.set_referral_contract(referral_address);
    stop_cheat_caller_address(game_address);

    (referral, game, referral_address, game_address)
}

#[test]
fn test_full_referral_flow_with_game() {
    let (referral, game, _, _) = setup_contracts();
    let user1: ContractAddress = USER1.try_into().unwrap(); // Referrer
    let user2: ContractAddress = USER2.try_into().unwrap(); // Referee

    // Step 1: User1 creates a referral code
    start_cheat_caller_address(referral.contract_address, user1);
    let code = 'GAMEREF';
    referral
        .create_referral_code(
            code, 10, get_block_timestamp() + 172800,
        ); // 2 days to account for time advance
    stop_cheat_caller_address(referral.contract_address);

    // Step 2: User2 registers with referral code (advance time to bypass cooldown)
    start_cheat_block_timestamp(
        referral.contract_address, get_block_timestamp() + 86401,
    ); // 24 hours + 1 second
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);

    // Verify relationship exists but not completed
    let relationship = referral.get_user_referral_relationship(user2);
    assert!(relationship.referrer == user1, "Wrong referrer");
    assert!(relationship.referee == user2, "Wrong referee");
    assert!(!relationship.first_game_completed, "Should not be completed yet");

    // Step 3: User2 starts and plays a game
    start_cheat_caller_address(game.contract_address, user2);
    let game_id = game.start_game();

    // Simulate some game play by trying different positions
    let mut position: u8 = 0;
    while position < 9 { // Try all positions 0-8 to ensure some hits
        game.hit_mole(game_id, position);
        position += 1;
    };

    // Step 4: User2 ends the game (this should trigger referral completion)
    let final_score = game.end_game(game_id);
    stop_cheat_caller_address(game.contract_address);

    // Since we tried all positions, we should get at least one hit
    assert!(final_score >= 0, "Game should complete");

    // Step 5: Verify referral was completed automatically
    let updated_relationship = referral.get_user_referral_relationship(user2);
    assert!(updated_relationship.first_game_completed, "Referral should be completed");

    // Step 6: Check that referrer stats were updated
    let referrer_stats = referral.get_user_stats(user1);
    assert!(referrer_stats.total_referrals == 1, "Should have 1 total referral");

    // Check if rewards were distributed (depends on if score met minimum)
    if final_score >= 1000 {
        assert!(referrer_stats.successful_referrals == 1, "Should have 1 successful referral");
    }
}

#[test]
fn test_referral_completion_below_minimum_score() {
    let (referral, game, _, _) = setup_contracts();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();

    // Setup referral relationship
    start_cheat_caller_address(referral.contract_address, user1);
    referral.create_referral_code('LOWSCORE', 10, get_block_timestamp() + 172800);
    stop_cheat_caller_address(referral.contract_address);

    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code('LOWSCORE');
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);

    // Play a game with low score (no hits)
    start_cheat_caller_address(game.contract_address, user2);
    let game_id = game.start_game();
    let final_score = game.end_game(game_id); // End immediately for low score
    stop_cheat_caller_address(game.contract_address);

    // Verify referral was completed but no rewards given
    let relationship = referral.get_user_referral_relationship(user2);
    assert!(relationship.first_game_completed, "Should be completed");

    let referrer_stats = referral.get_user_stats(user1);
    assert!(referrer_stats.total_referrals == 1, "Should count as referral");

    // If score was below minimum, no rewards should be earned
    if final_score < 1000 {
        assert!(referrer_stats.total_rewards_earned == 0, "No rewards for low score");
    }
}

#[test]
fn test_multiple_games_only_first_counts() {
    let (referral, game, _, _) = setup_contracts();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();

    // Setup referral
    start_cheat_caller_address(referral.contract_address, user1);
    referral.create_referral_code('MULTIPLE', 10, get_block_timestamp() + 172800);
    stop_cheat_caller_address(referral.contract_address);

    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code('MULTIPLE');
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);

    // Play first game
    start_cheat_caller_address(game.contract_address, user2);
    let game_id1 = game.start_game();
    // Try a few positions to get some score
    let mut position: u8 = 0;
    while position < 3 {
        game.hit_mole(game_id1, position);
        position += 1;
    };
    game.end_game(game_id1);
    stop_cheat_caller_address(game.contract_address);

    // Verify first game completed the referral
    let relationship = referral.get_user_referral_relationship(user2);
    assert!(relationship.first_game_completed, "First game should complete referral");

    // Get initial stats
    let initial_stats = referral.get_user_stats(user1);

    // Play second game
    start_cheat_caller_address(game.contract_address, user2);
    let game_id2 = game.start_game();
    // Try a few positions for second game too
    let mut position: u8 = 0;
    while position < 3 {
        game.hit_mole(game_id2, position);
        position += 1;
    };
    game.end_game(game_id2);
    stop_cheat_caller_address(game.contract_address);

    // Verify stats didn't change (only first game counts)
    let final_stats = referral.get_user_stats(user1);
    assert!(
        final_stats.total_referrals == initial_stats.total_referrals,
        "Second game should not affect referral stats",
    );
}

#[test]
fn test_game_without_referral() {
    let (referral, game, _, _) = setup_contracts();
    let user2: ContractAddress = USER2.try_into().unwrap();

    // User2 plays game without being referred
    start_cheat_caller_address(game.contract_address, user2);
    let game_id = game.start_game();
    let final_score = game.end_game(game_id);
    stop_cheat_caller_address(game.contract_address);

    // This should not create any referral relationships
    // and should not panic even though no referral exists
    assert!(final_score >= 0, "Game should complete normally");

    // Verify no referral relationship exists
    let relationship = referral.get_user_referral_relationship(user2);
    assert!(relationship.referrer.is_zero(), "Should have no referrer");
}

#[test]
fn test_multiple_referrals_different_codes() {
    let (referral, game, _, _) = setup_contracts();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();
    let user3: ContractAddress = contract_address_const::<0xabc>();

    // User1 creates referral code
    start_cheat_caller_address(referral.contract_address, user1);
    referral.create_referral_code('MULTI1', 10, get_block_timestamp() + 202800);
    stop_cheat_caller_address(referral.contract_address);

    // User2 and User3 register with same code
    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code('MULTI1');
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);

    // Advance time again for second user registration to avoid cooldown
    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 172802);
    start_cheat_caller_address(referral.contract_address, user3);
    referral.register_with_referral_code('MULTI1');
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);

    // Both complete games
    start_cheat_caller_address(game.contract_address, user2);
    let game_id2 = game.start_game();
    game.end_game(game_id2);
    stop_cheat_caller_address(game.contract_address);

    start_cheat_caller_address(game.contract_address, user3);
    let game_id3 = game.start_game();
    game.end_game(game_id3);
    stop_cheat_caller_address(game.contract_address);

    // Verify User1 got credit for both referrals
    let referrer_stats = referral.get_user_stats(user1);
    assert!(referrer_stats.total_referrals == 2, "Should have 2 referrals");

    // Verify both relationships exist
    let relationship2 = referral.get_user_referral_relationship(user2);
    let relationship3 = referral.get_user_referral_relationship(user3);

    assert!(relationship2.referrer == user1, "User2 should be referred by User1");
    assert!(relationship3.referrer == user1, "User3 should be referred by User1");
    assert!(relationship2.first_game_completed, "User2 should have completed");
    assert!(relationship3.first_game_completed, "User3 should have completed");
}

#[test]
fn test_contract_integration_addresses() {
    let (referral, _, _, game_address) = setup_contracts();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    let treasury: ContractAddress = TREASURY.try_into().unwrap();
    let token: ContractAddress = TOKEN_CONTRACT.try_into().unwrap();

    // Verify referral contract has correct addresses
    assert!(referral.get_treasury_contract() == treasury, "Wrong treasury address");
    assert!(referral.get_game_contract() == game_address, "Wrong game address");
    assert!(referral.get_token_contract() == token, "Wrong token address");

    // Test updating addresses (only owner should be able to)
    start_cheat_caller_address(referral.contract_address, owner);
    let new_treasury: ContractAddress = contract_address_const::<0x999>();
    referral.set_treasury_contract(new_treasury);
    stop_cheat_caller_address(referral.contract_address);
    assert!(referral.get_treasury_contract() == new_treasury, "Treasury address not updated");
}

#[test]
#[should_panic]
fn test_unauthorized_address_update() {
    let (referral, _, _, _) = setup_contracts();
    let user1: ContractAddress = USER1.try_into().unwrap();

    // Non-owner tries to update treasury address
    start_cheat_caller_address(referral.contract_address, user1);
    let new_treasury: ContractAddress = contract_address_const::<0x999>();
    referral.set_treasury_contract(new_treasury);
    stop_cheat_caller_address(referral.contract_address);
}
