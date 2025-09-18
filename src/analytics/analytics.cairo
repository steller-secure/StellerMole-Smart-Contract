#[starknet::contract]
pub mod Analytics {
    use starkmole::interfaces::analytics::IAnalytics;
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        // Per day aggregates
        day_active_users: Map<u64, u32>,
        day_sessions: Map<u64, u32>,
        day_achievements: Map<u64, u32>,
        day_referrals: Map<u64, u32>,

        // Per player per day metrics
        player_day_sessions: Map<(ContractAddress, u64), u32>,
        player_day_achievements: Map<(ContractAddress, u64), u32>,
        player_day_referrals: Map<(ContractAddress, u64), u32>,

        // For DAU uniqueness: whether player was active on day
        player_day_active: Map<(ContractAddress, u64), bool>,

        // Authorization
        owner: ContractAddress,
        game_contract: ContractAddress,
        referral_contract: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SessionStarted: SessionStarted,
        SessionEnded: SessionEnded,
        AchievementLogged: AchievementLogged,
        ReferralLogged: ReferralLogged,
        GameContractUpdated: GameContractUpdated,
        ReferralContractUpdated: ReferralContractUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SessionStarted { pub player: ContractAddress, pub day: u64 }

    #[derive(Drop, starknet::Event)]
    pub struct SessionEnded { pub player: ContractAddress, pub day: u64 }

    #[derive(Drop, starknet::Event)]
    pub struct AchievementLogged { pub player: ContractAddress, pub achievement_id: felt252, pub day: u64 }

    #[derive(Drop, starknet::Event)]
    pub struct ReferralLogged { pub referrer: ContractAddress, pub referee: ContractAddress, pub day: u64 }

    #[derive(Drop, starknet::Event)]
    pub struct GameContractUpdated { pub new_address: ContractAddress }

    #[derive(Drop, starknet::Event)]
    pub struct ReferralContractUpdated { pub new_address: ContractAddress }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, game_contract: ContractAddress, referral_contract: ContractAddress) {
        self.owner.write(owner);
        self.game_contract.write(game_contract);
        self.referral_contract.write(referral_contract);
    }

    #[abi(embed_v0)]
    impl AnalyticsImpl of IAnalytics<ContractState> {
        fn log_session_start(ref self: ContractState, player: ContractAddress, day: u64) {
            Self::_require_caller(self, self.game_contract.read());
            Self::_mark_active(ref self, player, day);
            let key = (player, day);
            let current = self.player_day_sessions.read(key);
            self.player_day_sessions.write(key, current + 1);
            let day_total = self.day_sessions.read(day);
            self.day_sessions.write(day, day_total + 1);
            self.emit(SessionStarted { player, day });
        }

        fn log_session_end(ref self: ContractState, player: ContractAddress, day: u64) {
            Self::_require_caller(self, self.game_contract.read());
            // We keep an end counter by incrementing sessions as well (optional). For now, emit only.
            self.emit(SessionEnded { player, day });
        }

        fn log_achievement(ref self: ContractState, player: ContractAddress, achievement_id: felt252, day: u64) {
            Self::_require_caller(self, self.game_contract.read());
            Self::_mark_active(ref self, player, day);
            let key = (player, day);
            let current = self.player_day_achievements.read(key);
            self.player_day_achievements.write(key, current + 1);
            let day_total = self.day_achievements.read(day);
            self.day_achievements.write(day, day_total + 1);
            self.emit(AchievementLogged { player, achievement_id, day });
        }

        fn log_referral(ref self: ContractState, referrer: ContractAddress, referee: ContractAddress, day: u64) {
            Self::_require_caller(self, self.referral_contract.read());
            Self::_mark_active(ref self, referrer, day);
            let key = (referrer, day);
            let current = self.player_day_referrals.read(key);
            self.player_day_referrals.write(key, current + 1);
            let day_total = self.day_referrals.read(day);
            self.day_referrals.write(day, day_total + 1);
            self.emit(ReferralLogged { referrer, referee, day });
        }

        fn get_player_sessions(self: @ContractState, player: ContractAddress, day: u64) -> u32 {
            self.player_day_sessions.read((player, day))
        }

        fn get_player_achievements(self: @ContractState, player: ContractAddress, day: u64) -> u32 {
            self.player_day_achievements.read((player, day))
        }

        fn get_player_referrals(self: @ContractState, player: ContractAddress, day: u64) -> u32 {
            self.player_day_referrals.read((player, day))
        }

        fn get_dau(self: @ContractState, day: u64) -> u32 { self.day_active_users.read(day) }
        fn get_day_sessions(self: @ContractState, day: u64) -> u32 { self.day_sessions.read(day) }
        fn get_day_achievements(self: @ContractState, day: u64) -> u32 { self.day_achievements.read(day) }
        fn get_day_referrals(self: @ContractState, day: u64) -> u32 { self.day_referrals.read(day) }

        fn get_week_sessions(self: @ContractState, start_day: u64) -> u64 {
            let mut total: u64 = 0;
            let mut i: u64 = 0;
            while i < 7 {
                let day = start_day + i;
                total += self.day_sessions.read(day).into();
                i += 1;
            };
            total
        }

        fn get_week_dau(self: @ContractState, start_day: u64) -> u64 {
            let mut total: u64 = 0;
            let mut i: u64 = 0;
            while i < 7 {
                let day = start_day + i;
                total += self.day_active_users.read(day).into();
                i += 1;
            };
            total
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _require_caller(self: @ContractState, expected: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == expected, 'UNAUTHORIZED');
        }

        fn _mark_active(ref self: ContractState, player: ContractAddress, day: u64) {
            let key = (player, day);
            if !self.player_day_active.read(key) {
                self.player_day_active.write(key, true);
                let dau = self.day_active_users.read(day);
                self.day_active_users.write(day, dau + 1);
            }
        }

        // Admin functions
        fn set_game_contract(ref self: ContractState, new_addr: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'ONLY_OWNER');
            self.game_contract.write(new_addr);
            self.emit(GameContractUpdated { new_address: new_addr });
        }

        fn set_referral_contract(ref self: ContractState, new_addr: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'ONLY_OWNER');
            self.referral_contract.write(new_addr);
            self.emit(ReferralContractUpdated { new_address: new_addr });
        }
    }
}


