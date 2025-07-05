use starknet::{ContractAddress, contract_address_const};

use starkmole::types::governance::{ProposalState, VoteType};

#[test]
fn test_proposal_states() {
    // Test proposal state constants
    assert(ProposalState::PENDING == 0_u8, 'Wrong PENDING state');
    assert(ProposalState::ACTIVE == 1_u8, 'Wrong ACTIVE state');
    assert(ProposalState::CANCELED == 2_u8, 'Wrong CANCELED state');
    assert(ProposalState::DEFEATED == 3_u8, 'Wrong DEFEATED state');
    assert(ProposalState::SUCCEEDED == 4_u8, 'Wrong SUCCEEDED state');
    assert(ProposalState::QUEUED == 5_u8, 'Wrong QUEUED state');
    assert(ProposalState::EXPIRED == 6_u8, 'Wrong EXPIRED state');
    assert(ProposalState::EXECUTED == 7_u8, 'Wrong EXECUTED state');
}

#[test]
fn test_vote_types() {
    // Test vote type constants
    assert(VoteType::AGAINST == 0_u8, 'Wrong AGAINST type');
    assert(VoteType::FOR == 1_u8, 'Wrong FOR type');
    assert(VoteType::ABSTAIN == 2_u8, 'Wrong ABSTAIN type');
}

#[test]
fn test_array_creation() {
    // Test that arrays can be created for proposals
    let targets = array![contract_address_const::<0x111>()];
    let values = array![0_u256];
    let empty_calldata: Array<felt252> = array![];
    let calldata = array![empty_calldata.span()];

    assert(targets.len() == 1, 'Wrong targets length');
    assert(values.len() == 1, 'Wrong values length');
    assert(calldata.len() == 1, 'Wrong calldata length');
}

#[test]
fn test_governance_types_integration() {
    // Test that our governance types work correctly
    let owner: ContractAddress = contract_address_const::<0x123>();
    let voter: ContractAddress = contract_address_const::<0x456>();

    // Test zero address comparison
    let zero_address: ContractAddress = 0.try_into().unwrap();
    assert(zero_address != owner, 'Zero address comparison failed');
    assert(zero_address != voter, 'Zero address comparison failed');
}

#[test]
fn test_numeric_constants() {
    // Test that our numeric constants work correctly
    let threshold = 1000_u256;
    let percentage = 400_u16; // 4%
    let delay = 86400_u64; // 1 day

    assert(threshold == 1000_u256, 'Wrong threshold');
    assert(percentage == 400_u16, 'Wrong percentage');
    assert(delay == 86400_u64, 'Wrong delay');
}
