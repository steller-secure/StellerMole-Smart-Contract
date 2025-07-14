use starknet::{ContractAddress, get_block_timestamp};
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp};

use starkmole::interfaces::referral::{IReferralDispatcher, IReferralDispatcherTrait};
use starkmole::types::{ ReferralRewardConfig,};

// Test constants
const OWNER: felt252 = 0x123;
const USER1: felt252 = 0x456;
const USER2: felt252 = 0x789;
const USER3: felt252 = 0xabc;
const TREASURY: felt252 = 0xdef;
const GAME_CONTRACT: felt252 = 0x111;
const TOKEN_CONTRACT: felt252 = 0x222;

fn setup_referral_contract() -> IReferralDispatcher {
    let owner: ContractAddress = OWNER.try_into().unwrap();
    let treasury: ContractAddress = TREASURY.try_into().unwrap();
    let game: ContractAddress = GAME_CONTRACT.try_into().unwrap();
    let token: ContractAddress = TOKEN_CONTRACT.try_into().unwrap();

    let contract = declare("Referral").unwrap().contract_class();
    let constructor_calldata = array![owner.into(), game.into(), treasury.into(), token.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    
    let referral = IReferralDispatcher { contract_address };
    
    // Set up reward configuration
    start_cheat_caller_address(referral.contract_address, owner);
    let config = ReferralRewardConfig {
        referrer_reward: 100,
        referee_reward: 50,
        min_game_score: 1000,
        reward_delay: 0,
        is_active: true,
    };
    referral.set_reward_config(config);
    stop_cheat_caller_address(referral.contract_address);
    
    referral
}

#[test]
fn test_contract_deployment() {
    let referral = setup_referral_contract();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    
    // Test that contract was deployed with correct owner
    assert!(referral.get_owner() == owner, "Wrong owner");
    assert!(!referral.is_paused(), "Should not be paused initially");
}

#[test]
fn test_create_referral_code() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, user1);
    
    // Create a referral code
    let code = 'TEST123';
    let usage_limit = 10;
    let expiry_time = get_block_timestamp() + 86400; // 1 day
    
    referral.create_referral_code(code, usage_limit, expiry_time);
    stop_cheat_caller_address(referral.contract_address);

    // Verify code was created
    assert!(referral.is_code_valid(code), "Code should be valid");
    
    let retrieved_code = referral.get_referral_code(code);
    assert!(retrieved_code.referrer == user1, "Wrong referrer");
    assert!(retrieved_code.max_uses == usage_limit, "Wrong usage limit");
    assert!(retrieved_code.expiry_time == expiry_time, "Wrong expiry time");
    assert!(retrieved_code.is_active, "Code should be active");
}

#[test]
#[should_panic]
fn test_create_duplicate_code() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, user1);
    
    let code = 'DUPLICATE';
    let usage_limit = 5;
    let expiry_time = get_block_timestamp() + 86400;
    
    // Create first code
    referral.create_referral_code(code, usage_limit, expiry_time);
    
    // Try to create duplicate - should panic
    referral.create_referral_code(code, usage_limit, expiry_time);
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
fn test_register_with_referral_code() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();
    
    // User1 creates a referral code
    start_cheat_caller_address(referral.contract_address, user1);
    let code = 'REFER123';
    referral.create_referral_code(code, 10, get_block_timestamp() + 172800);
    stop_cheat_caller_address(referral.contract_address);
    
    // User2 registers with the code (advance time to bypass cooldown)
    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);
    
    // Verify relationship was created
    let relationship = referral.get_user_referral_relationship(user2);
    assert!(relationship.referrer == user1, "Wrong referrer in relationship");
    assert!(relationship.referee == user2, "Wrong referee in relationship");
    assert!(!relationship.first_game_completed, "Should not be completed yet");
    
    // Verify code usage was incremented
    let updated_code = referral.get_referral_code(code);
    assert!(updated_code.current_uses == 1, "Usage count should be 1");
}

#[test]
#[should_panic]
fn test_register_with_invalid_code() {
    let referral = setup_referral_contract();
    let user2: ContractAddress = USER2.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, user2);
    
    // Try to register with non-existent code
    referral.register_with_referral_code('INVALID');
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
#[should_panic]
fn test_register_twice() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();
    
    // User1 creates a referral code
    start_cheat_caller_address(referral.contract_address, user1);
    let code = 'REFER123';
    referral.create_referral_code(code, 10, get_block_timestamp() + 172800);
    stop_cheat_caller_address(referral.contract_address);
    
    // User2 registers with the code
    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code(code);
    
    // Try to register again - should panic
    referral.register_with_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);
}

#[test]
#[should_panic]
fn test_self_referral() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, user1);
    
    // User1 creates a referral code
    let code = 'SELFREF';
    referral.create_referral_code(code, 10, get_block_timestamp() + 86400);

    // Try to register with own code - should panic
    referral.register_with_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
fn test_deactivate_referral_code() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, user1);
    
    // Create and then deactivate a code
    let code = 'DEACTIVATE';
    referral.create_referral_code(code, 10, get_block_timestamp() + 86400);
    
    assert!(referral.is_code_valid(code), "Code should be valid initially");
    
    referral.deactivate_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
    assert!(!referral.is_code_valid(code), "Code should be invalid after deactivation");
    
    let deactivated_code = referral.get_referral_code(code);
    assert!(!deactivated_code.is_active, "Code should not be active");
}

#[test]
#[should_panic]
fn test_deactivate_code_wrong_owner() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();
    
    // User1 creates a code
    start_cheat_caller_address(referral.contract_address, user1);
    let code = 'WRONGOWNER';
    referral.create_referral_code(code, 10, get_block_timestamp() + 86400);
    stop_cheat_caller_address(referral.contract_address);

    // User2 tries to deactivate it - should panic
    start_cheat_caller_address(referral.contract_address, user2);
    referral.deactivate_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
fn test_ban_and_unban_user() {
    let referral = setup_referral_contract();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, owner);
    
    // Ban user
    referral.ban_user(user1);
    assert!(referral.is_user_banned(user1), "User should be banned");
    
    // Unban user
    referral.unban_user(user1);
    assert!(!referral.is_user_banned(user1), "User should not be banned");
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
#[should_panic]
fn test_banned_user_cannot_create_code() {
    let referral = setup_referral_contract();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    // Ban user
    start_cheat_caller_address(referral.contract_address, owner);
    referral.ban_user(user1);
    stop_cheat_caller_address(referral.contract_address);
    
    // Try to create code as banned user
    start_cheat_caller_address(referral.contract_address, user1);
    referral.create_referral_code('BANNED', 10, get_block_timestamp() + 86400);
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
fn test_pause_and_unpause_system() {
    let referral = setup_referral_contract();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, owner);
    
    // Pause system
    referral.pause_system();
    assert!(referral.is_paused(), "System should be paused");
    
    // Unpause system
    referral.unpause_system();
    assert!(!referral.is_paused(), "System should not be paused");
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
#[should_panic]
fn test_paused_system_blocks_operations() {
    let referral = setup_referral_contract();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    // Pause system
    start_cheat_caller_address(referral.contract_address, owner);
    referral.pause_system();
    stop_cheat_caller_address(referral.contract_address);
    
    // Try to create code while paused
    start_cheat_caller_address(referral.contract_address, user1);
    referral.create_referral_code('PAUSED', 10, get_block_timestamp() + 86400);
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
fn test_get_user_referral_codes() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, user1);
    
    // Create multiple codes
    referral.create_referral_code('CODE1', 5, get_block_timestamp() + 86400);
    referral.create_referral_code('CODE2', 10, get_block_timestamp() + 86400);
    referral.create_referral_code('CODE3', 15, get_block_timestamp() + 86400);

    // Get user's codes
    let codes = referral.get_user_referral_codes(user1);
    assert!(codes.len() == 3, "Should have 3 codes");
    
    // Verify codes are in the array
    let mut found_code1 = false;
    let mut found_code2 = false;
    let mut found_code3 = false;
    
    let mut i = 0;
    while i < codes.len() {
        if *codes.at(i) == 'CODE1' {
            found_code1 = true;
        } else if *codes.at(i) == 'CODE2' {
            found_code2 = true;
        } else if *codes.at(i) == 'CODE3' {
            found_code3 = true;
        }
        i += 1;
    };
    
    assert!(found_code1, "CODE1 not found");
    assert!(found_code2, "CODE2 not found");
    assert!(found_code3, "CODE3 not found");
}

#[test]
fn test_get_user_referrals() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();
    let user3: ContractAddress = USER3.try_into().unwrap();
    
    // User1 creates a code
    start_cheat_caller_address(referral.contract_address, user1);
    let code = 'MULTIREF';
    referral.create_referral_code(code, 10, get_block_timestamp() + 202800);
    stop_cheat_caller_address(referral.contract_address);
    
    // Multiple users register with the code
    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);


    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 172802);
    start_cheat_caller_address(referral.contract_address, user3);
    referral.register_with_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);
    
    // Get user1's referrals
    let referrals = referral.get_user_referrals(user1);
    assert!(referrals.len() == 2, "Should have 2 referrals");
    
    // Verify both users are in the referrals
    let mut found_user2 = false;
    let mut found_user3 = false;
    
    let mut i = 0;
    while i < referrals.len() {
        if *referrals.at(i) == user2 {
            found_user2 = true;
        } else if *referrals.at(i) == user3 {
            found_user3 = true;
        }
        i += 1;
    };
    
    assert!(found_user2, "User2 not found in referrals");
    assert!(found_user3, "User3 not found in referrals");
}

#[test]
fn test_expired_code_validation() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, user1);
    
    // Create code that expires in 1 second
    let code = 'EXPIRE';
    let expiry_time = get_block_timestamp() + 1;
    referral.create_referral_code(code, 10, expiry_time);
    stop_cheat_caller_address(referral.contract_address);

    // Initially valid
    assert!(referral.is_code_valid(code), "Code should be valid initially");
    
    // Advance time past expiry
    start_cheat_block_timestamp(referral.contract_address, expiry_time + 1);
    
    // Should now be invalid
    assert!(!referral.is_code_valid(code), "Code should be expired");
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
fn test_usage_limit_reached() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();
    let _: ContractAddress = USER3.try_into().unwrap();
    
    // Create code with usage limit of 1
    start_cheat_caller_address(referral.contract_address, user1);
    let code = 'LIMIT1';
    referral.create_referral_code(code, 1, get_block_timestamp() + 172800);
    stop_cheat_caller_address(referral.contract_address);
    
    // First registration should work
    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code(code);
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);
    
    // Code should now be invalid due to usage limit
    assert!(!referral.is_code_valid(code), "Code should be invalid after reaching limit");
}

#[test]
fn test_reward_configuration() {
    let referral = setup_referral_contract();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    
    start_cheat_caller_address(referral.contract_address, owner);
    
    // Update reward config
    let new_config = ReferralRewardConfig {
        referrer_reward: 200,
        referee_reward: 100,
        min_game_score: 2000,
        reward_delay: 3600, // 1 hour
        is_active: true,
    };
    
    referral.set_reward_config(new_config);
    let retrieved_config = referral.get_reward_config();
    
    assert!(retrieved_config.referrer_reward == 200, "Wrong referrer reward");
    assert!(retrieved_config.referee_reward == 100, "Wrong referee reward");
    assert!(retrieved_config.min_game_score == 2000, "Wrong minimum score");
    assert!(retrieved_config.reward_delay == 3600, "Wrong reward delay");
    stop_cheat_caller_address(referral.contract_address);
}

#[test]
fn test_system_totals() {
    let referral = setup_referral_contract();
    let user1: ContractAddress = USER1.try_into().unwrap();
    let user2: ContractAddress = USER2.try_into().unwrap();
    
    // Initially should be zero
    let (total_codes, total_relationships, total_rewards) = referral.get_system_totals();
    assert!(total_codes == 0, "Initial codes should be 0");
    assert!(total_relationships == 0, "Initial relationships should be 0");
    assert!(total_rewards == 0, "Initial rewards should be 0");
    
    // Create code and relationship
    start_cheat_caller_address(referral.contract_address, user1);
    referral.create_referral_code('TOTALS', 10, get_block_timestamp() + 172800);
    stop_cheat_caller_address(referral.contract_address);
    
    start_cheat_block_timestamp(referral.contract_address, get_block_timestamp() + 86401);
    start_cheat_caller_address(referral.contract_address, user2);
    referral.register_with_referral_code('TOTALS');
    stop_cheat_caller_address(referral.contract_address);
    stop_cheat_block_timestamp(referral.contract_address);
    // Check updated totals
    let (updated_codes, updated_relationships, _) = referral.get_system_totals();
    assert!(updated_codes == 1, "Should have 1 code");
    assert!(updated_relationships == 1, "Should have 1 relationship");
} 