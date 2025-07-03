#[starknet::contract]
pub mod Rewards {
    use starkmole::interfaces::rewards::{IRewards};
    use starkmole::interfaces::leaderboard::{ILeaderboardDispatcher, ILeaderboardDispatcherTrait};
    use starkmole::types::{RewardTier, ChallengeCycle};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        // Core contract addresses
        owner: ContractAddress,
        leaderboard_contract: ContractAddress,
        token_address: ContractAddress,
        
        // Challenge cycle management
        challenge_cycles: Map<u32, ChallengeCycle>,
        current_cycle_id: u32,
        cycle_counter: u32,
        
        // Reward tracking
        claimed_rewards: Map<(ContractAddress, u32), bool>, // (player, cycle_id) -> claimed
        player_cycle_rewards: Map<(ContractAddress, u32), u256>, // (player, cycle_id) -> reward_amount
        cycle_claims_count: Map<u32, u32>, // cycle_id -> number_of_claims
        
        reward_tiers: Map<u32, RewardTier>, // index -> tier
        tier_count: u32,
        
        // Statistics
        total_rewards_distributed: u256,
        total_cycles_completed: u32,
        
        // Emergency controls
        paused: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RewardClaimed: RewardClaimed,
        ChallengeCycleCreated: ChallengeCycleCreated,
        ChallengeCycleFinalized: ChallengeCycleFinalized,
        RewardTiersUpdated: RewardTiersUpdated,
        EmergencyWithdrawal: EmergencyWithdrawal,
        ContractPaused: ContractPaused,
        ContractUnpaused: ContractUnpaused,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardClaimed {
        pub player: ContractAddress,
        pub cycle_id: u32,
        pub tier_name: felt252,
        pub amount: u256,
        pub rank: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChallengeCycleCreated {
        pub cycle_id: u32,
        pub start_time: u64,
        pub end_time: u64,
        pub total_pool: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChallengeCycleFinalized {
        pub cycle_id: u32,
        pub participants: u32,
        pub total_distributed: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardTiersUpdated {
        pub tier_count: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EmergencyWithdrawal {
        pub amount: u256,
        pub recipient: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContractPaused {}

    #[derive(Drop, starknet::Event)]
    pub struct ContractUnpaused {}

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        leaderboard_contract: ContractAddress,
        token_address: ContractAddress,
    ) {
        self.owner.write(owner);
        self.leaderboard_contract.write(leaderboard_contract);
        self.token_address.write(token_address);
        self.cycle_counter.write(0);
        self.current_cycle_id.write(0);
        self.paused.write(false);
        
        // Initialize default reward tiers
        self._initialize_default_tiers();
    }

    #[abi(embed_v0)]
    impl RewardsImpl of IRewards<ContractState> {
        fn claim_reward(ref self: ContractState, cycle_id: u32) -> u256 {
            self._assert_not_paused();
            let caller = get_caller_address();
            
            // Check if cycle exists and is finalized
            let cycle = self.challenge_cycles.read(cycle_id);
            assert(cycle.cycle_id != 0, 'Cycle does not exist');
            assert(cycle.is_finalized, 'Cycle not finalized');
            
            // Check if already claimed
            assert(!self.claimed_rewards.read((caller, cycle_id)), 'Already claimed');
            
            // Calculate reward amount
            let reward_amount = self.calculate_tier_rewards(cycle_id, caller);
            assert(reward_amount > 0, 'No reward eligible');
            
            // Mark as claimed
            self.claimed_rewards.write((caller, cycle_id), true);
            self.player_cycle_rewards.write((caller, cycle_id), reward_amount);
            
            // Update statistics
            let claims_count = self.cycle_claims_count.read(cycle_id);
            self.cycle_claims_count.write(cycle_id, claims_count + 1);
            self.total_rewards_distributed.write(self.total_rewards_distributed.read() + reward_amount);
            
            // Transfer tokens
            let token = IERC20Dispatcher { contract_address: self.token_address.read() };
            token.transfer(caller, reward_amount);
            
            // Get player rank and tier for event
            let leaderboard = ILeaderboardDispatcher { contract_address: self.leaderboard_contract.read() };
            let rank = leaderboard.get_player_rank(caller);
            let tier_name = self._get_tier_name_for_rank(rank);
            
            self.emit(RewardClaimed { 
                player: caller, 
                cycle_id, 
                tier_name,
                amount: reward_amount, 
                rank 
            });
            
            reward_amount
        }

        fn get_claimable_reward(self: @ContractState, player: ContractAddress, cycle_id: u32) -> u256 {
            // Check if cycle exists and is finalized
            let cycle = self.challenge_cycles.read(cycle_id);
            if cycle.cycle_id == 0 || !cycle.is_finalized {
                return 0;
            }
            
            // Check if already claimed
            if self.claimed_rewards.read((player, cycle_id)) {
                return 0;
            }
            
            self.calculate_tier_rewards(cycle_id, player)
        }

        fn has_claimed_reward(self: @ContractState, player: ContractAddress, cycle_id: u32) -> bool {
            self.claimed_rewards.read((player, cycle_id))
        }

        fn create_challenge_cycle(ref self: ContractState, start_time: u64, end_time: u64, total_pool: u256) -> u32 {
            self._assert_owner();
            assert(start_time < end_time, 'Invalid time range');
            assert(total_pool > 0, 'Pool must be positive');
            
            let cycle_id = self.cycle_counter.read() + 1;
            self.cycle_counter.write(cycle_id);
            
            let cycle = ChallengeCycle {
                cycle_id,
                start_time,
                end_time,
                total_pool,
                is_finalized: false,
                participant_count: 0,
            };
            
            self.challenge_cycles.write(cycle_id, cycle);
            self.current_cycle_id.write(cycle_id);
            
            self.emit(ChallengeCycleCreated { 
                cycle_id, 
                start_time, 
                end_time, 
                total_pool 
            });
            
            cycle_id
        }

        fn finalize_challenge_cycle(ref self: ContractState, cycle_id: u32) {
            self._assert_owner();
            
            let mut cycle = self.challenge_cycles.read(cycle_id);
            assert(cycle.cycle_id != 0, 'Cycle does not exist');
            assert(!cycle.is_finalized, 'Already finalized');
            assert(get_block_timestamp() >= cycle.end_time, 'Cycle not ended');
            
            // Get participant count from leaderboard
            let leaderboard = ILeaderboardDispatcher { contract_address: self.leaderboard_contract.read() };
            let total_players = leaderboard.get_total_players();
            
            cycle.participant_count = total_players;
            cycle.is_finalized = true;
            self.challenge_cycles.write(cycle_id, cycle);
            
            self.total_cycles_completed.write(self.total_cycles_completed.read() + 1);
            
            self.emit(ChallengeCycleFinalized { 
                cycle_id, 
                participants: total_players, 
                total_distributed: cycle.total_pool 
            });
        }

        fn get_challenge_cycle(self: @ContractState, cycle_id: u32) -> ChallengeCycle {
            self.challenge_cycles.read(cycle_id)
        }

        fn get_current_cycle(self: @ContractState) -> u32 {
            self.current_cycle_id.read()
        }

        fn set_reward_tiers(ref self: ContractState, tiers: Array<RewardTier>) {
            self._assert_owner();
            
            // Clear existing tiers by resetting count
            self.tier_count.write(0);
            
            // Add new tiers
            let mut i = 0_u32;
            let tier_array_len = tiers.len();
            while i < tier_array_len {
                let tier = *tiers.at(i);
                self.reward_tiers.write(i, tier);
                i += 1;
            };
            
            self.tier_count.write(tier_array_len);
            self.emit(RewardTiersUpdated { tier_count: tier_array_len });
        }

        fn get_reward_tiers(self: @ContractState) -> Array<RewardTier> {
            let mut result = ArrayTrait::new();
            let tier_count = self.tier_count.read();
            let mut i = 0_u32;
            
            while i < tier_count {
                let tier = self.reward_tiers.read(i);
                result.append(tier);
                i += 1;
            };
            
            result
        }

        fn calculate_tier_rewards(self: @ContractState, cycle_id: u32, player: ContractAddress) -> u256 {
            let cycle = self.challenge_cycles.read(cycle_id);
            if cycle.cycle_id == 0 {
                return 0;
            }
            
            let leaderboard = ILeaderboardDispatcher { contract_address: self.leaderboard_contract.read() };
            let player_rank = leaderboard.get_player_rank(player);
            let player_score = leaderboard.get_player_score(player);
            
            // Player must have participated (scored > 0)
            if player_score == 0 || player_rank == 0 {
                return 0;
            }
            
            let tier_count = self.tier_count.read();
            let mut i = 0_u32;
            let mut reward_amount = 0_u256;
            
            while i < tier_count {
                let tier = self.reward_tiers.read(i);
                if player_rank >= tier.min_rank && player_rank <= tier.max_rank {
                    // Calculate reward based on percentage of pool
                    reward_amount = (cycle.total_pool * tier.percentage_of_pool.into()) / 10000;
                    break;
                }
                i += 1;
            };
            
            reward_amount
        }

        fn set_token_address(ref self: ContractState, token_address: ContractAddress) {
            self._assert_owner();
            self.token_address.write(token_address);
        }

        fn emergency_withdraw(ref self: ContractState, amount: u256) {
            self._assert_owner();
            
            let token = IERC20Dispatcher { contract_address: self.token_address.read() };
            let owner = self.owner.read();
            token.transfer(owner, amount);
            
            self.emit(EmergencyWithdrawal { amount, recipient: owner });
        }

        fn update_leaderboard_contract(ref self: ContractState, new_address: ContractAddress) {
            self._assert_owner();
            self.leaderboard_contract.write(new_address);
        }

        fn get_total_rewards_distributed(self: @ContractState) -> u256 {
            self.total_rewards_distributed.read()
        }

        fn get_cycle_statistics(self: @ContractState, cycle_id: u32) -> (u32, u256, u32) {
            let cycle = self.challenge_cycles.read(cycle_id);
            let claims_count = self.cycle_claims_count.read(cycle_id);
            (cycle.participant_count, cycle.total_pool, claims_count)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_owner(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner');
        }
        
        fn _assert_not_paused(self: @ContractState) {
            assert(!self.paused.read(), 'Contract paused');
        }
        
        fn _initialize_default_tiers(ref self: ContractState) {
            // Initialize default reward tiers using Map storage
            self.reward_tiers.write(0, RewardTier {
                tier_name: 'WINNER',
                min_rank: 1,
                max_rank: 1,
                reward_amount: 0, // Will be calculated based on percentage
                percentage_of_pool: 3000, // 30%
            });
            
            self.reward_tiers.write(1, RewardTier {
                tier_name: 'RUNNER_UP',
                min_rank: 2,
                max_rank: 2,
                reward_amount: 0,
                percentage_of_pool: 1500, // 15%
            });
            
            self.reward_tiers.write(2, RewardTier {
                tier_name: 'THIRD_PLACE',
                min_rank: 3,
                max_rank: 3,
                reward_amount: 0,
                percentage_of_pool: 500, // 5%
            });
            
            // Top 10% - 30% of pool
            self.reward_tiers.write(3, RewardTier {
                tier_name: 'TOP_10_PERCENT',
                min_rank: 4,
                max_rank: 100, // Assuming max 1000 players, top 10% = top 100
                reward_amount: 0,
                percentage_of_pool: 30, // 0.3% per player (30% / 97 players)
            });
            
            // Participation reward - remaining 20%
            self.reward_tiers.write(4, RewardTier {
                tier_name: 'PARTICIPATION',
                min_rank: 101,
                max_rank: 999999, // Very high number to include all other participants
                reward_amount: 0,
                percentage_of_pool: 2, // 0.02% per player (20% distributed among participants)
            });
            
            self.tier_count.write(5);
        }
        
        fn _get_tier_name_for_rank(self: @ContractState, rank: u32) -> felt252 {
            let tier_count = self.tier_count.read();
            let mut i = 0_u32;
            let mut tier_name = 'UNKNOWN';
            
            while i < tier_count {
                let tier = self.reward_tiers.read(i);
                if rank >= tier.min_rank && rank <= tier.max_rank {
                    tier_name = tier.tier_name;
                    break;
                }
                i += 1;
            };
            
            tier_name
        }
        
        fn pause(ref self: ContractState) {
            self._assert_owner();
            self.paused.write(true);
            self.emit(ContractPaused {});
        }
        
        fn unpause(ref self: ContractState) {
            self._assert_owner();
            self.paused.write(false);
            self.emit(ContractUnpaused {});
        }
    }
}
