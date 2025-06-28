#[starknet::contract]
pub mod Leaderboard {
    use starkmole::interfaces::ILeaderboard;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use core::num::traits::Zero;

    #[storage]
    struct Storage {
        scores: Map<ContractAddress, u64>,
        player_ranks: Map<ContractAddress, u32>,
        top_players: Map<u32, ContractAddress>, // rank -> player
        total_players: u32,
        current_season: u32,
        season_winners: Map<u32, ContractAddress>,
        season_end_time: Map<u32, u64>,
        owner: ContractAddress,
        game_contract: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ScoreSubmitted: ScoreSubmitted,
        NewSeasonStarted: NewSeasonStarted,
        SeasonEnded: SeasonEnded,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ScoreSubmitted {
        pub player: ContractAddress,
        pub score: u64,
        pub new_rank: u32,
        pub season: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct NewSeasonStarted {
        pub season: u32,
        pub start_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SeasonEnded {
        pub season: u32,
        pub winner: ContractAddress,
        pub winning_score: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, game_contract: ContractAddress,
    ) {
        self.owner.write(owner);
        self.game_contract.write(game_contract);
        self.current_season.write(1);
        self.season_end_time.write(1, get_block_timestamp() + 604800); // 7 days
    }

    #[abi(embed_v0)]
    impl LeaderboardImpl of ILeaderboard<ContractState> {
        fn submit_score(ref self: ContractState, player: ContractAddress, score: u64) {
            let caller = get_caller_address();
            assert(caller == self.game_contract.read(), 'Only game contract');

            let current_season = self.current_season.read();
            let current_score = self.scores.read(player);

            // Only update if new score is better
            if score > current_score {
                self.scores.write(player, score);

                // Update rankings (simplified implementation)
                let current_rank = self._calculate_rank(player, score);
                self.player_ranks.write(player, current_rank);

                if current_rank <= 10 {
                    self.top_players.write(current_rank, player);
                }

                self
                    .emit(
                        ScoreSubmitted {
                            player, score, new_rank: current_rank, season: current_season,
                        },
                    );
            }
        }

        fn get_top_players(self: @ContractState, limit: u32) -> Array<(ContractAddress, u64)> {
            let mut result = ArrayTrait::new();
            let mut i = 1_u32;

            while i <= limit && i <= 10 {
                let player = self.top_players.read(i);
                if !player.is_zero() {
                    let score = self.scores.read(player);
                    result.append((player, score));
                }
                i += 1;
            };

            result
        }

        fn get_player_rank(self: @ContractState, player: ContractAddress) -> u32 {
            self.player_ranks.read(player)
        }

        fn get_season_winner(self: @ContractState, season: u32) -> ContractAddress {
            self.season_winners.read(season)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _calculate_rank(self: @ContractState, player: ContractAddress, score: u64) -> u32 {
            // Simplified ranking calculation
            // In production, this would be more sophisticated
            let mut rank = 1_u32;
            let mut i = 1_u32;

            while i <= 10 {
                let top_player = self.top_players.read(i);
                if !top_player.is_zero() {
                    let top_score = self.scores.read(top_player);
                    if score <= top_score {
                        rank += 1;
                    }
                }
                i += 1;
            };

            rank
        }
    }
}
