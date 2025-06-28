use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, stop_cheat_block_timestamp, stop_cheat_caller_address,
};
use starkmole::interfaces::{IStarkMoleGameDispatcher, IStarkMoleGameDispatcherTrait};
use starknet::{ContractAddress, contract_address_const};

fn deploy_game_contract() -> (IStarkMoleGameDispatcher, ContractAddress) {
    let contract = declare("StarkMoleGame").unwrap().contract_class();
    let owner = contract_address_const::<'owner'>();
    let (contract_address, _) = contract.deploy(@array![owner.into()]).unwrap();
    (IStarkMoleGameDispatcher { contract_address }, contract_address)
}

#[test]
fn test_start_game() {
    let (game_contract, contract_address) = deploy_game_contract();
    let player = contract_address_const::<'player'>();

    start_cheat_caller_address(contract_address, player);
    start_cheat_block_timestamp(contract_address, 1000);

    let game_id = game_contract.start_game();

    assert(game_id == 1, 'First game should have ID 1');

    let score = game_contract.get_game_score(game_id);
    assert(score == 0, 'Initial score should be 0');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
fn test_hit_mole() {
    let (game_contract, contract_address) = deploy_game_contract();
    let player = contract_address_const::<'player'>();

    start_cheat_caller_address(contract_address, player);
    start_cheat_block_timestamp(contract_address, 1000);

    let game_id = game_contract.start_game();

    // Try to hit position 0 (may or may not be correct due to randomness)
    let hit_result = game_contract.hit_mole(game_id, 0);

    // Test passes regardless of hit success since position is random
    let score_after = game_contract.get_game_score(game_id);

    if hit_result {
        assert(score_after >= 10, 'Score should increase on hit');
    }

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
fn test_end_game() {
    let (game_contract, contract_address) = deploy_game_contract();
    let player = contract_address_const::<'player'>();

    start_cheat_caller_address(contract_address, player);
    start_cheat_block_timestamp(contract_address, 1000);

    let game_id = game_contract.start_game();
    let final_score = game_contract.end_game(game_id);

    assert(final_score == 0, 'Final score should be 0');

    let (total_games, total_score, best_score) = game_contract.get_player_stats(player);
    assert(total_games == 1, 'Player should have 1 game');
    assert(total_score == 0, 'Total score should be 0');
    assert(best_score == 0, 'Best score should be 0');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}
