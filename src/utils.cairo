use starknet::get_block_timestamp;

// Returns a pseudo-random number based on the current block timestamp and a seed
pub fn get_pseudo_random(seed: u64, max_value: u64) -> u64 {
    let timestamp = get_block_timestamp();
    let hash_input = seed + timestamp;
    // Simple pseudo-random implementation for demo
    (hash_input * 1103515245 + 12345) % max_value
}

// Calculates the end of a cooldown period
pub fn calculate_cooldown_end(current_time: u64, cooldown_duration: u64) -> u64 {
    current_time + cooldown_duration
}

// Validates whether the mole position is within the valid 3x3 grid
pub fn is_valid_mole_position(position: u8) -> bool {
    position < 9 // 3x3 grid positions 0-8
}

// Calculates a score multiplier based on the number of consecutive hits
pub fn calculate_score_multiplier(consecutive_hits: u64) -> u64 {
    if consecutive_hits >= 10 {
        3
    } else if consecutive_hits >= 5 {
        2
    } else {
        1
    }
}

// Utility module for epoch calculations
pub mod MoleUtils {
    pub fn get_current_epoch(now: u64, start: u64, duration: u64) -> u64 {
        (now - start) / duration
    }
}
