#[starknet::contract]
pub mod Treasury {
    use starkmole::interfaces::treasury::{
        ITreasury,
    };
    use starkmole::types::{
        PoolTypes, FeeTypes, PoolInfo, WithdrawalProposal, FeeRecord, FeeCollection, FeeDistribution
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_tx_info};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::array::ArrayTrait;

    #[storage]
    struct Storage {
        // Access Control
        owner: ContractAddress,
        admins: Map<ContractAddress, bool>,
        fee_collectors: Map<ContractAddress, bool>,
        authorized_contracts: Map<ContractAddress, bool>,
        
        // Treasury Pools
        pool_balances: Map<felt252, u256>,
        pool_total_inflows: Map<felt252, u256>,
        pool_total_outflows: Map<felt252, u256>,
        pool_exists: Map<felt252, bool>,
        
        // Fee Configuration
        fee_rates: Map<felt252, u16>, // operation -> basis points
        fee_distributions: Map<u32, FeeDistribution>, // index -> distribution
        fee_distribution_count: u32,
        
        // Fee Tracking
        total_fees_collected: u256,
        fees_by_type: Map<felt252, u256>,
        fee_records: Map<u32, FeeRecord>,
        fee_record_count: u32,
        
        // Multi-sig Withdrawals
        withdrawal_proposals: Map<u32, WithdrawalProposal>,
        proposal_approvals: Map<(u32, ContractAddress), bool>, // (proposal_id, approver) -> approved
        proposal_count: u32,
        required_approvals: u32,
        
        // Token and State
        token_address: ContractAddress,
        paused: bool,
        
        // Statistics
        total_treasury_value: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        FeeCollected: FeeCollected,
        PoolDeposit: PoolDeposit,
        PoolWithdrawal: PoolWithdrawal,
        PoolTransfer: PoolTransfer,
        PoolCreated: PoolCreated,
        FeeRateUpdated: FeeRateUpdated,
        FeeDistributionUpdated: FeeDistributionUpdated,
        AdminAdded: AdminAdded,
        AdminRemoved: AdminRemoved,
        FeeCollectorAdded: FeeCollectorAdded,
        FeeCollectorRemoved: FeeCollectorRemoved,
        WithdrawalProposed: WithdrawalProposed,
        WithdrawalApproved: WithdrawalApproved,
        WithdrawalExecuted: WithdrawalExecuted,
        ContractAuthorized: ContractAuthorized,
        TreasuryPaused: TreasuryPaused,
        TreasuryUnpaused: TreasuryUnpaused,
        EmergencyWithdrawal: EmergencyWithdrawal,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeCollected {
        pub fee_type: felt252,
        pub amount: u256,
        pub payer: ContractAddress,
        pub collector: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PoolDeposit {
        pub pool_type: felt252,
        pub amount: u256,
        pub depositor: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PoolWithdrawal {
        pub pool_type: felt252,
        pub amount: u256,
        pub recipient: ContractAddress,
        pub authorized_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PoolTransfer {
        pub from_pool: felt252,
        pub to_pool: felt252,
        pub amount: u256,
        pub authorized_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PoolCreated {
        pub pool_type: felt252,
        pub initial_balance: u256,
        pub created_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeRateUpdated {
        pub operation: felt252,
        pub old_rate_bps: u16,
        pub new_rate_bps: u16,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeDistributionUpdated {
        pub updated_by: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AdminAdded {
        pub admin: ContractAddress,
        pub added_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AdminRemoved {
        pub admin: ContractAddress,
        pub removed_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeCollectorAdded {
        pub collector: ContractAddress,
        pub added_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeCollectorRemoved {
        pub collector: ContractAddress,
        pub removed_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawalProposed {
        pub proposal_id: u32,
        pub pool_type: felt252,
        pub amount: u256,
        pub recipient: ContractAddress,
        pub proposer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawalApproved {
        pub proposal_id: u32,
        pub approver: ContractAddress,
        pub approval_count: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawalExecuted {
        pub proposal_id: u32,
        pub amount: u256,
        pub recipient: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContractAuthorized {
        pub contract_address: ContractAddress,
        pub authorized: bool,
        pub authorized_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TreasuryPaused {
        pub paused_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TreasuryUnpaused {
        pub unpaused_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EmergencyWithdrawal {
        pub amount: u256,
        pub recipient: ContractAddress,
        pub authorized_by: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        token_address: ContractAddress,
        required_approvals: u32,
    ) {
        self.owner.write(owner);
        self.token_address.write(token_address);
        self.required_approvals.write(required_approvals);
        self.paused.write(false);
        
        // Initialize owner as admin
        self.admins.write(owner, true);
        
        // Initialize default pools
        self._initialize_default_pools();
        
        // Initialize default fee rates
        self._initialize_default_fee_rates();
        
        // Initialize default fee distribution
        self._initialize_default_fee_distribution();
    }

    #[abi(embed_v0)]
    impl TreasuryImpl of ITreasury<ContractState> {
        fn collect_fee(ref self: ContractState, fee_type: felt252, amount: u256, payer: ContractAddress) {
            self._assert_not_paused();
            self._assert_fee_collector_or_authorized_contract();
            
            assert(amount > 0, 'Fee must be positive');
            
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            let tx_info = get_tx_info().unbox();
            
            // Transfer tokens from payer to treasury
            let token = IERC20Dispatcher { contract_address: self.token_address.read() };
            token.transfer_from(payer, starknet::get_contract_address(), amount);
            
            // Distribute fee to pools according to configuration
            self._distribute_fee(fee_type, amount);
            
            // Update statistics
            self.total_fees_collected.write(self.total_fees_collected.read() + amount);
            self.fees_by_type.write(fee_type, self.fees_by_type.read(fee_type) + amount);
            
            // Record fee collection
            let record_id = self.fee_record_count.read() + 1;
            let fee_record = FeeRecord {
                id: record_id,
                fee_type,
                amount,
                payer,
                collector: caller,
                timestamp: current_time,
                transaction_hash: tx_info.transaction_hash,
            };
            self.fee_records.write(record_id, fee_record);
            self.fee_record_count.write(record_id);
            
            self.emit(FeeCollected { fee_type, amount, payer, collector: caller, timestamp: current_time });
        }

        fn collect_fee_batch(ref self: ContractState, fees: Array<FeeCollection>) {
            self._assert_not_paused();
            self._assert_fee_collector_or_authorized_contract();
            
            let mut i = 0;
            while i < fees.len() {
                let fee = *fees.at(i);
                self.collect_fee(fee.fee_type, fee.amount, fee.payer);
                i += 1;
            };
        }

        fn deposit_to_pool(ref self: ContractState, pool_type: felt252, amount: u256) {
            self._assert_admin();
            self._assert_pool_exists(pool_type);
            assert(amount > 0, 'Deposit must be positive');
            
            let caller = get_caller_address();
            
            // Transfer tokens to treasury
            let token = IERC20Dispatcher { contract_address: self.token_address.read() };
            token.transfer_from(caller, starknet::get_contract_address(), amount);
            
            // Update pool balance and statistics
            self.pool_balances.write(pool_type, self.pool_balances.read(pool_type) + amount);
            self.pool_total_inflows.write(pool_type, self.pool_total_inflows.read(pool_type) + amount);
            self.total_treasury_value.write(self.total_treasury_value.read() + amount);
            
            self.emit(PoolDeposit { pool_type, amount, depositor: caller });
        }

        fn withdraw_from_pool(ref self: ContractState, pool_type: felt252, amount: u256, recipient: ContractAddress) {
            self._assert_admin();
            self._assert_pool_exists(pool_type);
            assert(amount > 0, 'Withdraw must be positive');
            
            let pool_balance = self.pool_balances.read(pool_type);
            assert(pool_balance >= amount, 'Insufficient pool balance');
            
            let caller = get_caller_address();
            
            // Update pool balance and statistics
            self.pool_balances.write(pool_type, pool_balance - amount);
            self.pool_total_outflows.write(pool_type, self.pool_total_outflows.read(pool_type) + amount);
            self.total_treasury_value.write(self.total_treasury_value.read() - amount);
            
            // Transfer tokens to recipient
            let token = IERC20Dispatcher { contract_address: self.token_address.read() };
            token.transfer(recipient, amount);
            
            self.emit(PoolWithdrawal { pool_type, amount, recipient, authorized_by: caller });
        }

        fn transfer_between_pools(ref self: ContractState, from_pool: felt252, to_pool: felt252, amount: u256) {
            self._assert_admin();
            self._assert_pool_exists(from_pool);
            self._assert_pool_exists(to_pool);
            assert(amount > 0, 'Transfer must be positive');
            assert(from_pool != to_pool, 'Cannot transfer to same pool');
            
            let from_balance = self.pool_balances.read(from_pool);
            assert(from_balance >= amount, 'Insufficient balance');
            
            let caller = get_caller_address();
            
            // Update pool balances
            self.pool_balances.write(from_pool, from_balance - amount);
            self.pool_balances.write(to_pool, self.pool_balances.read(to_pool) + amount);
            
            // Update statistics (outflow from source, inflow to destination)
            self.pool_total_outflows.write(from_pool, self.pool_total_outflows.read(from_pool) + amount);
            self.pool_total_inflows.write(to_pool, self.pool_total_inflows.read(to_pool) + amount);
            
            self.emit(PoolTransfer { from_pool, to_pool, amount, authorized_by: caller });
        }

        fn set_fee_rate(ref self: ContractState, operation: felt252, rate_bps: u16) {
            self._assert_admin();
            assert(rate_bps <= 10000, 'Rate cannot exceed 100%');
            
            let old_rate = self.fee_rates.read(operation);
            self.fee_rates.write(operation, rate_bps);
            
            self.emit(FeeRateUpdated { operation, old_rate_bps: old_rate, new_rate_bps: rate_bps });
        }

        fn set_fee_distribution(ref self: ContractState, distributions: Array<FeeDistribution>) {
            self._assert_admin();
            
            // Validate that percentages add up to 100%
            let mut total_percentage = 0_u16;
            let mut i = 0;
            while i < distributions.len() {
                let distribution = *distributions.at(i);
                total_percentage += distribution.percentage_bps;
                i += 1;
            };
            assert(total_percentage == 10000, 'Must sum to 100%');
            
            // Clear existing distributions
            let old_count = self.fee_distribution_count.read();
            let mut j = 0;
            while j < old_count {
                self.fee_distributions.write(j, FeeDistribution { pool_type: 0, percentage_bps: 0 });
                j += 1;
            };
            
            // Set new distributions
            let mut k = 0;
            while k < distributions.len() {
                let distribution = *distributions.at(k);
                self._assert_pool_exists(distribution.pool_type);
                self.fee_distributions.write(k, distribution);
                k += 1;
            };
            
            self.fee_distribution_count.write(distributions.len());
            
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            self.emit(FeeDistributionUpdated { updated_by: caller, timestamp: current_time });
        }

        fn get_fee_rate(self: @ContractState, operation: felt252) -> u16 {
            self.fee_rates.read(operation)
        }

        fn get_fee_distribution(self: @ContractState) -> Array<FeeDistribution> {
            let mut distributions = ArrayTrait::new();
            let count = self.fee_distribution_count.read();
            let mut i = 0;
            while i < count {
                distributions.append(self.fee_distributions.read(i));
                i += 1;
            };
            distributions
        }

        fn get_pool_balance(self: @ContractState, pool_type: felt252) -> u256 {
            self.pool_balances.read(pool_type)
        }

        fn get_all_pool_balances(self: @ContractState) -> Array<PoolInfo> {
            let mut pools = ArrayTrait::new();
            
            // Return info for all known pool types
            let pool_types = self._get_all_pool_types();
            let mut i = 0;
            while i < pool_types.len() {
                let pool_type = *pool_types.at(i);
                if self.pool_exists.read(pool_type) {
                    pools.append(PoolInfo {
                        pool_type,
                        balance: self.pool_balances.read(pool_type),
                        total_inflows: self.pool_total_inflows.read(pool_type),
                        total_outflows: self.pool_total_outflows.read(pool_type),
                    });
                }
                i += 1;
            };
            
            pools
        }

        fn create_pool(ref self: ContractState, pool_type: felt252, initial_balance: u256) {
            self._assert_admin();
            assert(!self.pool_exists.read(pool_type), 'Pool already exists');
            
            let caller = get_caller_address();
            
            // Create pool
            self.pool_exists.write(pool_type, true);
            self.pool_balances.write(pool_type, initial_balance);
            
            if initial_balance > 0 {
                // Transfer initial balance to treasury
                let token = IERC20Dispatcher { contract_address: self.token_address.read() };
                token.transfer_from(caller, starknet::get_contract_address(), initial_balance);
                
                self.pool_total_inflows.write(pool_type, initial_balance);
                self.total_treasury_value.write(self.total_treasury_value.read() + initial_balance);
            }
            
            self.emit(PoolCreated { pool_type, initial_balance, created_by: caller });
        }

        fn add_admin(ref self: ContractState, admin: ContractAddress) {
            self._assert_owner();
            self.admins.write(admin, true);
            
            let caller = get_caller_address();
            self.emit(AdminAdded { admin, added_by: caller });
        }

        fn remove_admin(ref self: ContractState, admin: ContractAddress) {
            self._assert_owner();
            assert(admin != self.owner.read(), 'Cannot remove owner');
            self.admins.write(admin, false);
            
            let caller = get_caller_address();
            self.emit(AdminRemoved { admin, removed_by: caller });
        }

        fn add_fee_collector(ref self: ContractState, collector: ContractAddress) {
            self._assert_admin();
            self.fee_collectors.write(collector, true);
            
            let caller = get_caller_address();
            self.emit(FeeCollectorAdded { collector, added_by: caller });
        }

        fn remove_fee_collector(ref self: ContractState, collector: ContractAddress) {
            self._assert_admin();
            self.fee_collectors.write(collector, false);
            
            let caller = get_caller_address();
            self.emit(FeeCollectorRemoved { collector, removed_by: caller });
        }

        fn is_admin(self: @ContractState, address: ContractAddress) -> bool {
            address == self.owner.read() || self.admins.read(address)
        }

        fn is_fee_collector(self: @ContractState, address: ContractAddress) -> bool {
            self.fee_collectors.read(address)
        }

        fn propose_withdrawal(ref self: ContractState, pool_type: felt252, amount: u256, recipient: ContractAddress) -> u32 {
            self._assert_admin();
            self._assert_pool_exists(pool_type);
            assert(amount > 0, 'Withdraw must be positive');
            assert(self.pool_balances.read(pool_type) >= amount, 'Insufficient balance');
            
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            let proposal_id = self.proposal_count.read() + 1;
            
            let proposal = WithdrawalProposal {
                proposal_id,
                pool_type,
                amount,
                recipient,
                proposer: caller,
                created_at: current_time,
                executed: false,
                approval_count: 0,
                required_approvals: self.required_approvals.read(),
            };
            
            self.withdrawal_proposals.write(proposal_id, proposal);
            self.proposal_count.write(proposal_id);
            
            self.emit(WithdrawalProposed { proposal_id, pool_type, amount, recipient, proposer: caller });
            
            proposal_id
        }

        fn approve_withdrawal(ref self: ContractState, proposal_id: u32) {
            self._assert_admin();
            
            let mut proposal = self.withdrawal_proposals.read(proposal_id);
            assert(proposal.proposal_id != 0, 'Proposal does not exist');
            assert(!proposal.executed, 'Proposal already executed');
            
            let caller = get_caller_address();
            assert(!self.proposal_approvals.read((proposal_id, caller)), 'Already approved');
            
            // Record approval
            self.proposal_approvals.write((proposal_id, caller), true);
            proposal.approval_count += 1;
            
            self.withdrawal_proposals.write(proposal_id, proposal);
            
            self.emit(WithdrawalApproved { proposal_id, approver: caller, approval_count: proposal.approval_count });
        }

        fn execute_withdrawal(ref self: ContractState, proposal_id: u32) {
            self._assert_admin();
            
            let mut proposal = self.withdrawal_proposals.read(proposal_id);
            assert(proposal.proposal_id != 0, 'Proposal does not exist');
            assert(!proposal.executed, 'Proposal already executed');
            assert(proposal.approval_count >= proposal.required_approvals, 'Insufficient approvals');
            
            // Execute withdrawal
            let pool_balance = self.pool_balances.read(proposal.pool_type);
            assert(pool_balance >= proposal.amount, 'Insufficient balance');
            
            self.pool_balances.write(proposal.pool_type, pool_balance - proposal.amount);
            self.pool_total_outflows.write(proposal.pool_type, self.pool_total_outflows.read(proposal.pool_type) + proposal.amount);
            self.total_treasury_value.write(self.total_treasury_value.read() - proposal.amount);
            
            // Transfer tokens
            let token = IERC20Dispatcher { contract_address: self.token_address.read() };
            token.transfer(proposal.recipient, proposal.amount);
            
            // Mark as executed
            proposal.executed = true;
            self.withdrawal_proposals.write(proposal_id, proposal);
            
            self.emit(WithdrawalExecuted { proposal_id, amount: proposal.amount, recipient: proposal.recipient });
        }

        fn get_withdrawal_proposal(self: @ContractState, proposal_id: u32) -> WithdrawalProposal {
            self.withdrawal_proposals.read(proposal_id)
        }

        fn get_total_fees_collected(self: @ContractState) -> u256 {
            self.total_fees_collected.read()
        }

        fn get_fees_by_type(self: @ContractState, fee_type: felt252) -> u256 {
            self.fees_by_type.read(fee_type)
        }

        fn get_total_treasury_value(self: @ContractState) -> u256 {
            self.total_treasury_value.read()
        }

        fn get_fee_collection_history(self: @ContractState, offset: u32, limit: u32) -> Array<FeeRecord> {
            let mut records = ArrayTrait::new();
            let total_records = self.fee_record_count.read();
            
            let start = offset + 1; // Records are 1-indexed
            let end = if start + limit > total_records + 1 { total_records + 1 } else { start + limit };
            
            let mut i = start;
            while i < end {
                records.append(self.fee_records.read(i));
                i += 1;
            };
            
            records
        }

        fn set_authorized_contract(ref self: ContractState, contract_address: ContractAddress, authorized: bool) {
            self._assert_admin();
            self.authorized_contracts.write(contract_address, authorized);
            
            let caller = get_caller_address();
            self.emit(ContractAuthorized { contract_address, authorized, authorized_by: caller });
        }

        fn calculate_fee(self: @ContractState, operation: felt252, base_amount: u256) -> u256 {
            let rate_bps = self.fee_rates.read(operation);
            (base_amount * rate_bps.into()) / 10000
        }

        fn pause_fee_collection(ref self: ContractState) {
            self._assert_admin();
            self.paused.write(true);
            
            let caller = get_caller_address();
            self.emit(TreasuryPaused { paused_by: caller });
        }

        fn unpause_fee_collection(ref self: ContractState) {
            self._assert_admin();
            self.paused.write(false);
            
            let caller = get_caller_address();
            self.emit(TreasuryUnpaused { unpaused_by: caller });
        }

        fn emergency_withdraw_all(ref self: ContractState, recipient: ContractAddress) {
            self._assert_owner();
            
            let token = IERC20Dispatcher { contract_address: self.token_address.read() };
            let balance = token.balance_of(starknet::get_contract_address());
            
            if balance > 0 {
                token.transfer(recipient, balance);
                
                // Reset all pool balances and treasury value
                self.total_treasury_value.write(0);
                
                let caller = get_caller_address();
                self.emit(EmergencyWithdrawal { amount: balance, recipient, authorized_by: caller });
            }
        }

        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_owner(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner can call this');
        }
        
        fn _assert_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.is_admin(caller), 'Only admin can call this');
        }
        
        fn _assert_fee_collector_or_authorized_contract(self: @ContractState) {
            let caller = get_caller_address();
            assert(
                self.fee_collectors.read(caller) || self.authorized_contracts.read(caller),
                'Unauthorized fee collection'
            );
        }
        
        fn _assert_not_paused(self: @ContractState) {
            assert(!self.paused.read(), 'Treasury is paused');
        }
        
        fn _assert_pool_exists(self: @ContractState, pool_type: felt252) {
            assert(self.pool_exists.read(pool_type), 'Pool does not exist');
        }
        
        fn _distribute_fee(ref self: ContractState, fee_type: felt252, amount: u256) {
            let distribution_count = self.fee_distribution_count.read();
            let mut i = 0;
            
            while i < distribution_count {
                let distribution = self.fee_distributions.read(i);
                let pool_amount = (amount * distribution.percentage_bps.into()) / 10000;
                
                if pool_amount > 0 {
                    let current_balance = self.pool_balances.read(distribution.pool_type);
                    self.pool_balances.write(distribution.pool_type, current_balance + pool_amount);
                    self.pool_total_inflows.write(distribution.pool_type, self.pool_total_inflows.read(distribution.pool_type) + pool_amount);
                }
                
                i += 1;
            };
            
            self.total_treasury_value.write(self.total_treasury_value.read() + amount);
        }
        
        fn _initialize_default_pools(ref self: ContractState) {
            // Initialize default pools with zero balance
            self.pool_exists.write(PoolTypes::REWARDS_POOL, true);
            self.pool_exists.write(PoolTypes::DAO_POOL, true);
            self.pool_exists.write(PoolTypes::DEV_FUND, true);
            self.pool_exists.write(PoolTypes::MARKETING_POOL, true);
            self.pool_exists.write(PoolTypes::LIQUIDITY_POOL, true);
            self.pool_exists.write(PoolTypes::INSURANCE_POOL, true);
        }
        
        fn _initialize_default_fee_rates(ref self: ContractState) {
            // Set default fee rates (in basis points, where 100 = 1%)
            self.fee_rates.write(FeeTypes::GAME_START_FEE, 50);  // 0.5%
            self.fee_rates.write(FeeTypes::REWARD_CLAIM_FEE, 100); // 1%
            self.fee_rates.write(FeeTypes::LEADERBOARD_SUBMIT_FEE, 25); // 0.25%
            self.fee_rates.write(FeeTypes::BRIDGE_FEE, 200); // 2%
            self.fee_rates.write(FeeTypes::STAKING_FEE, 150); // 1.5%
            self.fee_rates.write(FeeTypes::TRANSACTION_FEE, 75); // 0.75%
        }
        
        fn _initialize_default_fee_distribution(ref self: ContractState) {
            // Set default fee distribution: 50% rewards, 20% DAO, 15% dev, 10% marketing, 3% liquidity, 2% insurance
            self.fee_distributions.write(0, FeeDistribution { pool_type: PoolTypes::REWARDS_POOL, percentage_bps: 5000 });
            self.fee_distributions.write(1, FeeDistribution { pool_type: PoolTypes::DAO_POOL, percentage_bps: 2000 });
            self.fee_distributions.write(2, FeeDistribution { pool_type: PoolTypes::DEV_FUND, percentage_bps: 1500 });
            self.fee_distributions.write(3, FeeDistribution { pool_type: PoolTypes::MARKETING_POOL, percentage_bps: 1000 });
            self.fee_distributions.write(4, FeeDistribution { pool_type: PoolTypes::LIQUIDITY_POOL, percentage_bps: 300 });
            self.fee_distributions.write(5, FeeDistribution { pool_type: PoolTypes::INSURANCE_POOL, percentage_bps: 200 });
            self.fee_distribution_count.write(6);
        }
        
        fn _get_all_pool_types(self: @ContractState) -> Array<felt252> {
            let mut pool_types = ArrayTrait::new();
            pool_types.append(PoolTypes::REWARDS_POOL);
            pool_types.append(PoolTypes::DAO_POOL);
            pool_types.append(PoolTypes::DEV_FUND);
            pool_types.append(PoolTypes::MARKETING_POOL);
            pool_types.append(PoolTypes::LIQUIDITY_POOL);
            pool_types.append(PoolTypes::INSURANCE_POOL);
            pool_types
        }
    }
} 