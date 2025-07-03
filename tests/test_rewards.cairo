use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp,
};
use starkmole::interfaces::leaderboard::{ILeaderboardDispatcher, ILeaderboardDispatcherTrait};
use starkmole::interfaces::rewards::{IRewardsDispatcher, IRewardsDispatcherTrait};
use starkmole::types::RewardTier;
use starknet::{ContractAddress, contract_address_const};

// Helper function to deploy leaderboard contract
fn deploy_leaderboard_contract() -> (ILeaderboardDispatcher, ContractAddress) {
    let contract = declare("Leaderboard").unwrap().contract_class();
    let owner = contract_address_const::<'leaderboard_owner'>();
    let game_contract = contract_address_const::<'game_contract'>();
    let (contract_address, _) = contract
        .deploy(@array![owner.into(), game_contract.into()])
        .unwrap();
    (ILeaderboardDispatcher { contract_address }, contract_address)
}

// Helper function to deploy rewards contract
fn deploy_rewards_contract() -> (IRewardsDispatcher, ContractAddress, ILeaderboardDispatcher) {
    let (leaderboard_dispatcher, leaderboard_address) = deploy_leaderboard_contract();
    
    let contract = declare("Rewards").unwrap().contract_class();
    let owner = contract_address_const::<'rewards_owner'>();
    let token_address = contract_address_const::<'mock_token'>(); // Mock token address
    let (contract_address, _) = contract
        .deploy(@array![owner.into(), leaderboard_address.into(), token_address.into()])
        .unwrap();
    
    let rewards_dispatcher = IRewardsDispatcher { contract_address };
    
    (rewards_dispatcher, contract_address, leaderboard_dispatcher)
}

#[test]
fn test_default_reward_tiers() {
    let (rewards_contract, _, _) = deploy_rewards_contract();
    
    let tiers = rewards_contract.get_reward_tiers();
    assert(tiers.len() == 5, 'Should have 5 default tiers');
    
    // Check first tier (WINNER)
    let winner_tier = *tiers.at(0);
    assert(winner_tier.tier_name == 'WINNER', 'First tier should be WINNER');
    assert(winner_tier.min_rank == 1, 'Winner min rank should be 1');
    assert(winner_tier.max_rank == 1, 'Winner max rank should be 1');
    assert(winner_tier.percentage_of_pool == 3000, 'Winner should get 30%');
}

#[test]
fn test_create_challenge_cycle() {
    let (rewards_contract, contract_address, _) = deploy_rewards_contract();
    let owner = contract_address_const::<'rewards_owner'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    let start_time = 1000_u64;
    let end_time = 2000_u64;
    let total_pool = 10000000000000000000000_u256; // 10k tokens
    
    let cycle_id = rewards_contract.create_challenge_cycle(start_time, end_time, total_pool);
    
    assert(cycle_id == 1, 'First cycle should have ID 1');
    
    let cycle = rewards_contract.get_challenge_cycle(cycle_id);
    assert(cycle.cycle_id == 1, 'Cycle ID should match');
    assert(cycle.start_time == start_time, 'Start time should match');
    assert(cycle.end_time == end_time, 'End time should match');
    assert(cycle.total_pool == total_pool, 'Pool should match');
    assert(!cycle.is_finalized, 'Should not be finalized');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Only owner',))]
fn test_create_challenge_cycle_unauthorized() {
    let (rewards_contract, contract_address, _) = deploy_rewards_contract();
    let unauthorized = contract_address_const::<'unauthorized'>();
    
    start_cheat_caller_address(contract_address, unauthorized);
    rewards_contract.create_challenge_cycle(1000, 2000, 10000);
}

#[test]
fn test_finalize_challenge_cycle() {
    let (rewards_contract, rewards_address, leaderboard_contract) = deploy_rewards_contract();
    let owner = contract_address_const::<'rewards_owner'>();
    let game_contract = contract_address_const::<'game_contract'>();
    
    // Create a cycle
    start_cheat_caller_address(rewards_address, owner);
    let cycle_id = rewards_contract.create_challenge_cycle(1000, 2000, 10000000000000000000000_u256);
    stop_cheat_caller_address(rewards_address);
    
    // Add some players to leaderboard
    let leaderboard_address = leaderboard_contract.contract_address;
    start_cheat_caller_address(leaderboard_address, game_contract);
    let player1 = contract_address_const::<'player1'>();
    let player2 = contract_address_const::<'player2'>();
    leaderboard_contract.submit_score(player1, 100);
    leaderboard_contract.submit_score(player2, 80);
    stop_cheat_caller_address(leaderboard_address);
    
    // Fast forward to after cycle end time
    start_cheat_block_timestamp(rewards_address, 3000);
    
    // Finalize cycle
    start_cheat_caller_address(rewards_address, owner);
    rewards_contract.finalize_challenge_cycle(cycle_id);
    
    let cycle = rewards_contract.get_challenge_cycle(cycle_id);
    assert(cycle.is_finalized, 'Cycle should be finalized');
    assert(cycle.participant_count == 2, 'Should have 2 participants');
    
    stop_cheat_caller_address(rewards_address);
    stop_cheat_block_timestamp(rewards_address);
}

#[test]
fn test_calculate_tier_rewards() {
    let (rewards_contract, rewards_address, leaderboard_contract) = deploy_rewards_contract();
    let owner = contract_address_const::<'rewards_owner'>();
    let game_contract = contract_address_const::<'game_contract'>();
    
    // Create and finalize a cycle
    start_cheat_caller_address(rewards_address, owner);
    let total_pool = 10000000000000000000000_u256; // 10k tokens
    let cycle_id = rewards_contract.create_challenge_cycle(1000, 2000, total_pool);
    stop_cheat_caller_address(rewards_address);
    
    // Add players to leaderboard
    let leaderboard_address = leaderboard_contract.contract_address;
    start_cheat_caller_address(leaderboard_address, game_contract);
    let winner = contract_address_const::<'winner'>();
    let runner_up = contract_address_const::<'runner_up'>();
    let third_place = contract_address_const::<'third_place'>();
    
    leaderboard_contract.submit_score(winner, 100);
    leaderboard_contract.submit_score(runner_up, 80);
    leaderboard_contract.submit_score(third_place, 60);
    stop_cheat_caller_address(leaderboard_address);
    
    // Finalize cycle
    start_cheat_block_timestamp(rewards_address, 3000);
    start_cheat_caller_address(rewards_address, owner);
    rewards_contract.finalize_challenge_cycle(cycle_id);
    stop_cheat_caller_address(rewards_address);
    
    // Calculate rewards
    let winner_reward = rewards_contract.calculate_tier_rewards(cycle_id, winner);
    let runner_up_reward = rewards_contract.calculate_tier_rewards(cycle_id, runner_up);
    let third_reward = rewards_contract.calculate_tier_rewards(cycle_id, third_place);
    
    // Winner should get 30% of pool
    let expected_winner = (total_pool * 3000) / 10000;
    assert(winner_reward == expected_winner, 'Winner reward incorrect');
    
    // Runner up should get 15% of pool  
    let expected_runner_up = (total_pool * 1500) / 10000;
    assert(runner_up_reward == expected_runner_up, 'Runner up reward incorrect');
    
    // Third place should get 5% of pool
    let expected_third = (total_pool * 500) / 10000;
    assert(third_reward == expected_third, 'Third place reward incorrect');
    
    stop_cheat_block_timestamp(rewards_address);
}

#[test]
fn test_get_claimable_reward() {
    let (rewards_contract, rewards_address, leaderboard_contract) = deploy_rewards_contract();
    let owner = contract_address_const::<'rewards_owner'>();
    let game_contract = contract_address_const::<'game_contract'>();
    
    // Create and setup cycle
    start_cheat_caller_address(rewards_address, owner);
    let total_pool = 10000000000000000000000_u256;
    let cycle_id = rewards_contract.create_challenge_cycle(1000, 2000, total_pool);
    stop_cheat_caller_address(rewards_address);
    
    // Add winner to leaderboard
    let leaderboard_address = leaderboard_contract.contract_address;
    start_cheat_caller_address(leaderboard_address, game_contract);
    let winner = contract_address_const::<'winner'>();
    leaderboard_contract.submit_score(winner, 100);
    stop_cheat_caller_address(leaderboard_address);
    
    // Before finalization, should be 0
    let claimable_before = rewards_contract.get_claimable_reward(winner, cycle_id);
    assert(claimable_before == 0, 'Should be 0 before finalization');
    
    // Finalize cycle
    start_cheat_block_timestamp(rewards_address, 3000);
    start_cheat_caller_address(rewards_address, owner);
    rewards_contract.finalize_challenge_cycle(cycle_id);
    stop_cheat_caller_address(rewards_address);
    
    // After finalization, should show claimable amount
    let claimable_after = rewards_contract.get_claimable_reward(winner, cycle_id);
    let expected_winner = (total_pool * 3000) / 10000;
    assert(claimable_after == expected_winner, 'Should show winner reward');
    
    stop_cheat_block_timestamp(rewards_address);
}

#[test]
fn test_set_custom_reward_tiers() {
    let (rewards_contract, rewards_address, _) = deploy_rewards_contract();
    let owner = contract_address_const::<'rewards_owner'>();
    
    start_cheat_caller_address(rewards_address, owner);
    
    let mut custom_tiers = ArrayTrait::new();
    custom_tiers.append(RewardTier {
        tier_name: 'GOLD',
        min_rank: 1,
        max_rank: 1,
        reward_amount: 0,
        percentage_of_pool: 5000, // 50%
    });
    custom_tiers.append(RewardTier {
        tier_name: 'SILVER',
        min_rank: 2,
        max_rank: 5,
        reward_amount: 0,
        percentage_of_pool: 1250, // 12.5% each
    });
    
    rewards_contract.set_reward_tiers(custom_tiers);
    
    let updated_tiers = rewards_contract.get_reward_tiers();
    assert(updated_tiers.len() == 2, 'Should have 2 custom tiers');
    
    let gold_tier = *updated_tiers.at(0);
    assert(gold_tier.tier_name == 'GOLD', 'First tier should be GOLD');
    assert(gold_tier.percentage_of_pool == 5000, 'Gold should get 50%');
    
    stop_cheat_caller_address(rewards_address);
}

#[test]
fn test_no_reward_for_non_participant() {
    let (rewards_contract, rewards_address, _) = deploy_rewards_contract();
    let owner = contract_address_const::<'rewards_owner'>();
    
    // Create and finalize empty cycle
    start_cheat_caller_address(rewards_address, owner);
    let cycle_id = rewards_contract.create_challenge_cycle(1000, 2000, 10000000000000000000000_u256);
    stop_cheat_caller_address(rewards_address);
    
    start_cheat_block_timestamp(rewards_address, 3000);
    start_cheat_caller_address(rewards_address, owner);
    rewards_contract.finalize_challenge_cycle(cycle_id);
    stop_cheat_caller_address(rewards_address);
    
    // Non-participant should have 0 claimable reward
    let non_participant = contract_address_const::<'non_participant'>();
    let claimable = rewards_contract.get_claimable_reward(non_participant, cycle_id);
    assert(claimable == 0, 'Non-participant should get 0');
    
    stop_cheat_block_timestamp(rewards_address);
}

#[test]
fn test_cycle_statistics() {
    let (rewards_contract, rewards_address, leaderboard_contract) = deploy_rewards_contract();
    let owner = contract_address_const::<'rewards_owner'>();
    let game_contract = contract_address_const::<'game_contract'>();
    
    // Create cycle and add participants
    start_cheat_caller_address(rewards_address, owner);
    let total_pool = 10000000000000000000000_u256;
    let cycle_id = rewards_contract.create_challenge_cycle(1000, 2000, total_pool);
    stop_cheat_caller_address(rewards_address);
    
    let leaderboard_address = leaderboard_contract.contract_address;
    start_cheat_caller_address(leaderboard_address, game_contract);
    let player1 = contract_address_const::<'player1'>();
    let player2 = contract_address_const::<'player2'>();
    leaderboard_contract.submit_score(player1, 100);
    leaderboard_contract.submit_score(player2, 80);
    stop_cheat_caller_address(leaderboard_address);
    
    // Finalize cycle
    start_cheat_block_timestamp(rewards_address, 3000);
    start_cheat_caller_address(rewards_address, owner);
    rewards_contract.finalize_challenge_cycle(cycle_id);
    stop_cheat_caller_address(rewards_address);
    
    // Check statistics
    let (participants, pool, claims) = rewards_contract.get_cycle_statistics(cycle_id);
    assert(participants == 2, 'Should have 2 participants');
    assert(pool == total_pool, 'Pool should match');
    assert(claims == 0, 'Should have 0 claims initially');
    
    stop_cheat_block_timestamp(rewards_address);
}
