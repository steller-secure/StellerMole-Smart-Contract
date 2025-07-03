use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address
};
use starkmole::interfaces::treasury::{
    ITreasuryDispatcher, ITreasuryDispatcherTrait
};
use starkmole::types::{FeeDistribution, PoolTypes, FeeTypes};
use starknet::{ContractAddress, contract_address_const};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

// Interface for our MockERC20 mint function
#[starknet::interface]
trait IMockERC20<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
}

// Mock ERC20 token for testing
fn deploy_mock_token() -> (IERC20Dispatcher, IMockERC20Dispatcher, ContractAddress) {
    let contract = declare("MockERC20").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    (
        IERC20Dispatcher { contract_address }, 
        IMockERC20Dispatcher { contract_address },
        contract_address
    )
}

// Helper function to deploy treasury contract and token
fn deploy_treasury_and_token() -> (ITreasuryDispatcher, ContractAddress, IERC20Dispatcher, IMockERC20Dispatcher, ContractAddress) {
    let (token_contract, mock_token, token_address) = deploy_mock_token();
    let contract = declare("Treasury").unwrap().contract_class();
    let owner = contract_address_const::<'treasury_owner'>();
    let required_approvals = 2_u32;
    
    let (contract_address, _) = contract
        .deploy(@array![owner.into(), token_address.into(), required_approvals.into()])
        .unwrap();
    
    let treasury_dispatcher = ITreasuryDispatcher { contract_address };
    
    (treasury_dispatcher, contract_address, token_contract, mock_token, token_address)
}

// Helper function to deploy treasury contract only
fn deploy_treasury_contract() -> (ITreasuryDispatcher, ContractAddress) {
    let contract = declare("Treasury").unwrap().contract_class();
    let owner = contract_address_const::<'treasury_owner'>();
    let token_address = contract_address_const::<'mock_token'>();
    let required_approvals = 2_u32;
    
    let (contract_address, _) = contract
        .deploy(@array![owner.into(), token_address.into(), required_approvals.into()])
        .unwrap();
    
    let treasury_dispatcher = ITreasuryDispatcher { contract_address };
    
    (treasury_dispatcher, contract_address)
}

#[test]
fn test_treasury_initialization() {
    let (treasury_contract, _) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    
    // Check that owner is admin
    assert(treasury_contract.is_admin(owner), 'Owner should be admin');
    
    // Check default pools exist
    let pools = treasury_contract.get_all_pool_balances();
    assert(pools.len() == 6, 'Should have 6 default pools');
    
    // Check default fee rates
    let game_start_fee = treasury_contract.get_fee_rate(FeeTypes::GAME_START_FEE);
    assert(game_start_fee == 50, 'Game start fee should be 0.5%');
    
    let reward_claim_fee = treasury_contract.get_fee_rate(FeeTypes::REWARD_CLAIM_FEE);
    assert(reward_claim_fee == 100, 'Reward claim fee should be 1%');
    
    // Check default fee distribution
    let distributions = treasury_contract.get_fee_distribution();
    assert(distributions.len() == 6, 'Should have 6 distributions');
}

#[test]
fn test_admin_management() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    let new_admin = contract_address_const::<'new_admin'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add new admin
    treasury_contract.add_admin(new_admin);
    assert(treasury_contract.is_admin(new_admin), 'New admin should be added');
    
    // Remove admin
    treasury_contract.remove_admin(new_admin);
    assert(!treasury_contract.is_admin(new_admin), 'Admin should be removed');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Only owner can call this',))]
fn test_add_admin_unauthorized() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let unauthorized = contract_address_const::<'unauthorized'>();
    let new_admin = contract_address_const::<'new_admin'>();
    
    start_cheat_caller_address(contract_address, unauthorized);
    treasury_contract.add_admin(new_admin);
}

#[test]
fn test_fee_collector_management() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    let collector = contract_address_const::<'fee_collector'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add fee collector
    treasury_contract.add_fee_collector(collector);
    assert(treasury_contract.is_fee_collector(collector), 'Should be fee collector');
    
    // Remove fee collector
    treasury_contract.remove_fee_collector(collector);
    assert(!treasury_contract.is_fee_collector(collector), 'Should not be fee collector');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_fee_rate_configuration() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Set new fee rate
    let new_rate = 250_u16; // 2.5%
    treasury_contract.set_fee_rate(FeeTypes::GAME_START_FEE, new_rate);
    
    let updated_rate = treasury_contract.get_fee_rate(FeeTypes::GAME_START_FEE);
    assert(updated_rate == new_rate, 'Fee rate should be updated');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Rate cannot exceed 100%',))]
fn test_invalid_fee_rate() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    
    start_cheat_caller_address(contract_address, owner);
    treasury_contract.set_fee_rate(FeeTypes::GAME_START_FEE, 10001); // 100.01%
}

#[test]
fn test_fee_distribution_configuration() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Set new fee distribution
    let mut new_distributions = ArrayTrait::new();
    new_distributions.append(FeeDistribution { pool_type: PoolTypes::REWARDS_POOL, percentage_bps: 7000 }); // 70%
    new_distributions.append(FeeDistribution { pool_type: PoolTypes::DAO_POOL, percentage_bps: 3000 }); // 30%
    
    treasury_contract.set_fee_distribution(new_distributions);
    
    let distributions = treasury_contract.get_fee_distribution();
    assert(distributions.len() == 2, 'Should have 2 distributions');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_calculate_fee() {
    let (treasury_contract, _) = deploy_treasury_contract();
    
    let base_amount = 10000000000000000000_u256; // 10 tokens
    let fee = treasury_contract.calculate_fee(FeeTypes::GAME_START_FEE, base_amount);
    
    // Default rate is 50 bps (0.5%), so fee should be 0.05 tokens
    let expected_fee = (base_amount * 50) / 10000;
    assert(fee == expected_fee, 'Fee calc should be correct');
}

#[test]
fn test_pause_and_unpause() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Initially not paused
    assert(!treasury_contract.is_paused(), 'Should not be paused initially');
    
    // Pause
    treasury_contract.pause_fee_collection();
    assert(treasury_contract.is_paused(), 'Should be paused');
    
    // Unpause
    treasury_contract.unpause_fee_collection();
    assert(!treasury_contract.is_paused(), 'Should not be paused');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_pool_creation() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    let custom_pool = 'CUSTOM_POOL';
    let initial_balance = 0_u256; // No initial balance for testing
    
    // Create custom pool
    treasury_contract.create_pool(custom_pool, initial_balance);
    
    let balance = treasury_contract.get_pool_balance(custom_pool);
    assert(balance == initial_balance, 'Custom pool should match');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_authorized_contract_management() {
    let (treasury_contract, contract_address) = deploy_treasury_contract();
    let owner = contract_address_const::<'treasury_owner'>();
    let authorized_contract = contract_address_const::<'authorized_contract'>();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Authorize contract
    treasury_contract.set_authorized_contract(authorized_contract, true);
    
    // Revoke authorization
    treasury_contract.set_authorized_contract(authorized_contract, false);
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_treasury_statistics() {
    let (treasury_contract, _) = deploy_treasury_contract();
    
    // Check initial statistics
    let total_fees = treasury_contract.get_total_fees_collected();
    assert(total_fees == 0, 'Initial total fees should be 0');
    
    let game_fees = treasury_contract.get_fees_by_type(FeeTypes::GAME_START_FEE);
    assert(game_fees == 0, 'Initial game fees should be 0');
    
    let treasury_value = treasury_contract.get_total_treasury_value();
    assert(treasury_value == 0, 'Initial treasury value 0');
}

#[test]
fn test_fee_collection() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    let collector = contract_address_const::<'fee_collector'>();
    let payer = contract_address_const::<'payer'>();
    
    // Setup: Add fee collector
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.add_fee_collector(collector);
    stop_cheat_caller_address(treasury_address);
    
    // Mint tokens to payer and approve treasury
    let fee_amount = 1000000000000000000_u256; // 1 token
    mock_token.mint(payer, fee_amount);
    
    start_cheat_caller_address(token_address, payer);
    token_contract.approve(treasury_address, fee_amount);
    stop_cheat_caller_address(token_address);
    
    // Collect fee
    start_cheat_caller_address(treasury_address, collector);
    treasury_contract.collect_fee(FeeTypes::GAME_START_FEE, fee_amount, payer);
    stop_cheat_caller_address(treasury_address);
    
    // Check fee was collected and distributed
    let total_fees = treasury_contract.get_total_fees_collected();
    assert(total_fees == fee_amount, 'Total fees should match');
    
    let game_fees = treasury_contract.get_fees_by_type(FeeTypes::GAME_START_FEE);
    assert(game_fees == fee_amount, 'Game fees should match');
    
    // Check rewards pool got 50% (default distribution)
    let rewards_balance = treasury_contract.get_pool_balance(PoolTypes::REWARDS_POOL);
    let expected_rewards = (fee_amount * 5000) / 10000; // 50%
    assert(rewards_balance == expected_rewards, 'Rewards pool should get 50%');
}

#[test]
#[should_panic(expected: ('Unauthorized fee collection',))]
fn test_unauthorized_fee_collection() {
    let (treasury_contract, treasury_address, _, _, _) = deploy_treasury_and_token();
    let unauthorized = contract_address_const::<'unauthorized'>();
    let payer = contract_address_const::<'payer'>();
    
    start_cheat_caller_address(treasury_address, unauthorized);
    treasury_contract.collect_fee(FeeTypes::GAME_START_FEE, 1000, payer);
}

#[test]
fn test_pool_management() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    
    // Setup tokens for owner
    let deposit_amount = 5000000000000000000_u256; // 5 tokens
    mock_token.mint(owner, deposit_amount);
    
    start_cheat_caller_address(token_address, owner);
    token_contract.approve(treasury_address, deposit_amount);
    stop_cheat_caller_address(token_address);
    
    start_cheat_caller_address(treasury_address, owner);
    
    // Deposit to pool
    treasury_contract.deposit_to_pool(PoolTypes::REWARDS_POOL, deposit_amount);
    
    let balance = treasury_contract.get_pool_balance(PoolTypes::REWARDS_POOL);
    assert(balance == deposit_amount, 'Pool balance should match');
    
    // Withdraw from pool
    let recipient = contract_address_const::<'recipient'>();
    let withdraw_amount = 2000000000000000000_u256; // 2 tokens
    treasury_contract.withdraw_from_pool(PoolTypes::REWARDS_POOL, withdraw_amount, recipient);
    
    let balance_after = treasury_contract.get_pool_balance(PoolTypes::REWARDS_POOL);
    let expected_balance = deposit_amount - withdraw_amount;
    assert(balance_after == expected_balance, 'Pool balance should be reduced');
    
    stop_cheat_caller_address(treasury_address);
}

#[test]
fn test_pool_transfer() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    
    // Setup initial balance in rewards pool
    let initial_amount = 3000000000000000000_u256; // 3 tokens
    mock_token.mint(owner, initial_amount);
    
    start_cheat_caller_address(token_address, owner);
    token_contract.approve(treasury_address, initial_amount);
    stop_cheat_caller_address(token_address);
    
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.deposit_to_pool(PoolTypes::REWARDS_POOL, initial_amount);
    
    // Transfer between pools
    let transfer_amount = 1000000000000000000_u256; // 1 token
    treasury_contract.transfer_between_pools(
        PoolTypes::REWARDS_POOL,
        PoolTypes::DAO_POOL,
        transfer_amount
    );
    
    let rewards_balance = treasury_contract.get_pool_balance(PoolTypes::REWARDS_POOL);
    let dao_balance = treasury_contract.get_pool_balance(PoolTypes::DAO_POOL);
    
    assert(rewards_balance == initial_amount - transfer_amount, 'Rewards pool should be reduced');
    assert(dao_balance == transfer_amount, 'DAO pool should receive');
    
    stop_cheat_caller_address(treasury_address);
}

#[test]
fn test_create_custom_pool() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    
    let custom_pool = 'CUSTOM_POOL';
    let initial_balance = 2000000000000000000_u256; // 2 tokens
    
    // Setup tokens for owner
    mock_token.mint(owner, initial_balance);
    
    start_cheat_caller_address(token_address, owner);
    token_contract.approve(treasury_address, initial_balance);
    stop_cheat_caller_address(token_address);
    
    start_cheat_caller_address(treasury_address, owner);
    
    // Create custom pool
    treasury_contract.create_pool(custom_pool, initial_balance);
    
    let balance = treasury_contract.get_pool_balance(custom_pool);
    assert(balance == initial_balance, 'Custom pool should match');
    
    stop_cheat_caller_address(treasury_address);
}

#[test]
fn test_multisig_withdrawal_proposal() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    let admin1 = contract_address_const::<'admin1'>();
    let admin2 = contract_address_const::<'admin2'>();
    let recipient = contract_address_const::<'recipient'>();
    
    // Setup: Add admins and fund pool
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.add_admin(admin1);
    treasury_contract.add_admin(admin2);
    stop_cheat_caller_address(treasury_address);
    
    let pool_balance = 5000000000000000000_u256; // 5 tokens
    mock_token.mint(owner, pool_balance);
    
    start_cheat_caller_address(token_address, owner);
    token_contract.approve(treasury_address, pool_balance);
    stop_cheat_caller_address(token_address);
    
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.deposit_to_pool(PoolTypes::REWARDS_POOL, pool_balance);
    stop_cheat_caller_address(treasury_address);
    
    // Propose withdrawal
    let withdrawal_amount = 2000000000000000000_u256; // 2 tokens
    start_cheat_caller_address(treasury_address, admin1);
    let proposal_id = treasury_contract.propose_withdrawal(
        PoolTypes::REWARDS_POOL,
        withdrawal_amount,
        recipient
    );
    assert(proposal_id == 1, 'First proposal should have ID 1');
    stop_cheat_caller_address(treasury_address);
    
    // Get proposal details
    let proposal = treasury_contract.get_withdrawal_proposal(proposal_id);
    assert(proposal.proposal_id == proposal_id, 'Proposal ID should match');
    assert(proposal.amount == withdrawal_amount, 'Amount should match');
    assert(!proposal.executed, 'Should not be executed yet');
    assert(proposal.approval_count == 0, 'Should have 0 approvals');
    
    // Approve by admin1
    start_cheat_caller_address(treasury_address, admin1);
    treasury_contract.approve_withdrawal(proposal_id);
    stop_cheat_caller_address(treasury_address);
    
    // Check approval count
    let proposal_after_approval1 = treasury_contract.get_withdrawal_proposal(proposal_id);
    assert(proposal_after_approval1.approval_count == 1, 'Should have 1 approval');
    
    // Approve by admin2
    start_cheat_caller_address(treasury_address, admin2);
    treasury_contract.approve_withdrawal(proposal_id);
    stop_cheat_caller_address(treasury_address);
    
    // Check approval count
    let proposal_after_approval2 = treasury_contract.get_withdrawal_proposal(proposal_id);
    assert(proposal_after_approval2.approval_count == 2, 'Should have 2 approvals');
    
    // Execute withdrawal
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.execute_withdrawal(proposal_id);
    stop_cheat_caller_address(treasury_address);
    
    // Check execution
    let proposal_final = treasury_contract.get_withdrawal_proposal(proposal_id);
    assert(proposal_final.executed, 'Should be executed');
    
    let pool_balance_after = treasury_contract.get_pool_balance(PoolTypes::REWARDS_POOL);
    assert(pool_balance_after == pool_balance - withdrawal_amount, 'Pool should be reduced');
}

#[test]
#[should_panic(expected: ('Insufficient approvals',))]
fn test_execute_withdrawal_insufficient_approvals() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    let admin1 = contract_address_const::<'admin1'>();
    let recipient = contract_address_const::<'recipient'>();
    
    // Setup
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.add_admin(admin1);
    stop_cheat_caller_address(treasury_address);
    
    let pool_balance = 5000000000000000000_u256;
    mock_token.mint(owner, pool_balance);
    
    start_cheat_caller_address(token_address, owner);
    token_contract.approve(treasury_address, pool_balance);
    stop_cheat_caller_address(token_address);
    
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.deposit_to_pool(PoolTypes::REWARDS_POOL, pool_balance);
    stop_cheat_caller_address(treasury_address);
    
    // Propose and approve only once (need 2 approvals)
    start_cheat_caller_address(treasury_address, admin1);
    let proposal_id = treasury_contract.propose_withdrawal(PoolTypes::REWARDS_POOL, 1000, recipient);
    treasury_contract.approve_withdrawal(proposal_id);
    stop_cheat_caller_address(treasury_address);
    
    // Try to execute with insufficient approvals
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.execute_withdrawal(proposal_id);
}

#[test]
fn test_fee_collection_history() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    let collector = contract_address_const::<'fee_collector'>();
    let payer = contract_address_const::<'payer'>();
    
    // Setup
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.add_fee_collector(collector);
    stop_cheat_caller_address(treasury_address);
    
    // Setup tokens and approvals
    let fee_amount = 1000000000000000000_u256;
    mock_token.mint(payer, fee_amount * 3); // For 3 fee collections
    
    start_cheat_caller_address(token_address, payer);
    token_contract.approve(treasury_address, fee_amount * 3);
    stop_cheat_caller_address(token_address);
    
    // Collect multiple fees
    start_cheat_caller_address(treasury_address, collector);
    treasury_contract.collect_fee(FeeTypes::GAME_START_FEE, fee_amount, payer);
    treasury_contract.collect_fee(FeeTypes::REWARD_CLAIM_FEE, fee_amount, payer);
    treasury_contract.collect_fee(FeeTypes::BRIDGE_FEE, fee_amount, payer);
    stop_cheat_caller_address(treasury_address);
    
    // Check history
    let history = treasury_contract.get_fee_collection_history(0, 10);
    assert(history.len() == 3, 'Should have 3 fee records');
    
    let first_record = *history.at(0);
    assert(first_record.fee_type == FeeTypes::GAME_START_FEE, 'First record should be game fee');
    assert(first_record.amount == fee_amount, 'Amount should match');
    assert(first_record.payer == payer, 'Payer should match');
    assert(first_record.collector == collector, 'Collector should match');
}

#[test]
fn test_authorized_contract_fee_collection() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    let authorized_contract = contract_address_const::<'authorized_contract'>();
    let payer = contract_address_const::<'payer'>();
    
    // Setup: Authorize contract
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.set_authorized_contract(authorized_contract, true);
    stop_cheat_caller_address(treasury_address);
    
    // Setup tokens
    let fee_amount = 1000000000000000000_u256;
    mock_token.mint(payer, fee_amount);
    
    start_cheat_caller_address(token_address, payer);
    token_contract.approve(treasury_address, fee_amount);
    stop_cheat_caller_address(token_address);
    
    // Authorized contract can collect fees
    start_cheat_caller_address(treasury_address, authorized_contract);
    treasury_contract.collect_fee(FeeTypes::GAME_START_FEE, fee_amount, payer);
    stop_cheat_caller_address(treasury_address);
    
    let total_fees = treasury_contract.get_total_fees_collected();
    assert(total_fees == fee_amount, 'Fee should be collected');
}

#[test]
fn test_get_treasury_statistics() {
    let (treasury_contract, treasury_address, token_contract, mock_token, token_address) = deploy_treasury_and_token();
    let owner = contract_address_const::<'treasury_owner'>();
    let collector = contract_address_const::<'fee_collector'>();
    let payer = contract_address_const::<'payer'>();
    
    // Setup
    start_cheat_caller_address(treasury_address, owner);
    treasury_contract.add_fee_collector(collector);
    stop_cheat_caller_address(treasury_address);
    
    let fee_amount = 2000000000000000000_u256; // 2 tokens
    mock_token.mint(payer, fee_amount);
    
    start_cheat_caller_address(token_address, payer);
    token_contract.approve(treasury_address, fee_amount);
    stop_cheat_caller_address(token_address);
    
    // Collect fee
    start_cheat_caller_address(treasury_address, collector);
    treasury_contract.collect_fee(FeeTypes::GAME_START_FEE, fee_amount, payer);
    stop_cheat_caller_address(treasury_address);
    
    // Check statistics
    let total_fees = treasury_contract.get_total_fees_collected();
    assert(total_fees == fee_amount, 'Total fees should match');
    
    let game_fees = treasury_contract.get_fees_by_type(FeeTypes::GAME_START_FEE);
    assert(game_fees == fee_amount, 'Game fees should match');
    
    let treasury_value = treasury_contract.get_total_treasury_value();
    assert(treasury_value == fee_amount, 'Treasury value should match');
    
    // Check pool balances are distributed correctly
    let pools = treasury_contract.get_all_pool_balances();
    assert(pools.len() == 6, 'Should have 6 pools');
    
    // Rewards pool should have 50% (5000 bps)
    let rewards_balance = treasury_contract.get_pool_balance(PoolTypes::REWARDS_POOL);
    let expected_rewards = (fee_amount * 5000) / 10000;
    assert(rewards_balance == expected_rewards, 'Rewards pool should get 50%');
} 