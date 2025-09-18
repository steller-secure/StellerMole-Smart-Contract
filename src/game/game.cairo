#[starknet::contract]
pub mod StarkMoleGame {
    use starkmole::interfaces::game::IStarkMoleGame;
    use starkmole::interfaces::analytics::{IAnalyticsDispatcher, IAnalyticsDispatcherTrait};
    use starkmole::interfaces::referral::{IReferralDispatcher, IReferralDispatcherTrait};
    use starkmole::utils::{calculate_score_multiplier, get_pseudo_random, is_valid_mole_position};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use core::num::traits::Zero;

    #[storage]
    struct Storage {
        game_counter: u64,
        games: Map<u64, Game>,
        player_games: Map<ContractAddress, u64>,
        player_stats: Map<ContractAddress, PlayerStats>,
        game_duration: u64,
        hit_cooldown: u64,
        owner: ContractAddress,
        referral_contract: ContractAddress,
        analytics_contract: ContractAddress,
    }

    #[derive(Drop, Serde, starknet::Store, Clone)]
    pub struct Game {
        pub player: ContractAddress,
        pub score: u64,
        pub hits: u64,
        pub misses: u64,
        pub start_time: u64,
        pub end_time: u64,
        pub current_mole_position: u8,
        pub is_active: bool,
        pub consecutive_hits: u64,
        pub last_hit_time: u64,
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct PlayerStats {
        pub total_games: u64,
        pub total_score: u64,
        pub best_score: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        GameStarted: GameStarted,
        MoleHit: MoleHit,
        MoleMissed: MoleMissed,
        GameEnded: GameEnded,
    }

    #[derive(Drop, starknet::Event)]
    pub struct GameStarted {
        pub game_id: u64,
        pub player: ContractAddress,
        pub start_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MoleHit {
        pub game_id: u64,
        pub player: ContractAddress,
        pub position: u8,
        pub score: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MoleMissed {
        pub game_id: u64,
        pub player: ContractAddress,
        pub position: u8,
    }

    #[derive(Drop, starknet::Event)]
    pub struct GameEnded {
        pub game_id: u64,
        pub player: ContractAddress,
        pub final_score: u64,
        pub total_hits: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.game_duration.write(60); // 60 seconds default
        self.hit_cooldown.write(2); // 2 seconds cooldown
    }

    #[abi(embed_v0)]
    impl StarkMoleGameImpl of IStarkMoleGame<ContractState> {
        fn start_game(ref self: ContractState) -> u64 {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            let game_id = self.game_counter.read() + 1;

            // Generate initial mole position
            let mole_position = get_pseudo_random(game_id, 9).try_into().unwrap();

            let new_game = Game {
                player: caller,
                score: 0,
                hits: 0,
                misses: 0,
                start_time: current_time,
                end_time: current_time + self.game_duration.read(),
                current_mole_position: mole_position,
                is_active: true,
                consecutive_hits: 0,
                last_hit_time: 0,
            };

            self.games.write(game_id, new_game);
            self.player_games.write(caller, game_id);
            self.game_counter.write(game_id);

            self.emit(GameStarted { game_id, player: caller, start_time: current_time });

            // Analytics: log session start if analytics is configured
            let analytics_addr = self.analytics_contract.read();
            if !analytics_addr.is_zero() {
                let analytics = IAnalyticsDispatcher { contract_address: analytics_addr };
                let day: u64 = current_time / 86400_u64;
                analytics.log_session_start(caller, day);
            }

            game_id
        }

        fn hit_mole(ref self: ContractState, game_id: u64, mole_position: u8) -> bool {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            let mut game = self.games.read(game_id);

            // Validate game state
            assert(game.player == caller, 'Not your game');
            assert(game.is_active, 'Game not active');
            assert(current_time <= game.end_time, 'Game ended');
            assert(is_valid_mole_position(mole_position), 'Invalid position');

            // Check cooldown
            if game.last_hit_time > 0 {
                assert(
                    current_time >= game.last_hit_time + self.hit_cooldown.read(),
                    'Cooldown active',
                );
            }

            let hit_success = game.current_mole_position == mole_position;

            if hit_success {
                game.hits += 1;
                game.consecutive_hits += 1;
                let multiplier = calculate_score_multiplier(game.consecutive_hits);
                game.score += 10 * multiplier;
                game.last_hit_time = current_time;

                // Generate new mole position
                game
                    .current_mole_position = get_pseudo_random(game_id + current_time, 9)
                    .try_into()
                    .unwrap();

                self
                    .emit(
                        MoleHit {
                            game_id, player: caller, position: mole_position, score: game.score,
                        },
                    );
            } else {
                game.misses += 1;
                game.consecutive_hits = 0;

                self.emit(MoleMissed { game_id, player: caller, position: mole_position });
            }

            self.games.write(game_id, game);
            hit_success
        }

        fn end_game(ref self: ContractState, game_id: u64) -> u64 {
            let caller = get_caller_address();
            let mut game = self.games.read(game_id);

            assert(game.player == caller, 'Not your game');
            assert(game.is_active, 'Game already ended');

            game.is_active = false;
            let final_score = game.score;

            // Update player stats
            let mut stats = self.player_stats.read(caller);
            let is_first_game = stats.total_games == 0;
            stats.total_games += 1;
            stats.total_score += final_score;
            if final_score > stats.best_score {
                stats.best_score = final_score;
            }

            self.games.write(game_id, game.clone());
            self.player_stats.write(caller, stats);

            // Trigger referral rewards if this is the first completed game
            if is_first_game {
                let referral_contract_addr = self.referral_contract.read();
                if !referral_contract_addr.is_zero() {
                    let referral_contract = IReferralDispatcher {
                        contract_address: referral_contract_addr,
                    };
                    // Call complete_referral with the player and their final score
                    // This will trigger rewards if the player was referred and meets minimum score
                    referral_contract.complete_referral(caller, final_score);
                }
            }

            self.emit(GameEnded { game_id, player: caller, final_score, total_hits: game.hits });

            // Analytics: log session end
            let analytics_addr = self.analytics_contract.read();
            if !analytics_addr.is_zero() {
                let analytics = IAnalyticsDispatcher { contract_address: analytics_addr };
                let day: u64 = game.end_time / 86400_u64;
                analytics.log_session_end(caller, day);
            }

            final_score
        }

        fn get_game_score(self: @ContractState, game_id: u64) -> u64 {
            let game = self.games.read(game_id);
            game.score
        }

        fn get_player_stats(self: @ContractState, player: ContractAddress) -> (u64, u64, u64) {
            let stats = self.player_stats.read(player);
            (stats.total_games, stats.total_score, stats.best_score)
        }

        fn set_referral_contract(ref self: ContractState, referral_contract: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner can set referral');
            self.referral_contract.write(referral_contract);
        }

        fn set_analytics_contract(ref self: ContractState, analytics_contract: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner can set analytics');
            self.analytics_contract.write(analytics_contract);
        }
    }
}
