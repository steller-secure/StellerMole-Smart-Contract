use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, spy_events, EventSpyAssertionsTrait,
    start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp
};

use starkmole::interfaces::challenge::{
    IChallengeSchedulerDispatcher, IChallengeSchedulerDispatcherTrait
};
use starkmole::challenge::challenge_scheduler::ChallengeScheduler::{
    Event as ChallengeEvents,
    ChallengeCreated,
    ParticipantJoined,
    ScoreSubmitted,
    ChallengeCancelled,
    ParticipantLeft,
    ContractUpdated
};

// Helper functions
fn owner() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn player1() -> ContractAddress {
    contract_address_const::<'player1'>()
}

fn player2() -> ContractAddress {
    contract_address_const::<'player2'>()
}

fn game_contract() -> ContractAddress {
    contract_address_const::<'game_contract'>()
}

fn leaderboard_contract() -> ContractAddress {
    contract_address_const::<'leaderboard_contract'>()
}

fn deploy_challenge_scheduler() -> (IChallengeSchedulerDispatcher, ContractAddress) {
    let contract = declare("ChallengeScheduler").unwrap().contract_class();
    
    let constructor_calldata = array![
        owner().into(),
        game_contract().into(),
        leaderboard_contract().into()
    ];

    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    let dispatcher = IChallengeSchedulerDispatcher { contract_address };

    (dispatcher, contract_address)
}

// Test constants
const DAILY_CHALLENGE: felt252 = 'daily';
const WEEKLY_CHALLENGE: felt252 = 'weekly';
const START_TIME: u64 = 1000000;
const END_TIME: u64 = 2000000;
const MAX_PARTICIPANTS: u32 = 100;

#[test]
fn test_constructor() {
    let (challenge_scheduler, _) = deploy_challenge_scheduler();
    
    assert_eq!(challenge_scheduler.get_owner(), owner());
    assert_eq!(challenge_scheduler.get_next_challenge_id(), 1);
}

#[test]
fn test_create_daily_challenge() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    start_cheat_caller_address(contract_address, owner());
    let mut spy = spy_events();

    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );

    assert_eq!(challenge_id, 1);
    assert_eq!(challenge_scheduler.get_next_challenge_id(), 2);

    let challenge = challenge_scheduler.get_challenge(challenge_id);
    assert_eq!(challenge.challenge_id, 1);
    assert_eq!(challenge.challenge_type, DAILY_CHALLENGE);
    assert_eq!(challenge.start_time, START_TIME);
    assert_eq!(challenge.end_time, END_TIME);
    assert_eq!(challenge.max_participants, MAX_PARTICIPANTS);
    assert_eq!(challenge.participant_count, 0);

    let expected_event = ChallengeEvents::ChallengeCreated(
        ChallengeCreated {
            challenge_id: 1,
            challenge_type: DAILY_CHALLENGE,
            start_time: START_TIME,
            end_time: END_TIME,
            max_participants: MAX_PARTICIPANTS,
            creator: owner(),
        }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
}

#[test]
fn test_create_weekly_challenge() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    start_cheat_caller_address(contract_address, owner());

    let challenge_id = challenge_scheduler.create_challenge(
        WEEKLY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );

    let challenge = challenge_scheduler.get_challenge(challenge_id);
    assert_eq!(challenge.challenge_type, WEEKLY_CHALLENGE);
}

#[test]
#[should_panic(expected: "Only owner can call this function")]
fn test_create_challenge_not_owner() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    start_cheat_caller_address(contract_address, player1());

    challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
}

#[test]
#[should_panic(expected: "Invalid challenge type")]
fn test_create_challenge_invalid_type() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    start_cheat_caller_address(contract_address, owner());

    challenge_scheduler.create_challenge(
        'invalid',
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
}

#[test]
#[should_panic(expected: "End time must be after start time")]
fn test_create_challenge_invalid_times() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    start_cheat_caller_address(contract_address, owner());

    challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        END_TIME,
        START_TIME, // End time before start time
        MAX_PARTICIPANTS
    );
}

#[test]
#[should_panic(expected: "Max participants must be greater than 0")]
fn test_create_challenge_zero_participants() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    start_cheat_caller_address(contract_address, owner());

    challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        0 // Zero max participants
    );
}

#[test]
fn test_join_challenge() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    // Create challenge as owner
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    stop_cheat_caller_address(contract_address);

    // Set time within challenge window
    start_cheat_block_timestamp(contract_address, START_TIME + 100);
    start_cheat_caller_address(contract_address, player1());
    let mut spy = spy_events();

    challenge_scheduler.join_challenge(challenge_id);

    // Verify participant joined
    assert!(challenge_scheduler.is_participant(challenge_id, player1()));
    
    let updated_challenge = challenge_scheduler.get_challenge(challenge_id);
    assert_eq!(updated_challenge.participant_count, 1);

    let expected_event = ChallengeEvents::ParticipantJoined(
        ParticipantJoined {
            challenge_id,
            participant: player1(),
            joined_at: START_TIME + 100,
        }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: "Challenge does not exist")]
fn test_join_nonexistent_challenge() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    start_cheat_caller_address(contract_address, player1());

    challenge_scheduler.join_challenge(999);
}

#[test]
#[should_panic(expected: "Challenge is not in valid time window")]
fn test_join_challenge_outside_time_window() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    // Create challenge as owner
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    stop_cheat_caller_address(contract_address);

    // Set time before challenge start
    start_cheat_block_timestamp(contract_address, START_TIME - 100);
    start_cheat_caller_address(contract_address, player1());

    challenge_scheduler.join_challenge(challenge_id);
}

#[test]
#[should_panic(expected: "Already participating in challenge")]
fn test_join_challenge_twice() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    // Create challenge as owner
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    stop_cheat_caller_address(contract_address);

    // Set time within challenge window
    start_cheat_block_timestamp(contract_address, START_TIME + 100);
    start_cheat_caller_address(contract_address, player1());

    challenge_scheduler.join_challenge(challenge_id);
    challenge_scheduler.join_challenge(challenge_id); // Should fail
}

#[test]
fn test_leave_challenge() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    // Create challenge and join
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    stop_cheat_caller_address(contract_address);

    start_cheat_block_timestamp(contract_address, START_TIME + 100);
    start_cheat_caller_address(contract_address, player1());
    challenge_scheduler.join_challenge(challenge_id);

    let mut spy = spy_events();
    challenge_scheduler.leave_challenge(challenge_id);

    // Verify participant left
    assert!(!challenge_scheduler.is_participant(challenge_id, player1()));
    
    let updated_challenge = challenge_scheduler.get_challenge(challenge_id);
    assert_eq!(updated_challenge.participant_count, 0);

    let expected_event = ChallengeEvents::ParticipantLeft(
        ParticipantLeft {
            challenge_id,
            participant: player1(),
        }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
}

#[test]
fn test_submit_score() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    // Create challenge and join
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    stop_cheat_caller_address(contract_address);

    start_cheat_block_timestamp(contract_address, START_TIME + 100);
    start_cheat_caller_address(contract_address, player1());
    challenge_scheduler.join_challenge(challenge_id);

    let mut spy = spy_events();
    let score = 1500_u128;
    challenge_scheduler.submit_score(challenge_id, score);

    // Verify score was submitted
    assert_eq!(challenge_scheduler.get_participant_score(challenge_id, player1()), score);

    let expected_event = ChallengeEvents::ScoreSubmitted(
        ScoreSubmitted {
            challenge_id,
            participant: player1(),
            score,
        }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: "Not participating in challenge")]
fn test_submit_score_not_participant() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    stop_cheat_caller_address(contract_address);

    start_cheat_block_timestamp(contract_address, START_TIME + 100);
    start_cheat_caller_address(contract_address, player1());

    challenge_scheduler.submit_score(challenge_id, 1500);
}

#[test]
fn test_cancel_challenge() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );

    let mut spy = spy_events();
    challenge_scheduler.cancel_challenge(challenge_id);

    let challenge = challenge_scheduler.get_challenge(challenge_id);
    assert!(!challenge.is_active);

    let expected_event = ChallengeEvents::ChallengeCancelled(
        ChallengeCancelled {
            challenge_id,
            cancelled_by: owner(),
        }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
}

#[test]
fn test_get_challenge_participants() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    // Create challenge
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    stop_cheat_caller_address(contract_address);

    // Join with multiple players
    start_cheat_block_timestamp(contract_address, START_TIME + 100);
    
    start_cheat_caller_address(contract_address, player1());
    challenge_scheduler.join_challenge(challenge_id);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, player2());
    challenge_scheduler.join_challenge(challenge_id);
    stop_cheat_caller_address(contract_address);

    let participants = challenge_scheduler.get_challenge_participants(challenge_id);
    assert_eq!(participants.len(), 2);
}

#[test]
fn test_is_challenge_active() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    start_cheat_caller_address(contract_address, owner());
    let challenge_id = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );

    // Before start time
    start_cheat_block_timestamp(contract_address, START_TIME - 100);
    assert!(!challenge_scheduler.is_challenge_active(challenge_id));

    // During challenge
    start_cheat_block_timestamp(contract_address, START_TIME + 100);
    assert!(challenge_scheduler.is_challenge_active(challenge_id));

    // After end time
    start_cheat_block_timestamp(contract_address, END_TIME + 100);
    assert!(!challenge_scheduler.is_challenge_active(challenge_id));
}

#[test]
fn test_get_active_challenges() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    start_cheat_caller_address(contract_address, owner());
    
    // Create multiple challenges
    let _challenge_id_1 = challenge_scheduler.create_challenge(
        DAILY_CHALLENGE,
        START_TIME,
        END_TIME,
        MAX_PARTICIPANTS
    );
    
    let _challenge_id_2 = challenge_scheduler.create_challenge(
        WEEKLY_CHALLENGE,
        START_TIME + 1000,
        END_TIME + 1000,
        MAX_PARTICIPANTS
    );

    // Set time when both are active
    start_cheat_block_timestamp(contract_address, START_TIME + 1500);
    
    let active_challenges = challenge_scheduler.get_active_challenges();
    assert_eq!(active_challenges.len(), 2);
}

#[test]
fn test_get_historical_challenges() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    
    start_cheat_caller_address(contract_address, owner());
    
    // Create multiple challenges
    challenge_scheduler.create_challenge(DAILY_CHALLENGE, START_TIME, END_TIME, MAX_PARTICIPANTS);
    challenge_scheduler.create_challenge(WEEKLY_CHALLENGE, START_TIME + 1000, END_TIME + 1000, MAX_PARTICIPANTS);
    challenge_scheduler.create_challenge(DAILY_CHALLENGE, START_TIME + 2000, END_TIME + 2000, MAX_PARTICIPANTS);

    let historical = challenge_scheduler.get_historical_challenges(0, 2);
    assert_eq!(historical.len(), 2);

    let all_historical = challenge_scheduler.get_historical_challenges(0, 10);
    assert_eq!(all_historical.len(), 3);
}

#[test]
fn test_set_game_contract() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    let new_game_contract = contract_address_const::<'new_game_contract'>();
    
    start_cheat_caller_address(contract_address, owner());
    let mut spy = spy_events();

    challenge_scheduler.set_game_contract(new_game_contract);

    let expected_event = ChallengeEvents::ContractUpdated(
        ContractUpdated {
            contract_type: 'game',
            new_address: new_game_contract,
        }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
}

#[test]
fn test_set_leaderboard_contract() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    let new_leaderboard_contract = contract_address_const::<'new_leaderboard_contract'>();
    
    start_cheat_caller_address(contract_address, owner());
    let mut spy = spy_events();

    challenge_scheduler.set_leaderboard_contract(new_leaderboard_contract);

    let expected_event = ChallengeEvents::ContractUpdated(
        ContractUpdated {
            contract_type: 'leaderboard',
            new_address: new_leaderboard_contract,
        }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: "Only owner can call this function")]
fn test_set_game_contract_not_owner() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    let new_game_contract = contract_address_const::<'new_game_contract'>();
    
    start_cheat_caller_address(contract_address, player1());
    challenge_scheduler.set_game_contract(new_game_contract);
}

#[test]
fn test_get_current_time() {
    let (challenge_scheduler, contract_address) = deploy_challenge_scheduler();
    let test_time = 12345_u64;
    
    start_cheat_block_timestamp(contract_address, test_time);
    assert_eq!(challenge_scheduler.get_current_time(), test_time);
} 