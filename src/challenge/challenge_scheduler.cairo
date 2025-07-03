#[starknet::contract]
pub mod ChallengeScheduler {
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starkmole::interfaces::challenge::{IChallengeScheduler, Challenge, ChallengeParticipant};

    // Challenge types constants
    pub mod ChallengeTypes {
        pub const DAILY: felt252 = 'daily';
        pub const WEEKLY: felt252 = 'weekly';
    }

    #[storage]
    struct Storage {
        // Basic contract info
        owner: ContractAddress,
        next_challenge_id: u32,
        
        // Challenge storage
        challenges: Map<u32, Challenge>,
        challenge_participants: Map<(u32, ContractAddress), ChallengeParticipant>,
        participant_exists: Map<(u32, ContractAddress), bool>,
        challenge_participant_list: Map<(u32, u32), ContractAddress>, // (challenge_id, index) -> participant
        
        // Contract integrations
        game_contract: ContractAddress,
        leaderboard_contract: ContractAddress,
        
        // Active challenges tracking
        active_challenge_count: u32,
        active_challenges: Map<u32, u32>, // index -> challenge_id
        
        // Historical tracking
        total_challenges_created: u32,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ChallengeCreated: ChallengeCreated,
        ChallengeCancelled: ChallengeCancelled,
        ParticipantJoined: ParticipantJoined,
        ParticipantLeft: ParticipantLeft,
        ScoreSubmitted: ScoreSubmitted,
        ContractUpdated: ContractUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChallengeCreated {
        #[key]
        pub challenge_id: u32,
        pub challenge_type: felt252,
        pub start_time: u64,
        pub end_time: u64,
        pub max_participants: u32,
        #[key]
        pub creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChallengeCancelled {
        #[key]
        pub challenge_id: u32,
        #[key]
        pub cancelled_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ParticipantJoined {
        #[key]
        pub challenge_id: u32,
        #[key]
        pub participant: ContractAddress,
        pub joined_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ParticipantLeft {
        #[key]
        pub challenge_id: u32,
        #[key]
        pub participant: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ScoreSubmitted {
        #[key]
        pub challenge_id: u32,
        #[key]
        pub participant: ContractAddress,
        pub score: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ContractUpdated {
        pub contract_type: felt252, // 'game' or 'leaderboard'
        pub new_address: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        game_contract: ContractAddress,
        leaderboard_contract: ContractAddress
    ) {
        self.owner.write(owner);
        self.next_challenge_id.write(1);
        self.game_contract.write(game_contract);
        self.leaderboard_contract.write(leaderboard_contract);
        self.active_challenge_count.write(0);
        self.total_challenges_created.write(0);
    }

    #[abi(embed_v0)]
    impl ChallengeSchedulerImpl of IChallengeScheduler<ContractState> {
        fn create_challenge(
            ref self: ContractState,
            challenge_type: felt252,
            start_time: u64,
            end_time: u64,
            max_participants: u32
        ) -> u32 {
            self.assert_only_owner();
            
            // Validate challenge type
            assert(
                challenge_type == ChallengeTypes::DAILY || challenge_type == ChallengeTypes::WEEKLY,
                'Invalid challenge type'
            );
            
            // Validate times
            assert(end_time > start_time, 'End time after start time');
            assert(max_participants > 0, 'Max participants > 0');
            
            let challenge_id = self.next_challenge_id.read();
            
            let challenge = Challenge {
                challenge_id,
                challenge_type,
                start_time,
                end_time,
                is_active: true, 
                participant_count: 0,
                max_participants,
            };
            
            self.challenges.write(challenge_id, challenge);
            self.next_challenge_id.write(challenge_id + 1);
            self.total_challenges_created.write(self.total_challenges_created.read() + 1);
            
            let active_count = self.active_challenge_count.read();
            self.active_challenges.write(active_count, challenge_id);
            self.active_challenge_count.write(active_count + 1);
            
            self.emit(ChallengeCreated {
                challenge_id,
                challenge_type,
                start_time,
                end_time,
                max_participants,
                creator: get_caller_address(),
            });
            
            challenge_id
        }

        fn cancel_challenge(ref self: ContractState, challenge_id: u32) {
            self.assert_only_owner();
            
            let mut challenge = self.challenges.read(challenge_id);
            assert(challenge.challenge_id != 0, 'Challenge does not exist');
            assert(challenge.is_active, 'Challenge is not active');
            
            challenge.is_active = false;
            self.challenges.write(challenge_id, challenge);
            
            // Remove from active challenges
            self._remove_from_active_challenges(challenge_id);
            
            self.emit(ChallengeCancelled {
                challenge_id,
                cancelled_by: get_caller_address(),
            });
        }

        fn join_challenge(ref self: ContractState, challenge_id: u32) {
            let participant = get_caller_address();
            let challenge = self.challenges.read(challenge_id);
            let current_time = get_block_timestamp();
            
            assert(challenge.challenge_id != 0, 'Challenge does not exist');
            assert(challenge.is_active, 'Challenge has been cancelled');
            assert(
                current_time >= challenge.start_time && current_time < challenge.end_time,
                'Invalid time window'
            );
            assert(
                challenge.participant_count < challenge.max_participants,
                'Challenge is full'
            );
            assert(
                !self.participant_exists.read((challenge_id, participant)),
                'Already participating'
            );
            
            let participant_data = ChallengeParticipant {
                challenge_id,
                participant,
                joined_at: current_time,
                score: 0,
                has_claimed_reward: false,
            };
            
            self.challenge_participants.write((challenge_id, participant), participant_data);
            self.participant_exists.write((challenge_id, participant), true);
            
            // Add to participant list
            let participant_index = challenge.participant_count;
            self.challenge_participant_list.write((challenge_id, participant_index), participant);
            
            // Update challenge participant count
            let mut updated_challenge = challenge;
            updated_challenge.participant_count += 1;
            self.challenges.write(challenge_id, updated_challenge);
            
            self.emit(ParticipantJoined {
                challenge_id,
                participant,
                joined_at: current_time,
            });
        }

        fn leave_challenge(ref self: ContractState, challenge_id: u32) {
            let participant = get_caller_address();
            let challenge = self.challenges.read(challenge_id);
            
            assert(challenge.challenge_id != 0, 'Challenge does not exist');
            assert(
                self.participant_exists.read((challenge_id, participant)),
                'Not participating'
            );
            
            // Remove participant
            self.participant_exists.write((challenge_id, participant), false);
            
            // Update challenge participant count
            let mut updated_challenge = challenge;
            updated_challenge.participant_count -= 1;
            self.challenges.write(challenge_id, updated_challenge);
            
            self.emit(ParticipantLeft {
                challenge_id,
                participant,
            });
        }

        fn submit_score(ref self: ContractState, challenge_id: u32, score: u128) {
            let participant = get_caller_address();
            let challenge = self.challenges.read(challenge_id);
            let current_time = get_block_timestamp();
            
            assert(challenge.challenge_id != 0, 'Challenge does not exist');
            assert(challenge.is_active, 'Challenge has been cancelled');
            assert(
                current_time >= challenge.start_time && current_time < challenge.end_time,
                'Invalid time window'
            );
            assert(
                self.participant_exists.read((challenge_id, participant)),
                'Not participating'
            );
            
            let mut participant_data = self.challenge_participants.read((challenge_id, participant));
            participant_data.score = score;
            self.challenge_participants.write((challenge_id, participant), participant_data);
            
            self.emit(ScoreSubmitted {
                challenge_id,
                participant,
                score,
            });
        }

        fn get_challenge(self: @ContractState, challenge_id: u32) -> Challenge {
            self.challenges.read(challenge_id)
        }

        fn get_active_challenges(self: @ContractState) -> Array<Challenge> {
            let mut active_challenges = ArrayTrait::new();
            let current_time = get_block_timestamp();
            let active_count = self.active_challenge_count.read();
            
            let mut i: u32 = 0;
            while i < active_count {
                let challenge_id = self.active_challenges.read(i);
                let challenge = self.challenges.read(challenge_id);
                
                // Check if challenge is still active
                if current_time >= challenge.start_time && current_time < challenge.end_time && challenge.is_active {
                    active_challenges.append(challenge);
                }
                i += 1;
            };
            
            active_challenges
        }

        fn get_historical_challenges(self: @ContractState, start_index: u32, count: u32) -> Array<Challenge> {
            let mut historical_challenges = ArrayTrait::new();
            let total_challenges = self.total_challenges_created.read();
            
            let mut i: u32 = start_index;
            let mut added: u32 = 0;
            
            while i < total_challenges && added < count {
                let challenge_id = i + 1; // Challenge IDs start from 1
                let challenge = self.challenges.read(challenge_id);
                
                if challenge.challenge_id != 0 {
                    historical_challenges.append(challenge);
                    added += 1;
                }
                i += 1;
            };
            
            historical_challenges
        }

        fn get_challenge_participants(self: @ContractState, challenge_id: u32) -> Array<ChallengeParticipant> {
            let mut participants = ArrayTrait::new();
            let challenge = self.challenges.read(challenge_id);
            
            let mut i: u32 = 0;
            while i < challenge.participant_count {
                let participant_address = self.challenge_participant_list.read((challenge_id, i));
                let participant_data = self.challenge_participants.read((challenge_id, participant_address));
                participants.append(participant_data);
                i += 1;
            };
            
            participants
        }

        fn is_participant(self: @ContractState, challenge_id: u32, participant: ContractAddress) -> bool {
            self.participant_exists.read((challenge_id, participant))
        }

        fn get_participant_score(self: @ContractState, challenge_id: u32, participant: ContractAddress) -> u128 {
            let participant_data = self.challenge_participants.read((challenge_id, participant));
            participant_data.score
        }

        fn is_challenge_active(self: @ContractState, challenge_id: u32) -> bool {
            let challenge = self.challenges.read(challenge_id);
            let current_time = get_block_timestamp();
            
            // A challenge is active if it's within the time window and not cancelled
            current_time >= challenge.start_time && current_time < challenge.end_time && challenge.is_active
        }

        fn get_current_time(self: @ContractState) -> u64 {
            get_block_timestamp()
        }

        fn get_next_challenge_id(self: @ContractState) -> u32 {
            self.next_challenge_id.read()
        }

        fn set_game_contract(ref self: ContractState, game_contract: ContractAddress) {
            self.assert_only_owner();
            self.game_contract.write(game_contract);
            
            self.emit(ContractUpdated {
                contract_type: 'game',
                new_address: game_contract,
            });
        }

        fn set_leaderboard_contract(ref self: ContractState, leaderboard_contract: ContractAddress) {
            self.assert_only_owner();
            self.leaderboard_contract.write(leaderboard_contract);
            
            self.emit(ContractUpdated {
                contract_type: 'leaderboard',
                new_address: leaderboard_contract,
            });
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        fn assert_only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'Only owner');
        }

        fn _remove_from_active_challenges(ref self: ContractState, challenge_id: u32) {
            let active_count = self.active_challenge_count.read();
            let mut found_index: Option<u32> = Option::None;
            
            // Find the index of the challenge to remove
            let mut i: u32 = 0;
            while i < active_count {
                if self.active_challenges.read(i) == challenge_id {
                    found_index = Option::Some(i);
                    break;
                }
                i += 1;
            };
            
            // If found, move the last element to the found position and decrease count
            if let Option::Some(index) = found_index {
                let last_index = active_count - 1;
                if index != last_index {
                    let last_challenge_id = self.active_challenges.read(last_index);
                    self.active_challenges.write(index, last_challenge_id);
                }
                self.active_challenge_count.write(last_index);
            }
        }
    }
} 