#[starknet::contract]
pub mod Referral {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_tx_info};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    // use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::num::traits::Zero;

    use starkmole::interfaces::referral::IReferral;
    use starkmole::interfaces::treasury::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
    use starkmole::types::{
        ReferralCode, ReferralRelationship, ReferralStats, ReferralRewardConfig,
        ReferralRewardClaim, ReferralConstants,
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // Components
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        // Referral code management
        referral_codes: Map<felt252, ReferralCode>,
        user_referral_codes: Map<(ContractAddress, u32), felt252>, // (user, index) -> code
        user_referral_codes_count: Map<ContractAddress, u32>,
        code_exists: Map<felt252, bool>,
        // Referral relationships
        referral_relationships: Map<
            ContractAddress, ReferralRelationship,
        >, // referee -> relationship
        user_referrals: Map<
            (ContractAddress, u32), ContractAddress,
        >, // (referrer, index) -> referee
        user_referrals_count: Map<ContractAddress, u32>,
        referral_stats: Map<ContractAddress, ReferralStats>,
        // Reward management
        reward_config: ReferralRewardConfig,
        reward_claims: Map<u32, ReferralRewardClaim>,
        user_reward_claims: Map<(ContractAddress, u32), u32>, // (user, index) -> claim_id
        user_reward_claims_count: Map<ContractAddress, u32>,
        pending_rewards: Map<ContractAddress, u256>,
        // Anti-abuse and security
        banned_users: Map<ContractAddress, bool>,
        last_referral_time: Map<ContractAddress, u64>,
        // Contract integrations
        game_contract: ContractAddress,
        treasury_contract: ContractAddress,
        token_contract: ContractAddress,
        // System state
        paused: bool,
        total_codes_created: u32,
        total_relationships: u32,
        total_rewards_distributed: u256,
        // Counters for unique IDs
        next_claim_id: u32,
        // Leaderboard tracking
        active_referrers: Map<u32, ContractAddress>, // index -> referrer address
        active_referrers_count: u32,
        referrer_index: Map<ContractAddress, u32> // referrer -> index in active_referrers
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        ReferralCodeCreated: ReferralCodeCreated,
        ReferralCodeDeactivated: ReferralCodeDeactivated,
        ReferralRegistered: ReferralRegistered,
        ReferralCompleted: ReferralCompleted,
        RewardsDistributed: RewardsDistributed,
        RewardsClaimed: RewardsClaimed,
        UserBanned: UserBanned,
        UserUnbanned: UserUnbanned,
        SystemPaused: SystemPaused,
        SystemUnpaused: SystemUnpaused,
        ConfigUpdated: ConfigUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ReferralCodeCreated {
        #[key]
        pub code: felt252,
        #[key]
        pub creator: ContractAddress,
        pub max_uses: u32,
        pub expiry_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ReferralCodeDeactivated {
        #[key]
        pub code: felt252,
        #[key]
        pub deactivator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ReferralRegistered {
        #[key]
        pub referrer: ContractAddress,
        #[key]
        pub referee: ContractAddress,
        pub referral_code: felt252,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ReferralCompleted {
        #[key]
        pub referrer: ContractAddress,
        #[key]
        pub referee: ContractAddress,
        pub game_score: u64,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardsDistributed {
        #[key]
        pub referrer: ContractAddress,
        #[key]
        pub referee: ContractAddress,
        pub referrer_reward: u256,
        pub referee_reward: u256,
        pub claim_id: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardsClaimed {
        #[key]
        pub claimer: ContractAddress,
        pub amount: u256,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct UserBanned {
        #[key]
        pub user: ContractAddress,
        #[key]
        pub admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct UserUnbanned {
        #[key]
        pub user: ContractAddress,
        #[key]
        pub admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SystemPaused {
        #[key]
        pub admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SystemUnpaused {
        #[key]
        pub admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ConfigUpdated {
        #[key]
        pub admin: ContractAddress,
        pub referrer_reward: u256,
        pub referee_reward: u256,
        pub min_game_score: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        game_contract: ContractAddress,
        treasury_contract: ContractAddress,
        token_contract: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.game_contract.write(game_contract);
        self.treasury_contract.write(treasury_contract);
        self.token_contract.write(token_contract);

        // Initialize default reward configuration
        let default_config = ReferralRewardConfig {
            referrer_reward: ReferralConstants::DEFAULT_REFERRER_REWARD,
            referee_reward: ReferralConstants::DEFAULT_REFEREE_REWARD,
            min_game_score: ReferralConstants::DEFAULT_MIN_SCORE,
            reward_delay: ReferralConstants::DEFAULT_REWARD_DELAY,
            is_active: true,
        };
        self.reward_config.write(default_config);

        self.paused.write(false);
        self.next_claim_id.write(1);
        self.total_codes_created.write(0);
        self.total_relationships.write(0);
        self.total_rewards_distributed.write(0);
    }

    #[abi(embed_v0)]
    impl ReferralImpl of IReferral<ContractState> {
        // Referral Code Management
        fn create_referral_code(
            ref self: ContractState, code: felt252, max_uses: u32, expiry_time: u64,
        ) -> bool {
            self._assert_not_paused();
            let caller = get_caller_address();
            assert!(!self.banned_users.read(caller), "User is banned");
            assert!(!self.code_exists.read(code), "Code already exists");
            assert!(
                max_uses > 0 && max_uses <= ReferralConstants::MAX_CODE_USES, "Invalid max uses",
            );

            let current_time = get_block_timestamp();
            let final_expiry = if expiry_time == 0 {
                current_time + ReferralConstants::DEFAULT_CODE_EXPIRY
            } else {
                expiry_time
            };

            let referral_code = ReferralCode {
                code,
                referrer: caller,
                created_at: current_time,
                is_active: true,
                max_uses,
                current_uses: 0,
                expiry_time: final_expiry,
            };

            self.referral_codes.write(code, referral_code);
            self.code_exists.write(code, true);

            // Add to user's referral codes list
            let user_codes_count = self.user_referral_codes_count.read(caller);
            self.user_referral_codes.write((caller, user_codes_count), code);
            self.user_referral_codes_count.write(caller, user_codes_count + 1);

            // Update counters
            let total_codes = self.total_codes_created.read() + 1;
            self.total_codes_created.write(total_codes);

            self
                .emit(
                    ReferralCodeCreated {
                        code, creator: caller, max_uses, expiry_time: final_expiry,
                    },
                );

            true
        }

        fn deactivate_referral_code(ref self: ContractState, code: felt252) {
            self._assert_not_paused();
            let caller = get_caller_address();
            let mut referral_code = self.referral_codes.read(code);

            // Only owner or code creator can deactivate
            assert!(
                caller == self.ownable.owner() || caller == referral_code.referrer,
                "Not authorized to deactivate code",
            );
            assert!(referral_code.is_active, "Code already inactive");

            referral_code.is_active = false;
            self.referral_codes.write(code, referral_code);

            self.emit(ReferralCodeDeactivated { code, deactivator: caller });
        }

        fn update_referral_code(
            ref self: ContractState, code: felt252, max_uses: u32, expiry_time: u64,
        ) {
            self._assert_not_paused();
            let caller = get_caller_address();
            let mut referral_code = self.referral_codes.read(code);

            assert!(caller == referral_code.referrer, "Not code owner");
            assert!(referral_code.is_active, "Code is inactive");
            assert!(max_uses >= referral_code.current_uses, "Max uses too low");

            referral_code.max_uses = max_uses;
            if expiry_time > 0 {
                referral_code.expiry_time = expiry_time;
            }

            self.referral_codes.write(code, referral_code);
        }

        fn get_referral_code(self: @ContractState, code: felt252) -> ReferralCode {
            self.referral_codes.read(code)
        }

        fn is_code_valid(self: @ContractState, code: felt252) -> bool {
            let referral_code = self.referral_codes.read(code);
            if !referral_code.is_active {
                return false;
            }

            let current_time = get_block_timestamp();
            if referral_code.expiry_time > 0 && current_time > referral_code.expiry_time {
                return false;
            }

            if referral_code.current_uses >= referral_code.max_uses {
                return false;
            }

            true
        }

        // Referral Registration and Tracking
        fn register_with_referral_code(ref self: ContractState, referral_code: felt252) -> bool {
            self._assert_not_paused();
            let caller = get_caller_address();
            assert!(!self.banned_users.read(caller), "User is banned");
            assert!(!self.has_referrer(caller), "User already has referrer");
            assert!(self.is_code_valid(referral_code), "Invalid referral code");

            let mut code_data = self.referral_codes.read(referral_code);
            let referrer = code_data.referrer;

            // Prevent self-referral
            assert!(referrer != caller, "Cannot refer yourself");

            // Check cooldown for referrer
            assert!(self.check_referral_cooldown(referrer), "Referrer in cooldown");

            let current_time = get_block_timestamp();

            // Create referral relationship
            let relationship = ReferralRelationship {
                referrer,
                referee: caller,
                referral_code,
                timestamp: current_time,
                rewards_claimed: false,
                first_game_completed: false,
            };

            self.referral_relationships.write(caller, relationship);

            // Update referrer's referral list
            let referrer_referrals_count = self.user_referrals_count.read(referrer);
            self.user_referrals.write((referrer, referrer_referrals_count), caller);
            self.user_referrals_count.write(referrer, referrer_referrals_count + 1);

            // Update referrer stats
            let mut referrer_stats = self.referral_stats.read(referrer);
            referrer_stats.total_referrals += 1;
            referrer_stats.last_referral_time = current_time;
            self.referral_stats.write(referrer, referrer_stats);

            // Add referrer to active referrers list for leaderboard tracking
            self._add_to_active_referrers(referrer);

            // Update code usage
            code_data.current_uses += 1;
            self.referral_codes.write(referral_code, code_data);

            // Update last referral time for cooldown
            self.last_referral_time.write(referrer, current_time);

            // Update total relationships counter
            let total_relationships = self.total_relationships.read() + 1;
            self.total_relationships.write(total_relationships);

            self
                .emit(
                    ReferralRegistered {
                        referrer, referee: caller, referral_code, timestamp: current_time,
                    },
                );

            true
        }

        fn complete_referral(
            ref self: ContractState, referee: ContractAddress, game_score: u64,
        ) -> bool {
            self._assert_not_paused();
            let caller = get_caller_address();

            // Only game contract can call this
            assert!(
                caller == self.game_contract.read(), "Only game contract can complete referrals",
            );

            if !self.has_referrer(referee) {
                return false;
            }

            let mut relationship = self.referral_relationships.read(referee);
            if relationship.first_game_completed {
                return false;
            }

            let config = self.reward_config.read();

            // Mark as completed
            relationship.first_game_completed = true;
            self.referral_relationships.write(referee, relationship);

            // Update referrer stats
            let referrer = relationship.referrer;
            let mut referrer_stats = self.referral_stats.read(referrer);

            // Only count as successful and give rewards if score meets minimum and config is active
            let meets_requirements = config.is_active && game_score >= config.min_game_score;
            if meets_requirements {
                referrer_stats.successful_referrals += 1;
            }
            self.referral_stats.write(referrer, referrer_stats);

            // Distribute rewards after delay only if requirements are met
            let current_time = get_block_timestamp();
            if meets_requirements {
                if config.reward_delay == 0 {
                    self._distribute_referral_rewards_internal(referrer, referee);
                } else {
                    // Add to pending rewards for later claim
                    let (referrer_reward, referee_reward) = self
                        .calculate_referral_rewards(referrer, referee);

                    let mut referrer_pending = self.pending_rewards.read(referrer);
                    referrer_pending += referrer_reward;
                    self.pending_rewards.write(referrer, referrer_pending);

                    let mut referee_pending = self.pending_rewards.read(referee);
                    referee_pending += referee_reward;
                    self.pending_rewards.write(referee, referee_pending);
                }
            }

            self.emit(ReferralCompleted { referrer, referee, game_score, timestamp: current_time });

            true
        }

        fn get_user_referral_relationship(
            self: @ContractState, referee: ContractAddress,
        ) -> ReferralRelationship {
            self.referral_relationships.read(referee)
        }

        fn has_referrer(self: @ContractState, referee: ContractAddress) -> bool {
            let relationship = self.referral_relationships.read(referee);
            !relationship.referrer.is_zero()
        }

        fn get_referrer(self: @ContractState, referee: ContractAddress) -> ContractAddress {
            let relationship = self.referral_relationships.read(referee);
            relationship.referrer
        }

        // Referral Statistics
        fn get_user_stats(self: @ContractState, user: ContractAddress) -> ReferralStats {
            self.referral_stats.read(user)
        }

        fn get_total_referrals(self: @ContractState, referrer: ContractAddress) -> u32 {
            let stats = self.referral_stats.read(referrer);
            stats.total_referrals
        }

        fn get_successful_referrals(self: @ContractState, referrer: ContractAddress) -> u32 {
            let stats = self.referral_stats.read(referrer);
            stats.successful_referrals
        }

        fn get_pending_rewards(self: @ContractState, user: ContractAddress) -> u256 {
            self.pending_rewards.read(user)
        }

        fn get_user_referral_codes(self: @ContractState, user: ContractAddress) -> Array<felt252> {
            let mut result = ArrayTrait::new();
            let codes_count = self.user_referral_codes_count.read(user);
            let mut i = 0;
            while i < codes_count {
                let code = self.user_referral_codes.read((user, i));
                result.append(code);
                i += 1;
            };
            result
        }

        // Reward Management
        fn claim_referral_rewards(ref self: ContractState) -> u256 {
            self.reentrancy_guard.start();
            self._assert_not_paused();
            let caller = get_caller_address();

            let pending_amount = self.pending_rewards.read(caller);
            assert!(pending_amount > 0, "No pending rewards");

            // Clear pending rewards
            self.pending_rewards.write(caller, 0);

            // Transfer tokens from treasury
            let treasury = ITreasuryDispatcher { contract_address: self.treasury_contract.read() };

            // Withdraw from treasury and transfer to user
            treasury.withdraw_from_pool('REWARDS_POOL', pending_amount, caller);

            let current_time = get_block_timestamp();
            self
                .emit(
                    RewardsClaimed {
                        claimer: caller, amount: pending_amount, timestamp: current_time,
                    },
                );

            self.reentrancy_guard.end();
            pending_amount
        }

        fn calculate_referral_rewards(
            self: @ContractState, referrer: ContractAddress, referee: ContractAddress,
        ) -> (u256, u256) {
            let config = self.reward_config.read();
            (config.referrer_reward, config.referee_reward)
        }

        fn distribute_referral_rewards(
            ref self: ContractState, referrer: ContractAddress, referee: ContractAddress,
        ) -> u32 {
            self._assert_not_paused();
            let caller = get_caller_address();
            assert!(
                caller == self.ownable.owner() || caller == self.game_contract.read(),
                "Not authorized",
            );

            self._distribute_referral_rewards_internal(referrer, referee)
        }

        fn get_reward_claim(self: @ContractState, claim_id: u32) -> ReferralRewardClaim {
            self.reward_claims.read(claim_id)
        }

        fn get_user_reward_claims(
            self: @ContractState, user: ContractAddress,
        ) -> Array<ReferralRewardClaim> {
            let mut result = ArrayTrait::new();
            let claims_count = self.user_reward_claims_count.read(user);
            let mut i = 0;
            while i < claims_count {
                let claim_id = self.user_reward_claims.read((user, i));
                let claim = self.reward_claims.read(claim_id);
                result.append(claim);
                i += 1;
            };
            result
        }

        // Configuration Management
        fn set_reward_config(ref self: ContractState, config: ReferralRewardConfig) {
            self.ownable.assert_only_owner();
            self.reward_config.write(config);

            self
                .emit(
                    ConfigUpdated {
                        admin: get_caller_address(),
                        referrer_reward: config.referrer_reward,
                        referee_reward: config.referee_reward,
                        min_game_score: config.min_game_score,
                    },
                );
        }

        fn get_reward_config(self: @ContractState) -> ReferralRewardConfig {
            self.reward_config.read()
        }

        fn update_reward_amounts(
            ref self: ContractState, referrer_reward: u256, referee_reward: u256,
        ) {
            self.ownable.assert_only_owner();
            let mut config = self.reward_config.read();
            config.referrer_reward = referrer_reward;
            config.referee_reward = referee_reward;
            self.reward_config.write(config);
        }

        fn update_min_score_requirement(ref self: ContractState, min_score: u64) {
            self.ownable.assert_only_owner();
            let mut config = self.reward_config.read();
            config.min_game_score = min_score;
            self.reward_config.write(config);
        }

        // Integration Functions
        fn set_game_contract(ref self: ContractState, game_contract: ContractAddress) {
            self.ownable.assert_only_owner();
            self.game_contract.write(game_contract);
        }

        fn set_treasury_contract(ref self: ContractState, treasury_contract: ContractAddress) {
            self.ownable.assert_only_owner();
            self.treasury_contract.write(treasury_contract);
        }

        fn set_token_contract(ref self: ContractState, token_contract: ContractAddress) {
            self.ownable.assert_only_owner();
            self.token_contract.write(token_contract);
        }

        fn get_game_contract(self: @ContractState) -> ContractAddress {
            self.game_contract.read()
        }

        fn get_treasury_contract(self: @ContractState) -> ContractAddress {
            self.treasury_contract.read()
        }

        fn get_token_contract(self: @ContractState) -> ContractAddress {
            self.token_contract.read()
        }

        // Anti-abuse and Security
        fn is_self_referral(
            self: @ContractState, referrer: ContractAddress, referee: ContractAddress,
        ) -> bool {
            referrer == referee
        }

        fn check_referral_cooldown(self: @ContractState, user: ContractAddress) -> bool {
            let last_time = self.last_referral_time.read(user);
            let current_time = get_block_timestamp();
            current_time >= last_time + ReferralConstants::ANTI_SPAM_COOLDOWN
        }

        fn get_last_referral_time(self: @ContractState, user: ContractAddress) -> u64 {
            self.last_referral_time.read(user)
        }

        fn ban_user(ref self: ContractState, user: ContractAddress) {
            self.ownable.assert_only_owner();
            self.banned_users.write(user, true);

            self.emit(UserBanned { user, admin: get_caller_address() });
        }

        fn unban_user(ref self: ContractState, user: ContractAddress) {
            self.ownable.assert_only_owner();
            self.banned_users.write(user, false);

            self.emit(UserUnbanned { user, admin: get_caller_address() });
        }

        fn is_user_banned(self: @ContractState, user: ContractAddress) -> bool {
            self.banned_users.read(user)
        }

        // Admin Functions
        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            self.ownable.transfer_ownership(new_owner);
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }

        fn pause_system(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.paused.write(true);

            self.emit(SystemPaused { admin: get_caller_address() });
        }

        fn unpause_system(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.paused.write(false);

            self.emit(SystemUnpaused { admin: get_caller_address() });
        }

        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }

        fn emergency_withdraw(ref self: ContractState, amount: u256) {
            self.ownable.assert_only_owner();
            let treasury = ITreasuryDispatcher { contract_address: self.treasury_contract.read() };
            treasury.emergency_withdraw_all(self.ownable.owner());
        }

        // Analytics and Metrics
        fn get_total_referral_codes_created(self: @ContractState) -> u32 {
            self.total_codes_created.read()
        }

        fn get_total_referral_relationships(self: @ContractState) -> u32 {
            self.total_relationships.read()
        }

        fn get_total_rewards_distributed(self: @ContractState) -> u256 {
            self.total_rewards_distributed.read()
        }

        // Bulk Operations
        fn batch_create_referral_codes(
            ref self: ContractState,
            codes: Array<felt252>,
            max_uses: Array<u32>,
            expiry_times: Array<u64>,
        ) -> Array<bool> {
            self.ownable.assert_only_owner();
            let mut results = ArrayTrait::new();
            let len = codes.len();
            assert!(len == max_uses.len() && len == expiry_times.len(), "Array length mismatch");

            let mut i = 0;
            while i < len {
                let success = self
                    .create_referral_code(*codes.at(i), *max_uses.at(i), *expiry_times.at(i));
                results.append(success);
                i += 1;
            };

            results
        }

        fn batch_deactivate_referral_codes(ref self: ContractState, codes: Array<felt252>) {
            self.ownable.assert_only_owner();
            let len = codes.len();
            let mut i = 0;
            while i < len {
                self.deactivate_referral_code(*codes.at(i));
                i += 1;
            };
        }

        fn get_user_referrals(
            self: @ContractState, user: ContractAddress,
        ) -> Array<ContractAddress> {
            let mut referrals = array![];
            let count = self.user_referrals_count.read(user);
            let mut i = 0;
            while i < count {
                let referee = self.user_referrals.read((user, i));
                referrals.append(referee);
                i += 1;
            };
            referrals
        }

        fn get_system_totals(self: @ContractState) -> (u32, u32, u256) {
            (
                self.get_total_referral_codes_created(),
                self.get_total_referral_relationships(),
                self.get_total_rewards_distributed(),
            )
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_not_paused(self: @ContractState) {
            assert!(!self.paused.read(), "Referral system is paused");
        }

        fn _add_to_active_referrers(ref self: ContractState, referrer: ContractAddress) {
            let existing_index = self.referrer_index.read(referrer);
            if existing_index == 0 && self.active_referrers.read(0) != referrer {
                let count = self.active_referrers_count.read();
                self.active_referrers.write(count, referrer);
                self.referrer_index.write(referrer, count);
                self.active_referrers_count.write(count + 1);
            }
        }

        fn _distribute_referral_rewards_internal(
            ref self: ContractState, referrer: ContractAddress, referee: ContractAddress,
        ) -> u32 {
            let (referrer_reward, referee_reward) = self
                .calculate_referral_rewards(referrer, referee);

            let claim_id = self.next_claim_id.read();
            self.next_claim_id.write(claim_id + 1);

            let current_time = get_block_timestamp();
            let tx_info = get_tx_info().unbox();

            let claim = ReferralRewardClaim {
                claim_id,
                referrer,
                referee,
                referrer_amount: referrer_reward,
                referee_amount: referee_reward,
                claimed_at: current_time,
                transaction_hash: tx_info.transaction_hash,
            };

            self.reward_claims.write(claim_id, claim);

            // Add to user reward claims
            let referrer_claims_count = self.user_reward_claims_count.read(referrer);
            self.user_reward_claims.write((referrer, referrer_claims_count), claim_id);
            self.user_reward_claims_count.write(referrer, referrer_claims_count + 1);

            let referee_claims_count = self.user_reward_claims_count.read(referee);
            self.user_reward_claims.write((referee, referee_claims_count), claim_id);
            self.user_reward_claims_count.write(referee, referee_claims_count + 1);

            // Update pending rewards for immediate claim
            let mut referrer_pending = self.pending_rewards.read(referrer);
            referrer_pending += referrer_reward;
            self.pending_rewards.write(referrer, referrer_pending);

            let mut referee_pending = self.pending_rewards.read(referee);
            referee_pending += referee_reward;
            self.pending_rewards.write(referee, referee_pending);

            // Update total rewards distributed
            let total_distributed = self.total_rewards_distributed.read()
                + referrer_reward
                + referee_reward;
            self.total_rewards_distributed.write(total_distributed);

            // Update referrer stats
            let mut referrer_stats = self.referral_stats.read(referrer);
            referrer_stats.total_rewards_earned += referrer_reward;
            referrer_stats.pending_rewards += referrer_reward;
            self.referral_stats.write(referrer, referrer_stats);

            self
                .emit(
                    RewardsDistributed {
                        referrer, referee, referrer_reward, referee_reward, claim_id,
                    },
                );

            claim_id
        }
    }
}
