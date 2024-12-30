const std = @import("std");

pub const ATTESTATION_SUBNET_COUNT = 64;
pub const DEPOSIT_CONTRACT_TREE_DEPTH = 32; // 2 ** 5
pub const NEXT_SYNC_COMMITTEE_DEPTH = 5;
pub const FINALIZED_ROOT_DEPTH = 6;
pub const SYNC_COMMITTEE_SUBNET_COUNT = 4;
pub const MAX_REQUEST_BLOCKS = 1024; // 2 ** 10;
pub const JUSTIFICATION_BITS_LENGTH = 4;
pub const BLOCK_BODY_EXECUTION_PAYLOAD_DEPTH = 4;
pub const MAX_REQUEST_BLOCKS_DENEB = 2 ** 7; // 128
pub const BYTES_PER_FIELD_ELEMENT = 32;

const PresetMainnet = struct {
    pub const MAX_COMMITTEES_PER_SLOT = 64;
    pub const TARGET_COMMITTEE_SIZE = 128;
    pub const MAX_VALIDATORS_PER_COMMITTEE = 2048;
    pub const SHUFFLE_ROUND_COUNT = 90;
    pub const HYSTERESIS_QUOTIENT = 4;
    pub const HYSTERESIS_DOWNWARD_MULTIPLIER = 1;
    pub const HYSTERESIS_UPWARD_MULTIPLIER = 5;
    pub const MIN_DEPOSIT_AMOUNT = 1_000_000_000;
    pub const MAX_EFFECTIVE_BALANCE = 32_000_000_000;
    pub const EFFECTIVE_BALANCE_INCREMENT = 1_000_000_000;
    pub const MIN_ATTESTATION_INCLUSION_DELAY = 1;
    pub const SLOTS_PER_EPOCH = 32;
    pub const MIN_SEED_LOOKAHEAD = 1;
    pub const MAX_SEED_LOOKAHEAD = 4;
    pub const EPOCHS_PER_ETH1_VOTING_PERIOD = 64;
    pub const SLOTS_PER_HISTORICAL_ROOT = 8192;
    pub const MIN_EPOCHS_TO_INACTIVITY_PENALTY = 4;
    pub const EPOCHS_PER_HISTORICAL_VECTOR = 65536;
    pub const EPOCHS_PER_SLASHINGS_VECTOR = 8192;
    pub const HISTORICAL_ROOTS_LIMIT = 16_777_216;
    pub const VALIDATOR_REGISTRY_LIMIT = 1_099_511_627_776;
    pub const BASE_REWARD_FACTOR = 64;
    pub const WHISTLEBLOWER_REWARD_QUOTIENT = 512;
    pub const PROPOSER_REWARD_QUOTIENT = 8;
    pub const INACTIVITY_PENALTY_QUOTIENT = 67_108_864;
    pub const MIN_SLASHING_PENALTY_QUOTIENT = 128;
    pub const PROPORTIONAL_SLASHING_MULTIPLIER = 1;
    pub const MAX_PROPOSER_SLASHINGS = 16;
    pub const MAX_ATTESTER_SLASHINGS = 2;
    pub const MAX_ATTESTATIONS = 128;
    pub const MAX_DEPOSITS = 16;
    pub const MAX_VOLUNTARY_EXITS = 16;
    pub const SYNC_COMMITTEE_SIZE = 512;
    pub const EPOCHS_PER_SYNC_COMMITTEE_PERIOD = 256;
    pub const INACTIVITY_PENALTY_QUOTIENT_ALTAIR = 50_331_648;
    pub const MIN_SLASHING_PENALTY_QUOTIENT_ALTAIR = 64;
    pub const PROPORTIONAL_SLASHING_MULTIPLIER_ALTAIR = 2;
    pub const MIN_SYNC_COMMITTEE_PARTICIPANTS = 1;
    pub const UPDATE_TIMEOUT = 8192;
    pub const INACTIVITY_PENALTY_QUOTIENT_BELLATRIX = 16_777_216;
    pub const MIN_SLASHING_PENALTY_QUOTIENT_BELLATRIX = 32;
    pub const PROPORTIONAL_SLASHING_MULTIPLIER_BELLATRIX = 3;
    pub const MAX_BYTES_PER_TRANSACTION = 1_073_741_824;
    pub const MAX_TRANSACTIONS_PER_PAYLOAD = 1_048_576;
    pub const BYTES_PER_LOGS_BLOOM = 256;
    pub const MAX_EXTRA_DATA_BYTES = 32;
    pub const MAX_BLS_TO_EXECUTION_CHANGES = 16;
    pub const MAX_WITHDRAWALS_PER_PAYLOAD = 16;
    pub const MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP = 16384;
    pub const FIELD_ELEMENTS_PER_BLOB = 4096;
    pub const MAX_BLOB_COMMITMENTS_PER_BLOCK = 4096;
    pub const MAX_BLOBS_PER_BLOCK = 6;
};

const PresetMinimal = struct {
    pub const MAX_COMMITTEES_PER_SLOT = 4;
    pub const TARGET_COMMITTEE_SIZE = 4;
    pub const MAX_VALIDATORS_PER_COMMITTEE = 2048;
    pub const SHUFFLE_ROUND_COUNT = 10;
    pub const HYSTERESIS_QUOTIENT = 4;
    pub const HYSTERESIS_DOWNWARD_MULTIPLIER = 1;
    pub const HYSTERESIS_UPWARD_MULTIPLIER = 5;
    pub const MIN_DEPOSIT_AMOUNT = 1_000_000_000;
    pub const MAX_EFFECTIVE_BALANCE = 32_000_000_000;
    pub const EFFECTIVE_BALANCE_INCREMENT = 1_000_000_000;
    pub const MIN_ATTESTATION_INCLUSION_DELAY = 1;
    pub const SLOTS_PER_EPOCH = 8;
    pub const MIN_SEED_LOOKAHEAD = 1;
    pub const MAX_SEED_LOOKAHEAD = 4;
    pub const EPOCHS_PER_ETH1_VOTING_PERIOD = 4;
    pub const SLOTS_PER_HISTORICAL_ROOT = 64;
    pub const MIN_EPOCHS_TO_INACTIVITY_PENALTY = 4;
    pub const EPOCHS_PER_HISTORICAL_VECTOR = 64;
    pub const EPOCHS_PER_SLASHINGS_VECTOR = 64;
    pub const HISTORICAL_ROOTS_LIMIT = 16_777_216;
    pub const VALIDATOR_REGISTRY_LIMIT = 1_099_511_627_776;
    pub const BASE_REWARD_FACTOR = 64;
    pub const WHISTLEBLOWER_REWARD_QUOTIENT = 512;
    pub const PROPOSER_REWARD_QUOTIENT = 8;
    pub const INACTIVITY_PENALTY_QUOTIENT = 33_554_432;
    pub const MIN_SLASHING_PENALTY_QUOTIENT = 64;
    pub const PROPORTIONAL_SLASHING_MULTIPLIER = 2;
    pub const MAX_PROPOSER_SLASHINGS = 16;
    pub const MAX_ATTESTER_SLASHINGS = 2;
    pub const MAX_ATTESTATIONS = 128;
    pub const MAX_DEPOSITS = 16;
    pub const MAX_VOLUNTARY_EXITS = 16;
    pub const SYNC_COMMITTEE_SIZE = 32;
    pub const EPOCHS_PER_SYNC_COMMITTEE_PERIOD = 8;
    pub const INACTIVITY_PENALTY_QUOTIENT_ALTAIR = 50_331_648;
    pub const MIN_SLASHING_PENALTY_QUOTIENT_ALTAIR = 64;
    pub const PROPORTIONAL_SLASHING_MULTIPLIER_ALTAIR = 2;
    pub const MIN_SYNC_COMMITTEE_PARTICIPANTS = 1;
    pub const UPDATE_TIMEOUT = 64;
    pub const INACTIVITY_PENALTY_QUOTIENT_BELLATRIX = 16_777_216;
    pub const MIN_SLASHING_PENALTY_QUOTIENT_BELLATRIX = 32;
    pub const PROPORTIONAL_SLASHING_MULTIPLIER_BELLATRIX = 3;
    pub const MAX_BYTES_PER_TRANSACTION = 1_073_741_824;
    pub const MAX_TRANSACTIONS_PER_PAYLOAD = 1_048_576;
    pub const BYTES_PER_LOGS_BLOOM = 256;
    pub const MAX_EXTRA_DATA_BYTES = 32;
    pub const MAX_BLS_TO_EXECUTION_CHANGES = 16;
    pub const MAX_WITHDRAWALS_PER_PAYLOAD = 4;
    pub const MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP = 16;
    pub const FIELD_ELEMENTS_PER_BLOB = 4;
    pub const MAX_BLOB_COMMITMENTS_PER_BLOCK = 16;
    pub const MAX_BLOBS_PER_BLOCK = 6;
};

pub fn getPreset() type {
    // TODO: get preset from environment variable

    // const env_var_name = "LODESTAR_PRESET";
    // const default_preset = "minimal";
    // const preset = try std.os.getenv[env_var_name];
    // std.process.getEnvVarOwned(allocator: Allocator, key: []const u8)
    // Determine the active preset
    // const active_preset = if (preset) |value| {
    //     if (std.mem.eql(u8, value, "mainnet")) "mainnet" else default_preset;
    // } else default_preset;

    // if (std.mem.eql(u8, active_preset, "mainnet")) {
    //     return PresetMainnet;
    // } else {
    //     return PresetMinimal;
    // }

    return PresetMinimal;
}