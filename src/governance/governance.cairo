#[starknet::contract]
pub mod DAOGovernance {
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_block_timestamp,
        syscalls::call_contract_syscall,
    };
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec, MutableVecTrait, StoragePathEntry,
        Map,
    };

    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;

    use starkmole::interfaces::governance::IGovernance;
    use starkmole::types::governance::{
        Proposal, ProposalAction, VoteReceipt, GovernanceConfig, ProposalState, VoteType,
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // Emergency interface definition
    #[starknet::interface]
    trait IEmergency<TContractState> {
        fn emergency_pause(ref self: TContractState);
        fn emergency_unpause(ref self: TContractState);
        fn set_emergency_admin(ref self: TContractState, new_admin: ContractAddress);
    }


    #[storage]
    struct Storage {
        // Components
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        // Core governance state
        proposals: Map<u256, Proposal>,
        proposal_actions: Map<(u256, u32), ProposalAction>, // (proposal_id, action_index)
        votes: Map<(u256, ContractAddress), VoteReceipt>, // (proposal_id, voter)
        proposal_count: u256,
        // Governance configuration
        config: GovernanceConfig,
        // Anti-spam measures
        last_proposal_time: Map<ContractAddress, u64>,
        // Voting power source (could be token contract)
        voting_token: ContractAddress,
        // Treasury integration
        treasury_contract: ContractAddress,
        // Emergency controls
        paused: bool,
        emergency_admin: ContractAddress,
        // Calldata storage for proposals
        proposal_calldata: Map<(u256, u32), Vec<felt252>> // (proposal_id, action_index)
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        ProposalCreated: ProposalCreated,
        VoteCast: VoteCast,
        ProposalCanceled: ProposalCanceled,
        ProposalQueued: ProposalQueued,
        ProposalExecuted: ProposalExecuted,
        ConfigurationUpdated: ConfigurationUpdated,
        EmergencyAction: EmergencyAction,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalCreated {
        pub proposal_id: u256,
        pub proposer: ContractAddress,
        pub description: felt252,
        pub start_time: u64,
        pub end_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct VoteCast {
        pub proposal_id: u256,
        pub voter: ContractAddress,
        pub support: u8,
        pub voting_power: u256,
        pub reason: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalCanceled {
        pub proposal_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalQueued {
        pub proposal_id: u256,
        pub queue_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalExecuted {
        pub proposal_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ConfigurationUpdated {
        pub parameter: felt252,
        pub old_value: u256,
        pub new_value: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EmergencyAction {
        pub action: felt252,
        pub admin: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        voting_token: ContractAddress,
        treasury_contract: ContractAddress,
        initial_config: GovernanceConfig,
    ) {
        self.ownable.initializer(owner);
        self.voting_token.write(voting_token);
        self.treasury_contract.write(treasury_contract);
        self.config.write(initial_config);
        self.emergency_admin.write(owner);
        self.proposal_count.write(0);
        self.paused.write(false);
    }

    #[abi(embed_v0)]
    impl GovernanceImpl of IGovernance<ContractState> {
        fn propose(
            ref self: ContractState,
            targets: Array<ContractAddress>,
            values: Array<u256>,
            calldatas: Array<Span<felt252>>,
            description: felt252,
        ) -> u256 {
            self._assert_not_paused();
            self.reentrancy_guard.start();

            let caller = get_caller_address();
            let current_time = get_block_timestamp();

            // Check proposal threshold
            let voting_power = self._get_voting_power(caller, current_time);
            let threshold = self.config.read().proposal_threshold;
            assert(voting_power >= threshold, 'Insufficient voting power');

            // Anti-spam: check minimum proposal interval
            let config = self.config.read();
            let last_proposal = self.last_proposal_time.read(caller);
            assert(
                current_time >= last_proposal + config.min_proposal_interval,
                'Proposal interval too short',
            );

            // Validate proposal data
            let targets_len = targets.len();
            assert(targets_len > 0, 'Empty proposal');
            assert(targets_len == values.len(), 'values length mismatch');
            assert(targets_len == calldatas.len(), 'calldata length mismatch');
            assert(targets_len <= 10_u32, 'Too many actions'); // Limit complexity

            // Generate proposal ID
            let proposal_count = self.proposal_count.read() + 1;
            self.proposal_count.write(proposal_count);
            let proposal_id = proposal_count;

            // Calculate voting period
            let start_time = current_time + config.voting_delay;
            let end_time = start_time + config.voting_period;

            // Create proposal
            let proposal = Proposal {
                id: proposal_id,
                proposer: caller,
                description,
                start_time,
                end_time,
                for_votes: 0,
                against_votes: 0,
                abstain_votes: 0,
                canceled: false,
                executed: false,
                queued: false,
                queue_time: 0,
                targets_count: targets_len,
            };

            self.proposals.write(proposal_id, proposal);

            // Store proposal actions and calldata
            let mut i = 0;
            loop {
                if i >= targets_len {
                    break;
                }

                let action = ProposalAction {
                    proposal_id,
                    action_index: i,
                    target: *targets.at(i),
                    value: *values.at(i),
                    calldata_hash: self._hash_calldata(*calldatas.at(i)),
                };

                self.proposal_actions.write((proposal_id, i), action);

                // Store calldata
                let calldata = *calldatas.at(i);
                let calldata_vec = self.proposal_calldata.entry((proposal_id, i));
                let mut j = 0;
                loop {
                    if j >= calldata.len() {
                        break;
                    }
                    calldata_vec.append().write(*calldata.at(j));
                    j += 1;
                };

                i += 1;
            };

            // Update last proposal time for anti-spam
            self.last_proposal_time.write(caller, current_time);

            self
                .emit(
                    ProposalCreated {
                        proposal_id, proposer: caller, description, start_time, end_time,
                    },
                );

            self.reentrancy_guard.end();
            proposal_id
        }

        fn cancel(ref self: ContractState, proposal_id: u256) {
            self._assert_not_paused();
            let caller = get_caller_address();
            let proposal = self.proposals.read(proposal_id);

            // Only proposer or owner can cancel
            assert(
                caller == proposal.proposer || caller == self.ownable.owner(),
                'Not authorized to cancel',
            );

            let state = self._get_proposal_state_internal(proposal_id);
            assert(
                state == ProposalState::PENDING || state == ProposalState::ACTIVE,
                'Cannot cancel proposal',
            );

            let mut updated_proposal = proposal;
            updated_proposal.canceled = true;
            self.proposals.write(proposal_id, updated_proposal);

            self.emit(ProposalCanceled { proposal_id });
        }

        fn queue(ref self: ContractState, proposal_id: u256) {
            self._assert_not_paused();
            let state = self._get_proposal_state_internal(proposal_id);
            assert(state == ProposalState::SUCCEEDED, 'Proposal not succeeded');

            let mut proposal = self.proposals.read(proposal_id);
            let current_time = get_block_timestamp();

            proposal.queued = true;
            proposal.queue_time = current_time;
            self.proposals.write(proposal_id, proposal);

            self.emit(ProposalQueued { proposal_id, queue_time: current_time });
        }

        fn execute(ref self: ContractState, proposal_id: u256) {
            self._assert_not_paused();
            self.reentrancy_guard.start();

            let state = self._get_proposal_state_internal(proposal_id);
            assert(state == ProposalState::QUEUED, 'Proposal not ready');

            let mut proposal = self.proposals.read(proposal_id);
            let current_time = get_block_timestamp();
            let config = self.config.read();

            // Check timelock delay
            assert(
                current_time >= proposal.queue_time + config.timelock_delay, 'Timelock not expired',
            );

            // Execute proposal actions
            let mut i = 0;
            loop {
                if i >= proposal.targets_count {
                    break;
                }

                let action = self.proposal_actions.read((proposal_id, i));
                let calldata_vec = self.proposal_calldata.entry((proposal_id, i));

                // Convert Vec to Span
                let mut calldata_array: Array<felt252> = ArrayTrait::new();
                let mut j = 0;
                loop {
                    if j >= calldata_vec.len() {
                        break;
                    }
                    calldata_array.append(calldata_vec.at(j).read());
                    j += 1;
                };

                // Execute the call
                if action.value > 0 { // Handle ETH transfer if needed
                // Note: StarkNet doesn't have ETH in the same way, this could be token transfer
                }

                if calldata_array.len() > 0 {
                    let result = call_contract_syscall(
                        action.target,
                        *calldata_array.at(0), // function selector
                        calldata_array.span(),
                    );
                    assert(result.is_ok(), 'Execution failed');
                }

                i += 1;
            };

            proposal.executed = true;
            self.proposals.write(proposal_id, proposal);

            self.emit(ProposalExecuted { proposal_id });
            self.reentrancy_guard.end();
        }

        fn cast_vote(ref self: ContractState, proposal_id: u256, support: u8) {
            self.cast_vote_with_reason(proposal_id, support, '');
        }

        fn cast_vote_with_reason(
            ref self: ContractState, proposal_id: u256, support: u8, reason: felt252,
        ) {
            self._assert_not_paused();
            let caller = get_caller_address();
            let current_time = get_block_timestamp();

            // Validate vote support
            assert(
                support == VoteType::AGAINST
                    || support == VoteType::FOR
                    || support == VoteType::ABSTAIN,
                'Invalid vote type',
            );

            // Check proposal state
            let state = self._get_proposal_state_internal(proposal_id);
            assert(state == ProposalState::ACTIVE, 'Voting not active');

            // Check if already voted
            let vote_key = (proposal_id, caller);
            let existing_vote = self.votes.read(vote_key);
            let zero_address: ContractAddress = 0.try_into().unwrap();
            assert(existing_vote.voter == zero_address, 'Already voted');

            // Get voting power at proposal start
            let proposal = self.proposals.read(proposal_id);
            let voting_power = self._get_voting_power(caller, proposal.start_time);
            assert(voting_power > 0, 'No voting power');

            // Record vote
            let vote_receipt = VoteReceipt {
                voter: caller, proposal_id, support, voting_power, reason, timestamp: current_time,
            };
            self.votes.write(vote_key, vote_receipt);

            // Update proposal vote totals
            let mut updated_proposal = proposal;
            if support == VoteType::FOR {
                updated_proposal.for_votes += voting_power;
            } else if support == VoteType::AGAINST {
                updated_proposal.against_votes += voting_power;
            } else { // ABSTAIN
                updated_proposal.abstain_votes += voting_power;
            }
            self.proposals.write(proposal_id, updated_proposal);

            self.emit(VoteCast { proposal_id, voter: caller, support, voting_power, reason });
        }

        // View functions
        fn get_proposal(self: @ContractState, proposal_id: u256) -> Proposal {
            self.proposals.read(proposal_id)
        }

        fn get_proposal_actions(self: @ContractState, proposal_id: u256) -> Array<ProposalAction> {
            let proposal = self.proposals.read(proposal_id);
            let mut actions = ArrayTrait::new();
            let mut i = 0;

            loop {
                if i >= proposal.targets_count {
                    break;
                }
                let action = self.proposal_actions.read((proposal_id, i));
                actions.append(action);
                i += 1;
            };

            actions
        }

        fn get_proposal_state(self: @ContractState, proposal_id: u256) -> u8 {
            self._get_proposal_state_internal(proposal_id)
        }

        fn get_voting_power(
            self: @ContractState, account: ContractAddress, timepoint: u64,
        ) -> u256 {
            self._get_voting_power(account, timepoint)
        }

        fn get_votes(self: @ContractState, proposal_id: u256) -> (u256, u256, u256) {
            let proposal = self.proposals.read(proposal_id);
            (proposal.for_votes, proposal.against_votes, proposal.abstain_votes)
        }

        fn has_voted(self: @ContractState, proposal_id: u256, account: ContractAddress) -> bool {
            let vote = self.votes.read((proposal_id, account));
            let zero_address: ContractAddress = 0.try_into().unwrap();
            vote.voter != zero_address
        }

        // Configuration getters
        fn voting_delay(self: @ContractState) -> u64 {
            self.config.read().voting_delay
        }

        fn voting_period(self: @ContractState) -> u64 {
            self.config.read().voting_period
        }

        fn proposal_threshold(self: @ContractState) -> u256 {
            self.config.read().proposal_threshold
        }

        fn quorum(self: @ContractState, timepoint: u64) -> u256 {
            // Calculate quorum based on total supply at timepoint
            let total_supply = self._get_total_supply(timepoint);
            let config = self.config.read();
            (total_supply * config.quorum_percentage.into()) / 10000_u256
        }

        // Admin functions (only owner)
        fn set_voting_delay(ref self: ContractState, new_delay: u64) {
            self.ownable.assert_only_owner();
            let mut config = self.config.read();
            let old_delay = config.voting_delay;
            config.voting_delay = new_delay;
            self.config.write(config);

            self
                .emit(
                    ConfigurationUpdated {
                        parameter: 'voting_delay',
                        old_value: old_delay.into(),
                        new_value: new_delay.into(),
                    },
                );
        }

        fn set_voting_period(ref self: ContractState, new_period: u64) {
            self.ownable.assert_only_owner();
            let mut config = self.config.read();
            let old_period = config.voting_period;
            config.voting_period = new_period;
            self.config.write(config);

            self
                .emit(
                    ConfigurationUpdated {
                        parameter: 'voting_period',
                        old_value: old_period.into(),
                        new_value: new_period.into(),
                    },
                );
        }

        fn set_proposal_threshold(ref self: ContractState, new_threshold: u256) {
            self.ownable.assert_only_owner();
            let mut config = self.config.read();
            let old_threshold = config.proposal_threshold;
            config.proposal_threshold = new_threshold;
            self.config.write(config);

            self
                .emit(
                    ConfigurationUpdated {
                        parameter: 'proposal_threshold',
                        old_value: old_threshold,
                        new_value: new_threshold,
                    },
                );
        }

        fn set_quorum_percentage(ref self: ContractState, new_percentage: u16) {
            self.ownable.assert_only_owner();
            assert(new_percentage <= 10000, 'Invalid percentage'); // Max 100%

            let mut config = self.config.read();
            let old_percentage = config.quorum_percentage;
            config.quorum_percentage = new_percentage;
            self.config.write(config);

            self
                .emit(
                    ConfigurationUpdated {
                        parameter: 'quorum_percentage',
                        old_value: old_percentage.into(),
                        new_value: new_percentage.into(),
                    },
                );
        }
    }

    // Internal implementation
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _get_proposal_state_internal(self: @ContractState, proposal_id: u256) -> u8 {
            let proposal = self.proposals.read(proposal_id);

            // Check if proposal exists
            let zero_address: ContractAddress = 0.try_into().unwrap();
            if proposal.proposer == zero_address {
                panic!("Proposal does not exist");
            }

            if proposal.canceled {
                return ProposalState::CANCELED;
            }

            if proposal.executed {
                return ProposalState::EXECUTED;
            }

            let current_time = get_block_timestamp();

            if current_time < proposal.start_time {
                return ProposalState::PENDING;
            }

            if current_time <= proposal.end_time {
                return ProposalState::ACTIVE;
            }

            // Voting ended, check if succeeded
            let total_votes = proposal.for_votes + proposal.against_votes + proposal.abstain_votes;
            let quorum_needed = self.quorum(proposal.start_time);

            if total_votes < quorum_needed {
                return ProposalState::DEFEATED;
            }

            if proposal.for_votes > proposal.against_votes {
                if proposal.queued {
                    let config = self.config.read();
                    if current_time > proposal.queue_time
                        + config.timelock_delay
                        + (7 * 24 * 60 * 60) { // 7 days grace period
                        return ProposalState::EXPIRED;
                    }
                    return ProposalState::QUEUED;
                }
                return ProposalState::SUCCEEDED;
            }

            ProposalState::DEFEATED
        }

        fn _get_voting_power(
            self: @ContractState, account: ContractAddress, timepoint: u64,
        ) -> u256 {
            // This would call the voting token contract to get historical balance
            // For now, we'll implement a placeholder
            // TODO: Implement actual token balance query
            1000_u256 // Placeholder
        }

        fn _get_total_supply(self: @ContractState, timepoint: u64) -> u256 {
            // This would call the voting token contract to get historical total supply
            // For now, we'll implement a placeholder
            // TODO: Implement actual total supply query
            1000000_u256 // Placeholder
        }

        fn _hash_calldata(self: @ContractState, calldata: Span<felt252>) -> felt252 {
            // Simple hash implementation - in production, use a proper hash function
            let mut hash: felt252 = 0;
            let mut i = 0;
            loop {
                if i >= calldata.len() {
                    break;
                }
                hash = hash + *calldata.at(i);
                i += 1;
            };
            hash
        }

        fn _assert_not_paused(self: @ContractState) {
            assert(!self.paused.read(), 'Contract is paused');
        }
    }

    // Emergency functions
    #[abi(embed_v0)]
    impl EmergencyImpl of IEmergency<ContractState> {
        fn emergency_pause(ref self: ContractState) {
            let caller = get_caller_address();
            assert(
                caller == self.emergency_admin.read() || caller == self.ownable.owner(),
                'Not authorized',
            );
            self.paused.write(true);
            self.emit(EmergencyAction { action: 'PAUSE', admin: caller });
        }

        fn emergency_unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.paused.write(false);
            self.emit(EmergencyAction { action: 'UNPAUSE', admin: get_caller_address() });
        }

        fn set_emergency_admin(ref self: ContractState, new_admin: ContractAddress) {
            self.ownable.assert_only_owner();
            self.emergency_admin.write(new_admin);
        }
    }

    // Upgrade functionality
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
