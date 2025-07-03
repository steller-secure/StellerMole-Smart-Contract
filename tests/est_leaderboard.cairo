use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starkmole::interfaces::leaderboard::{ILeaderboardDispatcher, ILeaderboardDispatcherTrait};
use starknet::{ContractAddress, contract_address_const};

fn deploy_leaderboard_contract() -> (ILeaderboardDispatcher, ContractAddress) {
    let contract = declare("Leaderboard").unwrap().contract_class();
    let owner = contract_address_const::<'owner'>();
    let game_contract = contract_address_const::<'game_contract'>();
    let (contract_address, _) = contract
        .deploy(@array![owner.into(), game_contract.into()])
        .unwrap();
    (ILeaderboardDispatcher { contract_address }, contract_address)
}

#[test]
fn test_submit_score() {
    let (leaderboard_contract, contract_address) = deploy_leaderboard_contract();
    let game_contract = contract_address_const::<'game_contract'>();
    let player = contract_address_const::<'player'>();

    start_cheat_caller_address(contract_address, game_contract);

    leaderboard_contract.submit_score(player, 1000);

    let rank = leaderboard_contract.get_player_rank(player);
    assert(rank > 0, 'Player should have a rank');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_get_top_players() {
    let (leaderboard_contract, contract_address) = deploy_leaderboard_contract();
    let game_contract = contract_address_const::<'game_contract'>();
    let player1 = contract_address_const::<'player1'>();
    let player2 = contract_address_const::<'player2'>();

    start_cheat_caller_address(contract_address, game_contract);

    leaderboard_contract.submit_score(player1, 1000);
    leaderboard_contract.submit_score(player2, 1500);

    let top_players = leaderboard_contract.get_top_players(5);
    assert(top_players.len() <= 5, 'Should return max 5 players');

    stop_cheat_caller_address(contract_address);
}
