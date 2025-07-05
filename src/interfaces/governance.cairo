use starknet::ContractAddress;

// Governance interface for DAO operations
#[starknet::interface]
pub trait IGovernance<TContractState> {
    // Proposal management
    fn propose(
        ref self: TContractState,
        targets: Array<ContractAddress>,
        values: Array<u256>,
        calldatas: Array<Span<felt252>>,
        description: felt252,
    ) -> u256;

    fn cancel(ref self: TContractState, proposal_id: u256);
    fn queue(ref self: TContractState, proposal_id: u256);
    fn execute(ref self: TContractState, proposal_id: u256);

    // Voting functions
    fn cast_vote(ref self: TContractState, proposal_id: u256, support: u8);
    fn cast_vote_with_reason(
        ref self: TContractState, proposal_id: u256, support: u8, reason: felt252,
    );

    // View functions
    fn get_proposal(
        self: @TContractState, proposal_id: u256,
    ) -> super::super::types::governance::Proposal;
    fn get_proposal_actions(
        self: @TContractState, proposal_id: u256,
    ) -> Array<super::super::types::governance::ProposalAction>;
    fn get_proposal_state(self: @TContractState, proposal_id: u256) -> u8;
    fn get_voting_power(self: @TContractState, account: ContractAddress, timepoint: u64) -> u256;
    fn get_votes(
        self: @TContractState, proposal_id: u256,
    ) -> (u256, u256, u256); // for, against, abstain
    fn has_voted(self: @TContractState, proposal_id: u256, account: ContractAddress) -> bool;

    // Configuration
    fn voting_delay(self: @TContractState) -> u64;
    fn voting_period(self: @TContractState) -> u64;
    fn proposal_threshold(self: @TContractState) -> u256;
    fn quorum(self: @TContractState, timepoint: u64) -> u256;

    // Admin functions
    fn set_voting_delay(ref self: TContractState, new_delay: u64);
    fn set_voting_period(ref self: TContractState, new_period: u64);
    fn set_proposal_threshold(ref self: TContractState, new_threshold: u256);
    fn set_quorum_percentage(ref self: TContractState, new_percentage: u16);
}
