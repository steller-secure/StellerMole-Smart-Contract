use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starkmole::interfaces::{IRewardsDispatcher, IRewardsDispatcherTrait};
use starknet::{ContractAddress, contract_address_const};

fn deploy_rewards_contract() -> (IRewardsDispatcher, ContractAddress) {
    let contract = declare("Rewards").unwrap().contract_class();
    let owner = contract_address_const::<'owner'>();
    let leaderboard_contract = contract_address_const::<'leaderboard_contract'>();
    let (contract_address, _) = contract
        .deploy(@array![owner.into(), leaderboard_contract.into()])
        .unwrap();
    (IRewardsDispatcher { contract_address }, contract_address)
}

#[test]
fn test_set_reward_multiplier() {
    let (rewards_contract, contract_address) = deploy_rewards_contract();
    let owner = contract_address_const::<'owner'>();

    start_cheat_caller_address(contract_address, owner);

    rewards_contract.set_reward_multiplier(2000000000000000000); // 2.0

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_distribute_season_rewards() {
    let (rewards_contract, contract_address) = deploy_rewards_contract();
    let owner = contract_address_const::<'owner'>();

    start_cheat_caller_address(contract_address, owner);

    rewards_contract.distribute_season_rewards(1);

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_get_pending_rewards() {
    let (rewards_contract, _) = deploy_rewards_contract();
    let player = contract_address_const::<'player'>();

    let pending = rewards_contract.get_pending_rewards(player);
    assert(pending == 0, 'Initial pending rewards should be 0');
}
