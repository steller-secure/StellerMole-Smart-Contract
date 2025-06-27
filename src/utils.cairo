use starknet::{ContractAddress, get_block_timestamp};

pub fn get_pseudo_random(seed: u64, max_value: u64) -> u64 {
    let timestamp = get_block_timestamp();
    let hash_input = seed + timestamp;
    // Simple pseudo-random implementation for demo
    (hash_input * 1103515245 + 12345) % max_value
}

pub fn calculate_cooldown_end(current_time: u64, cooldown_duration: u64) -> u64 {
    current_time + cooldown_duration
}

pub fn is_valid_mole_position(position: u8) -> bool {
    position < 9 // 3x3 grid positions 0-8
}

pub fn calculate_score_multiplier(consecutive_hits: u64) -> u64 {
    if consecutive_hits >= 10 {
        3
    } else if consecutive_hits >= 5 {
        2
    } else {
        1
    }
}
