use starknet::ContractAddress;
use starkmole::types::{FeeCollection, FeeDistribution, PoolInfo, WithdrawalProposal, FeeRecord};

// Interface for Treasury and Fee Management
#[starknet::interface]
pub trait ITreasury<TContractState> {
    // Fee Collection
    fn collect_fee(ref self: TContractState, fee_type: felt252, amount: u256, payer: ContractAddress);
    fn collect_fee_batch(ref self: TContractState, fees: Array<FeeCollection>);
    
    // Treasury Management
    fn deposit_to_pool(ref self: TContractState, pool_type: felt252, amount: u256);
    fn withdraw_from_pool(ref self: TContractState, pool_type: felt252, amount: u256, recipient: ContractAddress);
    fn transfer_between_pools(ref self: TContractState, from_pool: felt252, to_pool: felt252, amount: u256);
    
    // Fee Configuration
    fn set_fee_rate(ref self: TContractState, operation: felt252, rate_bps: u16); // basis points (1/10000)
    fn set_fee_distribution(ref self: TContractState, distributions: Array<FeeDistribution>);
    fn get_fee_rate(self: @TContractState, operation: felt252) -> u16;
    fn get_fee_distribution(self: @TContractState) -> Array<FeeDistribution>;
    
    // Pool Management
    fn get_pool_balance(self: @TContractState, pool_type: felt252) -> u256;
    fn get_all_pool_balances(self: @TContractState) -> Array<PoolInfo>;
    fn create_pool(ref self: TContractState, pool_type: felt252, initial_balance: u256);
    
    // Access Control and Admin
    fn add_admin(ref self: TContractState, admin: ContractAddress);
    fn remove_admin(ref self: TContractState, admin: ContractAddress);
    fn add_fee_collector(ref self: TContractState, collector: ContractAddress);
    fn remove_fee_collector(ref self: TContractState, collector: ContractAddress);
    fn is_admin(self: @TContractState, address: ContractAddress) -> bool;
    fn is_fee_collector(self: @TContractState, address: ContractAddress) -> bool;
    
    // Multi-sig Operations
    fn propose_withdrawal(ref self: TContractState, pool_type: felt252, amount: u256, recipient: ContractAddress) -> u32;
    fn approve_withdrawal(ref self: TContractState, proposal_id: u32);
    fn execute_withdrawal(ref self: TContractState, proposal_id: u32);
    fn get_withdrawal_proposal(self: @TContractState, proposal_id: u32) -> WithdrawalProposal;
    
    // Treasury Statistics and Transparency
    fn get_total_fees_collected(self: @TContractState) -> u256;
    fn get_fees_by_type(self: @TContractState, fee_type: felt252) -> u256;
    fn get_total_treasury_value(self: @TContractState) -> u256;
    fn get_fee_collection_history(self: @TContractState, offset: u32, limit: u32) -> Array<FeeRecord>;
    
    // Integration with other contracts
    fn set_authorized_contract(ref self: TContractState, contract_address: ContractAddress, authorized: bool);
    fn calculate_fee(self: @TContractState, operation: felt252, base_amount: u256) -> u256;
    
    // Emergency and Maintenance
    fn pause_fee_collection(ref self: TContractState);
    fn unpause_fee_collection(ref self: TContractState);
    fn emergency_withdraw_all(ref self: TContractState, recipient: ContractAddress);
    fn is_paused(self: @TContractState) -> bool;
} 