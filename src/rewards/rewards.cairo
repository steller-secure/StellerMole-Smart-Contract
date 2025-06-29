#[starknet::contract]
pub mod Rewards {
    use starkmole::interfaces::IRewards;
    use starknet::{ContractAddress, get_caller_address};
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};

    #[storage]
    struct Storage {
        pending_rewards: Map<ContractAddress, u256>,
        total_rewards_distributed: u256,
        reward_multiplier: u256,
        season_rewards: Map<u32, u256>,
        claimed_rewards: Map<ContractAddress, u256>,
        owner: ContractAddress,
        leaderboard_contract: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RewardClaimed: RewardClaimed,
        RewardsDistributed: RewardsDistributed,
        MultiplierUpdated: MultiplierUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardClaimed {
        pub player: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardsDistributed {
        pub season: u32,
        pub total_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MultiplierUpdated {
        pub old_multiplier: u256,
        pub new_multiplier: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, leaderboard_contract: ContractAddress,
    ) {
        self.owner.write(owner);
        self.leaderboard_contract.write(leaderboard_contract);
        self.reward_multiplier.write(1000000000000000000); // 1.0 in 18 decimals
    }

    #[abi(embed_v0)]
    impl RewardsImpl of IRewards<ContractState> {
        fn claim_reward(ref self: ContractState, player: ContractAddress) -> u256 {
            let caller = get_caller_address();
            assert(caller == player, 'Can only claim own rewards');

            let pending = self.pending_rewards.read(player);
            assert(pending > 0, 'No rewards to claim');

            self.pending_rewards.write(player, 0);
            let claimed = self.claimed_rewards.read(player);
            self.claimed_rewards.write(player, claimed + pending);

            // In production, transfer actual tokens here
            self.emit(RewardClaimed { player, amount: pending });

            pending
        }

        fn get_pending_rewards(self: @ContractState, player: ContractAddress) -> u256 {
            self.pending_rewards.read(player)
        }

        fn distribute_season_rewards(ref self: ContractState, season: u32) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner');

            // Dummy distribution logic
            let season_pool = self.season_rewards.read(season);
            if season_pool == 0 {
                // Set default season pool
                self.season_rewards.write(season, 1000000000000000000000); // 1000 tokens
            }

            let total_distributed = self.season_rewards.read(season);
            self
                .total_rewards_distributed
                .write(self.total_rewards_distributed.read() + total_distributed);

            self.emit(RewardsDistributed { season, total_amount: total_distributed });
        }

        fn set_reward_multiplier(ref self: ContractState, multiplier: u256) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner');

            let old_multiplier = self.reward_multiplier.read();
            self.reward_multiplier.write(multiplier);

            self.emit(MultiplierUpdated { old_multiplier, new_multiplier: multiplier });
        }
    }
}
