#[contract]
mod StarkMole {
    use starknet::ContractAddress;
    use starknet::get_block_timestamp;
    use starknet::get_caller_address;

    use src::contracts::starkmole::libraries::MoleUtils;

    struct Player {
        score: u128,
        last_active_epoch: u64,
        reward_claimed: bool,
    }

    struct Challenge {
        high_score: u128,
        top_player: ContractAddress,
        epoch_id: u64,
    }

    #[storage]
    struct Storage {
        players: LegacyMap<ContractAddress, Player>,
        current_challenge: Challenge,
        challenge_start_time: u64,
        challenge_duration: u64,
    }

    #[constructor]
    fn constructor(duration: u64) {
        challenge_duration::write(duration);
        challenge_start_time::write(get_block_timestamp());
    }

    #[external]
    fn register() {
        let caller = get_caller_address();
        assert(!players::contains(caller), 'Player already registered');

        let now = get_block_timestamp();
        let epoch = MoleUtils::get_current_epoch(now, challenge_start_time::read(), challenge_duration::read());

        let player = Player { score: 0, last_active_epoch: epoch, reward_claimed: false };
        players::write(caller, player);
    }

    #[external]
    fn submit_score(score: u128) {
        let caller = get_caller_address();
        assert(players::contains(caller), 'Not registered');

        let now = get_block_timestamp();
        let epoch = MoleUtils::get_current_epoch(now, challenge_start_time::read(), challenge_duration::read());

        let mut player = players::read(caller);
        assert(player.last_active_epoch < epoch, 'Score already submitted for this epoch');

        player.score = score;
        player.last_active_epoch = epoch;
        player.reward_claimed = false;
        players::write(caller, player);

        let mut challenge = current_challenge::read();
        if score > challenge.high_score {
            challenge.high_score = score;
            challenge.top_player = caller;
            challenge.epoch_id = epoch;
            current_challenge::write(challenge);
        }
    }

    #[external]
    fn claim_reward() {
        let caller = get_caller_address();
        let now = get_block_timestamp();
        let epoch = MoleUtils::get_current_epoch(now, challenge_start_time::read(), challenge_duration::read());

        let mut player = players::read(caller);
        let challenge = current_challenge::read();

        assert(player.last_active_epoch < epoch, 'Current challenge ongoing');
        assert(!player.reward_claimed, 'Already claimed');
        assert(challenge.top_player == caller, 'Not eligible');

        player.reward_claimed = true;
        players::write(caller, player);

        // Transfer logic or emit event here
    }

    #[view]
    fn get_leaderboard() -> (ContractAddress, u128, u64) {
        let challenge = current_challenge::read();
        return (challenge.top_player, challenge.high_score, challenge.epoch_id);
    }
}
