use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use starkmole::interfaces::analytics::{IAnalyticsDispatcher, IAnalyticsDispatcherTrait};

fn deploy_analytics(owner: ContractAddress, game: ContractAddress, referral: ContractAddress) -> (IAnalyticsDispatcher, ContractAddress) {
    let class = declare("Analytics").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![owner.into(), game.into(), referral.into()]).unwrap();
    (IAnalyticsDispatcher { contract_address: addr }, addr)
}

#[test]
fn test_dau_and_sessions_and_achievements_and_referrals() {
    let owner = contract_address_const::<'owner'>();
    let game = contract_address_const::<'game'>();
    let referral = contract_address_const::<'referral'>();
    let player_a = contract_address_const::<'player_a'>();
    let player_b = contract_address_const::<'player_b'>();

    let (analytics, analytics_addr) = deploy_analytics(owner, game, referral);

    // Game contract logs sessions and achievements
    start_cheat_caller_address(analytics_addr, game);
    analytics.log_session_start(player_a, 20000);
    analytics.log_session_start(player_b, 20000);
    analytics.log_session_start(player_a, 20000);
    analytics.log_achievement(player_a, 'ACH_FIRST_BLOOD', 20000);
    stop_cheat_caller_address(analytics_addr);

    // Referral contract logs referral for player_a
    start_cheat_caller_address(analytics_addr, referral);
    analytics.log_referral(player_a, player_b, 20000);
    stop_cheat_caller_address(analytics_addr);

    // Player-scoped reads
    let a_sessions = analytics.get_player_sessions(player_a, 20000);
    let b_sessions = analytics.get_player_sessions(player_b, 20000);
    let a_ach = analytics.get_player_achievements(player_a, 20000);
    let a_refs = analytics.get_player_referrals(player_a, 20000);
    assert(a_sessions == 2, 'player_a sessions');
    assert(b_sessions == 1, 'player_b sessions');
    assert(a_ach == 1, 'player_a achievements');
    assert(a_refs == 1, 'player_a referrals');

    // Aggregates
    let dau = analytics.get_dau(20000);
    let day_sessions = analytics.get_day_sessions(20000);
    let day_ach = analytics.get_day_achievements(20000);
    let day_refs = analytics.get_day_referrals(20000);
    assert(dau == 2, 'DAU should count unique players (a,b)');
    assert(day_sessions == 3, 'total sessions for the day');
    assert(day_ach == 1, 'total achievements for the day');
    assert(day_refs == 1, 'total referrals for the day');
}

#[test]
fn test_week_aggregation() {
    let owner = contract_address_const::<'owner'>();
    let game = contract_address_const::<'game'>();
    let referral = contract_address_const::<'referral'>();
    let player = contract_address_const::<'player'>();

    let (analytics, analytics_addr) = deploy_analytics(owner, game, referral);

    start_cheat_caller_address(analytics_addr, game);
    // Log sessions across 7 days starting at 30000
    let mut i: u64 = 0;
    while i < 7 {
        let day = 30000 + i;
        analytics.log_session_start(player, day);
        analytics.log_session_start(player, day);
        i += 1;
    };
    stop_cheat_caller_address(analytics_addr);

    let week_sessions = analytics.get_week_sessions(30000);
    let week_dau = analytics.get_week_dau(30000);

    // 2 sessions per day * 7 days = 14
    assert(week_sessions == 14_u64, 'week sessions total');
    // DAU is 1 per day over 7 days
    assert(week_dau == 7_u64, 'week dau total');
}


