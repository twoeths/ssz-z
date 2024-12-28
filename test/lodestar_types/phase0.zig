const std = @import("std");
const Allocator = std.mem.Allocator;
const p = @import("./primitive.zig");
const ssz = @import("ssz");
const sha256Hash = @import("hash").sha256Hash;
const param = @import("./param.zig");
const getPreset = @import("./param.zig").getPreset;
const preset = getPreset();

/// SF stands for ssz_fields

// Misc types
// ==========
const AttestationSubnetsSSZ = ssz.createBitVectorType(param.ATTESTATION_SUBNET_COUNT);

/// BeaconBlockHeader where slot is bounded by the clock, and values above it are invalid
const BeaconBlockHeaderSF = struct {
    slot: p.Slot,
    proposer_index: p.ValidatorIndex,
    parent_root: p.Root,
    state_root: p.Root,
    body_root: p.Root,
};
const BeaconBlockHeaderSSZ = ssz.createContainerType(BeaconBlockHeaderSF, sha256Hash);

const SignedBeaconBlockHeaderSF = struct {
    message: BeaconBlockHeaderSSZ,
    signature: p.BLSSignature,
};
const SignedBeaconBlockHeaderSSZ = ssz.createContainerType(SignedBeaconBlockHeaderSF, sha256Hash);

const CheckpointSF = struct {
    epoch: p.Epoch,
    root: p.Root,
};
const CheckpointSSZ = ssz.createContainerType(CheckpointSF, sha256Hash);

const CommitteeBitsSSZ = ssz.createBitListType(preset.MAX_VALIDATORS_PER_COMMITTEE);
const CommitteeIndicesSSZ = ssz.createListBasicType(p.ValidatorIndex);

const DepositMessageSF = struct {
    pubkey: p.BLSPubkey,
    withdrawal_credentials: p.Root,
    amount: p.Uint64,
};
const DepositMessageSSZ = ssz.createContainerType(DepositMessageSF, sha256Hash);

const DepositDataSF = struct {
    pubkey: p.BLSPubkey,
    withdrawal_credentials: p.Bytes32,
    amount: p.Uint64,
    signature: p.BLSSignature,
};
const DepositDataSSZ = ssz.createContainerType(DepositDataSF, sha256Hash);

const DepositDataRootFullListSSZ = ssz.createListCompositeType(p.Root);

const DepositEventSF = struct {
    deposit_data: DepositDataSSZ,
    block_number: p.Uint64,
    index: p.Uint64,
};
const DepositEventSSZ = ssz.createContainerType(DepositEventSF, sha256Hash);

const Eth1DataSF = struct {
    deposit_root: p.Root,
    deposit_count: p.Uint64,
    block_hash: p.Bytes32,
};
const Eth1DataSSZ = ssz.createContainerType(Eth1DataSF, sha256Hash);

const Eth1DataVotesSSZ = ssz.createListCompositeType(Eth1DataSSZ);

const Eth1DataOrderedSF = struct {
    deposit_root: p.Root,
    deposit_count: p.Uint64,
    block_hash: p.Bytes32,
    block_number: p.Uint64,
};
const Eth1DataOrderedSSZ = ssz.createContainerType(Eth1DataOrderedSF, sha256Hash);

// TODO DepositsDataSnapshot

/// Spec'ed but only used in lodestar as a type
const Eth1BlockSF = struct {
    timestamp: p.Uint64,
    deposit_root: p.Root,
    deposit_count: p.Uint64,
};
const Eth1BlockSSZ = ssz.createContainerType(Eth1BlockSF, sha256Hash);

const ForkSF = struct {
    previous_version: p.Version,
    current_version: p.Version,
    epoch: p.Epoch,
};
const ForkSSZ = ssz.createContainerType(ForkSF, sha256Hash);

const ForkDataSF = struct {
    current_version: p.Version,
    genesis_validators_root: p.Root,
};
const ForkDataSSZ = ssz.createContainerType(ForkDataSF, sha256Hash);

const ENRForkIDSF = struct {
    fork_digest: p.ForkDigest,
    next_fork_version: p.Version,
    next_fork_epoch: p.Epoch,
};
const ENRForkIDSSZ = ssz.createContainerType(ENRForkIDSF, sha256Hash);

const HistoricalBlockRootsSSZ = ssz.createListCompositeType(p.Root);

const HistoricalStateRootsSSZ = ssz.createListCompositeType(p.Root);

const HistoricalBatchSF = struct {
    block_roots: HistoricalBlockRootsSSZ,
    state_roots: HistoricalStateRootsSSZ,
};
const HistoricalBatchSSZ = ssz.createContainerType(HistoricalBatchSF, sha256Hash);

const HistoricalBatchRootsSF = struct {
    block_roots: HistoricalBlockRootsSSZ,
    state_roots: HistoricalStateRootsSSZ,
};
const HistoricalBatchRootsSSZ = ssz.createContainerType(HistoricalBatchRootsSF, sha256Hash);

const ValidatorSF = struct {
    pubkey: p.BLSPubkey,
    withdrawal_credentials: p.Root,
    effective_balance: p.Gwei,
    slashed: p.Boolean,
    activation_eligibility_epoch: p.Epoch,
    activation_epoch: p.Epoch,
    exit_epoch: p.Epoch,
    withdrawable_epoch: p.Epoch,
};
const ValidatorSSZ = ssz.createContainerType(ValidatorSF, sha256Hash);

const ValidatorsSSZ = ssz.createListCompositeType(ValidatorSSZ);

const BalancesSSZ = ssz.createListBasicType(p.Gwei);

const RandaoMixesSSZ = ssz.createVectorCompositeType(p.Bytes32);

const SlashingsSSZ = ssz.createVectorBasicType(p.Gwei);

const JustificationBitsSSZ = ssz.createBitVectorType(param.JUSTIFICATION_BITS_LENGTH);

const AttestationDataSF = struct {
    slot: p.Slot,
    index: p.CommitteeIndex,
    beacon_block_root: p.Root,
    source: CheckpointSSZ,
    target: CheckpointSSZ,
};

const AttestationDataSSZ = ssz.createContainerType(AttestationDataSF, sha256Hash);

const IndexedAttestationSF = struct {
    attesting_indices: CommitteeIndicesSSZ,
    data: AttestationDataSSZ,
    signature: p.BLSSignature,
};
const IndexedAttestationSSZ = ssz.createContainerType(IndexedAttestationSF, sha256Hash);

const PendingAttestationSF = struct {
    aggregation_bits: CommitteeBitsSSZ,
    data: AttestationDataSSZ,
    inclusion_delay: p.Uint64,
    proposer_index: p.ValidatorIndex,
};
const PendingAttestationSSZ = ssz.createContainerType(PendingAttestationSF, sha256Hash);

const SigningDataSF = struct {
    object_root: p.Root,
    domain: p.Domain,
};
const SigningDataSSZ = ssz.createContainerType(SigningDataSF, sha256Hash);

const AttestationSF = struct {
    aggregation_bits: CommitteeBitsSSZ,
    data: AttestationDataSSZ,
    signature: p.BLSSignature,
};
const AttestationSSZ = ssz.createContainerType(AttestationSF, sha256Hash);

const AttesterSlashingSF = struct {
    attestation_1: IndexedAttestationSSZ,
    attestation_2: IndexedAttestationSSZ,
};
const AttesterSlashingSSZ = ssz.createContainerType(AttesterSlashingSF, sha256Hash);

const DepositProofSSZ = ssz.createVectorCompositeType(p.Bytes32);
const DepositSF = struct {
    proof: DepositProofSSZ,
    data: DepositDataSSZ,
};
const DepositSSZ = ssz.createContainerType(DepositSF, sha256Hash);

const ProposerSlashingSF = struct {
    signed_header_1: SignedBeaconBlockHeaderSSZ,
    signed_header_2: SignedBeaconBlockHeaderSSZ,
};
const ProposerSlashingSSZ = ssz.createContainerType(ProposerSlashingSF, sha256Hash);

const VoluntaryExitSF = struct {
    epoch: p.Epoch,
    validator_index: p.ValidatorIndex,
};
const VoluntaryExitSSZ = ssz.createContainerType(VoluntaryExitSF, sha256Hash);

const SignedVoluntaryExitSF = struct {
    message: VoluntaryExitSSZ,
    signature: p.BLSSignature,
};
const SignedVoluntaryExitSSZ = ssz.createContainerType(SignedVoluntaryExitSF, sha256Hash);

const ProposerSlashingsSSZ = ssz.createListCompositeType(ProposerSlashingSSZ);
const AttesterSlashingsSSZ = ssz.createListCompositeType(AttesterSlashingSSZ);
const AttestationsSSZ = ssz.createListCompositeType(AttestationSSZ);
const DepositsSSZ = ssz.createListCompositeType(DepositSSZ);
const SignedVoluntaryExitsSSZ = ssz.createListCompositeType(SignedVoluntaryExitSSZ);
const BeaconBlockBodySF = struct {
    randao_reveal: p.BLSSignature,
    eth1_data: Eth1DataSSZ,
    graffiti: p.Bytes32,
    proposer_slashings: ProposerSlashingsSSZ,
    attester_slashings: AttesterSlashingsSSZ,
    attestations: AttestationsSSZ,
    deposits: DepositsSSZ,
    voluntary_exits: SignedVoluntaryExitsSSZ,
};
const BeaconBlockBodySSZ = ssz.createContainerType(BeaconBlockBodySF, sha256Hash);

const BeaconBlockSF = struct {
    slot: p.Slot,
    proposer_index: p.ValidatorIndex,
    parent_root: p.Root,
    state_root: p.Root,
    body: BeaconBlockBodySSZ,
};
const BeaconBlockSSZ = ssz.createContainerType(BeaconBlockSF, sha256Hash);

const SignedBeaconBlockSF = struct {
    message: BeaconBlockSSZ,
    signature: p.BLSSignature,
};
const SignedBeaconBlockSSZ = ssz.createContainerType(SignedBeaconBlockSF, sha256Hash);

// State types
// ===========

const EpochAttestationsSSZ = ssz.createListCompositeType(PendingAttestationSSZ);

const BeaconStateSF = struct {
    genesis_time: p.Uint64,
    genesis_validators_root: p.Root,
    slot: p.Slot,
    fork: ForkSSZ,
    latest_block_header: BeaconBlockHeaderSSZ,
    block_roots: HistoricalBlockRootsSSZ,
    state_roots: HistoricalStateRootsSSZ,
    historical_roots: HistoricalBatchRootsSSZ,
    // Eth1
    eth1_data: Eth1DataSSZ,
    eth1_data_votes: Eth1DataVotesSSZ,
    eth1_deposit_index: p.Uint64,
    // Registry
    validators: ValidatorsSSZ,
    balances: BalancesSSZ,
    randao_mixes: RandaoMixesSSZ,
    // Slashings
    slashings: SlashingsSSZ,
    // Attestations
    previous_epoch_attestations: EpochAttestationsSSZ,
    current_epoch_attestations: EpochAttestationsSSZ,
    // Finality
    justification_bits: JustificationBitsSSZ,
    previous_justified_checkpoint: CheckpointSSZ,
    current_justified_checkpoint: CheckpointSSZ,
    finalized_checkpoint: CheckpointSSZ,
};
const BeaconStateSSZ = ssz.createContainerType(BeaconStateSF, sha256Hash);

// Validator types
// ===============

const CommitteeAssignmentSF = struct {
    validators: CommitteeIndicesSSZ,
    committee_index: p.CommitteeIndex,
    slot: p.Slot,
};
const CommitteeAssignmentSSZ = ssz.createContainerType(CommitteeAssignmentSF, sha256Hash);

const AggregateAndProofSF = struct {
    aggregator_index: p.ValidatorIndex,
    aggregate: AttestationSSZ,
    selection_proof: p.BLSSignature,
};
const AggregateAndProofSSZ = ssz.createContainerType(AggregateAndProofSF, sha256Hash);

const SignedAggregateAndProofSF = struct {
    message: AggregateAndProofSSZ,
    signature: p.BLSSignature,
};
const SignedAggregateAndProofSSZ = ssz.createContainerType(SignedAggregateAndProofSF, sha256Hash);

// ReqResp types
// =============

const StatusSF = struct {
    fork_digest: p.ForkDigest,
    finalized_root: p.Root,
    finalized_epoch: p.Epoch,
    head_root: p.Root,
    head_slot: p.Slot,
};
const StatusSSZ = ssz.createContainerType(StatusSF, sha256Hash);

const GoodbyeSSZ = p.Uint64;

const PingSSZ = p.Uint64;

const MetadataSF = struct {
    seq_number: p.Uint64,
    attnets: AttestationSubnetsSSZ,
};
const MetadataSSZ = ssz.createContainerType(MetadataSF, sha256Hash);

const BeaconBlocksByRangeRequestSF = struct {
    start_slot: p.Slot,
    count: p.Uint64,
    step: p.Uint64,
};
const BeaconBlocksByRangeRequestSSZ = ssz.createContainerType(BeaconBlocksByRangeRequestSF, sha256Hash);

const BeaconBlocksByRootRequestSSZ = ssz.createListCompositeType(p.Root);

// Api types
// =========

const GenesisSF = struct {
    genesis_time: p.Uint64,
    genesis_validators_root: p.Root,
    genesis_fork_version: p.Version,
};
const GenesisSSZ = ssz.createContainerType(GenesisSF, sha256Hash);

/// phase0 namespace for zig types
pub const phase0 = struct {
    pub const AttestationSubnets = AttestationSubnetsSSZ.getZigType();
    pub const BeaconBlockHeader = BeaconBlockHeaderSSZ.getZigType();
    pub const SignedBeaconBlockHeader = SignedBeaconBlockHeaderSSZ.getZigType();
    pub const Checkpoint = CheckpointSSZ.getZigType();
    pub const CommitteeBits = CommitteeBitsSSZ.getZigType();
    pub const CommitteeIndices = CommitteeIndicesSSZ.getZigType();
    pub const DepositMessage = DepositMessageSSZ.getZigType();
    pub const DepositData = DepositDataSSZ.getZigType();
    pub const DepositDataRootFullList = DepositDataRootFullListSSZ.getZigType();
    pub const DepositEvent = DepositEventSSZ.getZigType();
    pub const Eth1Data = Eth1DataSSZ.getZigType();
    pub const Eth1DataVotes = Eth1DataVotesSSZ.getZigType();
    pub const Eth1DataOrdered = Eth1DataOrderedSSZ.getZigType();
    pub const Eth1Block = Eth1BlockSSZ.getZigType();
    pub const Fork = ForkSSZ.getZigType();
    pub const ForkData = ForkDataSSZ.getZigType();
    pub const ENRForkID = ENRForkIDSSZ.getZigType();
    pub const HistoricalBlockRoots = HistoricalBlockRootsSSZ.getZigType();
    pub const HistoricalStateRoots = HistoricalStateRootsSSZ.getZigType();
    pub const HistoricalBatch = HistoricalBatchSSZ.getZigType();
    pub const HistoricalBatchRoots = HistoricalBatchRootsSSZ.getZigType();
    pub const Validator = ValidatorSSZ.getZigType();
    pub const Validators = ValidatorsSSZ.getZigType();
    pub const Balances = BalancesSSZ.getZigType();
    pub const RandaoMixes = RandaoMixesSSZ.getZigType();
    pub const Slashings = SlashingsSSZ.getZigType();
    pub const JustificationBits = JustificationBitsSSZ.getZigType();
    pub const AttestationData = AttestationDataSSZ.getZigType();
    pub const IndexedAttestation = IndexedAttestationSSZ.getZigType();
    pub const PendingAttestation = PendingAttestationSSZ.getZigType();
    pub const SigningData = SigningDataSSZ.getZigType();
    pub const Attestation = AttestationSSZ.getZigType();
    pub const AttesterSlashing = AttesterSlashingSSZ.getZigType();
    pub const Deposit = DepositSSZ.getZigType();
    pub const ProposerSlashing = ProposerSlashingSSZ.getZigType();
    pub const VoluntaryExit = VoluntaryExitSSZ.getZigType();
    pub const SignedVoluntaryExit = SignedVoluntaryExitSSZ.getZigType();
    pub const BeaconBlockBody = BeaconBlockBodySSZ.getZigType();
    pub const BeaconBlock = BeaconBlockSSZ.getZigType();
    pub const SignedBeaconBlock = SignedBeaconBlockSSZ.getZigType();
    pub const EpochAttestations = EpochAttestationsSSZ.getZigType();
    pub const BeaconState = BeaconStateSSZ.getZigType();
    pub const CommitteeAssignment = CommitteeAssignmentSSZ.getZigType();
    pub const AggregateAndProof = AggregateAndProofSSZ.getZigType();
    pub const SignedAggregateAndProof = SignedAggregateAndProofSSZ.getZigType();
    pub const Status = StatusSSZ.getZigType();
    pub const Goodbye = GoodbyeSSZ.getZigType();
    pub const Ping = PingSSZ.getZigType();
    pub const Metadata = MetadataSSZ.getZigType();
    pub const BeaconBlocksByRangeRequest = BeaconBlocksByRangeRequestSSZ.getZigType();
    pub const Genesis = GenesisSSZ.getZigType();
};

pub const Phase0SSZTypes = struct {
    AttestationSubnets: AttestationSubnetsSSZ,
    BeaconBlockHeader: BeaconBlockHeaderSSZ,
    SignedBeaconBlockHeader: SignedBeaconBlockHeaderSSZ,
    Checkpoint: CheckpointSSZ,
    CommitteeBits: CommitteeBitsSSZ,
    CommitteeIndices: CommitteeIndicesSSZ,
    DepositMessage: DepositMessageSSZ,
    DepositData: DepositDataSSZ,
    DepositDataRootFullList: DepositDataRootFullListSSZ,
    DepositEvent: DepositEventSSZ,
    Eth1Data: Eth1DataSSZ,
    Eth1DataVotes: Eth1DataVotesSSZ,
    Eth1DataOrdered: Eth1DataOrderedSSZ,
    Eth1Block: Eth1BlockSSZ,
    Fork: ForkSSZ,
    ForkData: ForkDataSSZ,
    ENRForkID: ENRForkIDSSZ,
    HistoricalBlockRoots: HistoricalBlockRootsSSZ,
    HistoricalStateRoots: HistoricalStateRootsSSZ,
    HistoricalBatch: HistoricalBatchSSZ,
    HistoricalBatchRoots: HistoricalBatchRootsSSZ,
    Validator: ValidatorSSZ,
    Validators: ValidatorsSSZ,
    Balances: BalancesSSZ,
    RandaoMixes: RandaoMixesSSZ,
    Slashings: SlashingsSSZ,
    JustificationBits: JustificationBitsSSZ,
    AttestationData: AttestationDataSSZ,
    IndexedAttestation: IndexedAttestationSSZ,
    PendingAttestation: PendingAttestationSSZ,
    SigningData: SigningDataSSZ,
    Attestation: AttestationSSZ,
    AttesterSlashing: AttesterSlashingSSZ,
    Deposit: DepositSSZ,
    ProposerSlashing: ProposerSlashingSSZ,
    VoluntaryExit: VoluntaryExitSSZ,
    SignedVoluntaryExit: SignedVoluntaryExitSSZ,
    BeaconBlockBody: BeaconBlockBodySSZ,
    BeaconBlock: BeaconBlockSSZ,
    SignedBeaconBlock: SignedBeaconBlockSSZ,
    EpochAttestations: EpochAttestationsSSZ,
    BeaconState: BeaconStateSSZ,
    CommitteeAssignment: CommitteeAssignmentSSZ,
    AggregateAndProof: AggregateAndProofSSZ,
    SignedAggregateAndProof: SignedAggregateAndProofSSZ,
    Status: StatusSSZ,
    Goodbye: GoodbyeSSZ,
    Ping: PingSSZ,
    Metadata: MetadataSSZ,
    BeaconBlocksByRangeRequest: BeaconBlocksByRangeRequestSSZ,
    BeaconBlocksByRootRequest: BeaconBlocksByRootRequestSSZ,
    Genesis: GenesisSSZ,

    pub fn init(allocator: Allocator) !@This() {
        const pt = try p.getPrimitiveTypes(allocator);

        const AttestationSubnets = try AttestationSubnetsSSZ.init(allocator);

        const BeaconBlockHeader = try BeaconBlockHeaderSSZ.init(allocator, .{
            .slot = pt.Slot,
            .proposer_index = pt.ValidatorIndex,
            .parent_root = pt.Root,
            .state_root = pt.Root,
            .body_root = pt.Root,
        });

        const SignedBeaconBlockHeader = try SignedBeaconBlockHeaderSSZ.init(allocator, .{
            .message = BeaconBlockHeader,
            .signature = pt.BLSSignature,
        });

        const Checkpoint = try CheckpointSSZ.init(allocator, .{
            .epoch = pt.Epoch,
            .root = pt.Root,
        });

        const CommitteeBits = try CommitteeBitsSSZ.init(allocator, preset.MAX_VALIDATORS_PER_COMMITTEE);

        const CommitteeIndices = try CommitteeIndicesSSZ.init(allocator, &pt.ValidatorIndex, preset.MAX_VALIDATORS_PER_COMMITTEE, preset.MAX_VALIDATORS_PER_COMMITTEE);

        const DepositMessage = try DepositMessageSSZ.init(allocator, .{
            .pubkey = pt.BLSPubkey,
            .withdrawal_credentials = pt.Root,
            .amount = pt.Uint64,
        });

        const DepositData = try DepositDataSSZ.init(allocator, .{
            .pubkey = pt.BLSPubkey,
            .withdrawal_credentials = pt.Bytes32,
            .amount = pt.Uint64,
            .signature = pt.BLSSignature,
        });

        const limit: usize = comptime param.DEPOSIT_CONTRACT_TREE_DEPTH;

        const DepositDataRootFullList = try DepositDataRootFullListSSZ.init(allocator, &pt.Root, limit, param.DEPOSIT_CONTRACT_TREE_DEPTH);

        const DepositEvent = try DepositEventSSZ.init(allocator, .{
            .deposit_data = DepositData,
            .block_number = pt.Uint64,
            .index = pt.Uint64,
        });

        var Eth1Data = try Eth1DataSSZ.init(allocator, .{
            .deposit_root = pt.Root,
            .deposit_count = pt.Uint64,
            .block_hash = pt.Bytes32,
        });

        const vote_limit = comptime preset.EPOCHS_PER_ETH1_VOTING_PERIOD * preset.SLOTS_PER_EPOCH;
        const Eth1DataVotes = try Eth1DataVotesSSZ.init(allocator, &Eth1Data, vote_limit, vote_limit);

        const Eth1DataOrdered = try Eth1DataOrderedSSZ.init(allocator, .{
            .deposit_root = pt.Root,
            .deposit_count = pt.Uint64,
            .block_hash = pt.Bytes32,
            .block_number = pt.Uint64,
        });

        const Eth1Block = try Eth1BlockSSZ.init(allocator, .{
            .timestamp = pt.Uint64,
            .deposit_root = pt.Root,
            .deposit_count = pt.Uint64,
        });

        const Fork = try ForkSSZ.init(allocator, .{
            .previous_version = pt.Version,
            .current_version = pt.Version,
            .epoch = pt.Epoch,
        });

        const ForkData = try ForkDataSSZ.init(allocator, .{
            .current_version = pt.Version,
            .genesis_validators_root = pt.Root,
        });

        const ENRForkID = try ENRForkIDSSZ.init(allocator, .{
            .fork_digest = pt.ForkDigest,
            .next_fork_version = pt.Version,
            .next_fork_epoch = pt.Epoch,
        });

        const HistoricalBlockRoots = try HistoricalBlockRootsSSZ.init(allocator, &pt.Root, preset.SLOTS_PER_HISTORICAL_ROOT, preset.SLOTS_PER_HISTORICAL_ROOT);

        const HistoricalStateRoots = try HistoricalStateRootsSSZ.init(allocator, &pt.Root, preset.SLOTS_PER_HISTORICAL_ROOT, preset.SLOTS_PER_HISTORICAL_ROOT);

        const HistoricalBatch = try HistoricalBatchSSZ.init(allocator, .{
            .block_roots = HistoricalBlockRoots,
            .state_roots = HistoricalStateRoots,
        });

        const HistoricalBatchRoots = try HistoricalBatchRootsSSZ.init(allocator, .{
            .block_roots = HistoricalBlockRoots,
            .state_roots = HistoricalStateRoots,
        });

        var Validator = try ValidatorSSZ.init(allocator, .{
            .pubkey = pt.BLSPubkey,
            .withdrawal_credentials = pt.Root,
            .effective_balance = pt.Gwei,
            .slashed = pt.Boolean,
            .activation_eligibility_epoch = pt.Epoch,
            .activation_epoch = pt.Epoch,
            .exit_epoch = pt.Epoch,
            .withdrawable_epoch = pt.Epoch,
        });

        const Validators = try ValidatorsSSZ.init(allocator, &Validator, preset.VALIDATOR_REGISTRY_LIMIT, preset.VALIDATOR_REGISTRY_LIMIT);

        const Balances = try BalancesSSZ.init(allocator, &pt.Gwei, preset.VALIDATOR_REGISTRY_LIMIT, preset.VALIDATOR_REGISTRY_LIMIT);

        const RandaoMixes = try RandaoMixesSSZ.init(allocator, &pt.Bytes32, preset.EPOCHS_PER_HISTORICAL_VECTOR);

        const Slashings = try SlashingsSSZ.init(allocator, &pt.Gwei, preset.EPOCHS_PER_SLASHINGS_VECTOR);

        const JustificationBits = try JustificationBitsSSZ.init(allocator);

        const AttestationData = try AttestationDataSSZ.init(allocator, .{
            .slot = pt.Slot,
            .index = pt.CommitteeIndex,
            .beacon_block_root = pt.Root,
            .source = Checkpoint,
            .target = Checkpoint,
        });

        const IndexedAttestation = try IndexedAttestationSSZ.init(allocator, .{
            .attesting_indices = CommitteeIndices,
            .data = AttestationData,
            .signature = pt.BLSSignature,
        });

        var PendingAttestation = try PendingAttestationSSZ.init(allocator, .{
            .aggregation_bits = CommitteeBits,
            .data = AttestationData,
            .inclusion_delay = pt.Uint64,
            .proposer_index = pt.ValidatorIndex,
        });

        const SigningData = try SigningDataSSZ.init(allocator, .{
            .object_root = pt.Root,
            .domain = pt.Domain,
        });

        var Attestation = try AttestationSSZ.init(allocator, .{
            .aggregation_bits = CommitteeBits,
            .data = AttestationData,
            .signature = pt.BLSSignature,
        });

        var AttesterSlashing = try AttesterSlashingSSZ.init(allocator, .{
            .attestation_1 = IndexedAttestation,
            .attestation_2 = IndexedAttestation,
        });

        var Deposit = try DepositSSZ.init(allocator, .{
            .proof = try DepositProofSSZ.init(allocator, &pt.Bytes32, param.DEPOSIT_CONTRACT_TREE_DEPTH + 1),
            .data = DepositData,
        });

        var ProposerSlashing = try ProposerSlashingSSZ.init(allocator, .{
            .signed_header_1 = SignedBeaconBlockHeader,
            .signed_header_2 = SignedBeaconBlockHeader,
        });

        const VoluntaryExit = try VoluntaryExitSSZ.init(allocator, .{
            .epoch = pt.Epoch,
            .validator_index = pt.ValidatorIndex,
        });

        var SignedVoluntaryExit = try SignedVoluntaryExitSSZ.init(allocator, .{
            .message = VoluntaryExit,
            .signature = pt.BLSSignature,
        });

        const BeaconBlockBody = try BeaconBlockBodySSZ.init(allocator, .{
            .randao_reveal = pt.BLSSignature,
            .eth1_data = Eth1Data,
            .graffiti = pt.Bytes32,
            .proposer_slashings = try ProposerSlashingsSSZ.init(allocator, &ProposerSlashing, preset.MAX_PROPOSER_SLASHINGS, preset.MAX_PROPOSER_SLASHINGS),
            .attester_slashings = try AttesterSlashingsSSZ.init(allocator, &AttesterSlashing, preset.MAX_ATTESTER_SLASHINGS, preset.MAX_ATTESTER_SLASHINGS),
            .attestations = try AttestationsSSZ.init(allocator, &Attestation, preset.MAX_ATTESTATIONS, preset.MAX_ATTESTATIONS),
            .deposits = try DepositsSSZ.init(allocator, &Deposit, preset.MAX_DEPOSITS, preset.MAX_DEPOSITS),
            .voluntary_exits = try SignedVoluntaryExitsSSZ.init(allocator, &SignedVoluntaryExit, preset.MAX_VOLUNTARY_EXITS, preset.MAX_VOLUNTARY_EXITS),
        });

        const BeaconBlock = try BeaconBlockSSZ.init(allocator, .{
            .slot = pt.Slot,
            .proposer_index = pt.ValidatorIndex,
            .parent_root = pt.Root,
            .state_root = pt.Root,
            .body = BeaconBlockBody,
        });

        const SignedBeaconBlock = try SignedBeaconBlockSSZ.init(allocator, .{
            .message = BeaconBlock,
            .signature = pt.BLSSignature,
        });

        const epoch_attestations_limit = comptime preset.MAX_ATTESTATIONS * preset.SLOTS_PER_EPOCH;
        const EpochAttestations = try EpochAttestationsSSZ.init(allocator, &PendingAttestation, epoch_attestations_limit, epoch_attestations_limit);

        const BeaconState = try BeaconStateSSZ.init(allocator, .{
            .genesis_time = pt.Uint64,
            .genesis_validators_root = pt.Root,
            .slot = pt.Slot,
            .fork = Fork,
            .latest_block_header = BeaconBlockHeader,
            .block_roots = HistoricalBlockRoots,
            .state_roots = HistoricalStateRoots,
            .historical_roots = HistoricalBatchRoots,
            .eth1_data = Eth1Data,
            .eth1_data_votes = Eth1DataVotes,
            .eth1_deposit_index = pt.Uint64,
            .validators = Validators,
            .balances = Balances,
            .randao_mixes = RandaoMixes,
            .slashings = Slashings,
            .previous_epoch_attestations = EpochAttestations,
            .current_epoch_attestations = EpochAttestations,
            .justification_bits = JustificationBits,
            .previous_justified_checkpoint = Checkpoint,
            .current_justified_checkpoint = Checkpoint,
            .finalized_checkpoint = Checkpoint,
        });

        const CommitteeAssignment = try CommitteeAssignmentSSZ.init(allocator, .{
            .validators = CommitteeIndices,
            .committee_index = pt.CommitteeIndex,
            .slot = pt.Slot,
        });

        const AggregateAndProof = try AggregateAndProofSSZ.init(allocator, .{
            .aggregator_index = pt.ValidatorIndex,
            .aggregate = Attestation,
            .selection_proof = pt.BLSSignature,
        });

        const SignedAggregateAndProof = try SignedAggregateAndProofSSZ.init(allocator, .{
            .message = AggregateAndProof,
            .signature = pt.BLSSignature,
        });

        const Status = try StatusSSZ.init(allocator, .{
            .fork_digest = pt.ForkDigest,
            .finalized_root = pt.Root,
            .finalized_epoch = pt.Epoch,
            .head_root = pt.Root,
            .head_slot = pt.Slot,
        });

        const Goodbye = pt.Uint64;

        const Ping = pt.Uint64;

        const Metadata = try MetadataSSZ.init(allocator, .{
            .seq_number = pt.Uint64,
            .attnets = AttestationSubnets,
        });

        const BeaconBlocksByRangeRequest = try BeaconBlocksByRangeRequestSSZ.init(allocator, .{
            .start_slot = pt.Slot,
            .count = pt.Uint64,
            .step = pt.Uint64,
        });

        const by_roots_limit = comptime param.MAX_REQUEST_BLOCKS;
        const BeaconBlocksByRootRequest = try BeaconBlocksByRootRequestSSZ.init(allocator, &pt.Root, by_roots_limit, by_roots_limit);

        const Genesis = try GenesisSSZ.init(allocator, .{
            .genesis_time = pt.Uint64,
            .genesis_validators_root = pt.Root,
            .genesis_fork_version = pt.Version,
        });

        return @This(){
            .AttestationSubnets = AttestationSubnets,
            .BeaconBlockHeader = BeaconBlockHeader,
            .SignedBeaconBlockHeader = SignedBeaconBlockHeader,
            .Checkpoint = Checkpoint,
            .CommitteeBits = CommitteeBits,
            .CommitteeIndices = CommitteeIndices,
            .DepositMessage = DepositMessage,
            .DepositData = DepositData,
            .DepositDataRootFullList = DepositDataRootFullList,
            .DepositEvent = DepositEvent,
            .Eth1Data = Eth1Data,
            .Eth1DataVotes = Eth1DataVotes,
            .Eth1DataOrdered = Eth1DataOrdered,
            .Eth1Block = Eth1Block,
            .Fork = Fork,
            .ForkData = ForkData,
            .ENRForkID = ENRForkID,
            .HistoricalBlockRoots = HistoricalBlockRoots,
            .HistoricalStateRoots = HistoricalStateRoots,
            .HistoricalBatch = HistoricalBatch,
            .HistoricalBatchRoots = HistoricalBatchRoots,
            .Validator = Validator,
            .Validators = Validators,
            .Balances = Balances,
            .RandaoMixes = RandaoMixes,
            .Slashings = Slashings,
            .JustificationBits = JustificationBits,
            .AttestationData = AttestationData,
            .IndexedAttestation = IndexedAttestation,
            .PendingAttestation = PendingAttestation,
            .SigningData = SigningData,
            .Attestation = Attestation,
            .AttesterSlashing = AttesterSlashing,
            .Deposit = Deposit,
            .ProposerSlashing = ProposerSlashing,
            .VoluntaryExit = VoluntaryExit,
            .SignedVoluntaryExit = SignedVoluntaryExit,
            .BeaconBlockBody = BeaconBlockBody,
            .BeaconBlock = BeaconBlock,
            .SignedBeaconBlock = SignedBeaconBlock,
            .EpochAttestations = EpochAttestations,
            .BeaconState = BeaconState,
            .CommitteeAssignment = CommitteeAssignment,
            .AggregateAndProof = AggregateAndProof,
            .SignedAggregateAndProof = SignedAggregateAndProof,
            .Status = Status,
            .Goodbye = Goodbye,
            .Ping = Ping,
            .Metadata = Metadata,
            .BeaconBlocksByRangeRequest = BeaconBlocksByRangeRequest,
            .BeaconBlocksByRootRequest = BeaconBlocksByRootRequest,
            .Genesis = Genesis,
        };
    }

    pub fn deinit(self: *const @This()) !void {
        try self.AttestationSubnets.deinit();
        try self.BeaconBlockHeader.deinit();
        try self.SignedBeaconBlockHeader.deinit();
        try self.Checkpoint.deinit();
        try self.CommitteeBits.deinit();
        try self.CommitteeIndices.deinit();
        try self.DepositMessage.deinit();
        try self.DepositData.deinit();
        try self.DepositDataRootFullList.deinit();
        try self.DepositEvent.deinit();
        try self.Eth1Data.deinit();
        try self.Eth1DataVotes.deinit();
        try self.Eth1DataOrdered.deinit();
        try self.Eth1Block.deinit();
        try self.Fork.deinit();
        try self.ForkData.deinit();
        try self.ENRForkID.deinit();
        try self.HistoricalBlockRoots.deinit();
        try self.HistoricalStateRoots.deinit();
        try self.HistoricalBatch.deinit();
        try self.HistoricalBatchRoots.deinit();
        try self.Validator.deinit();
        try self.Validators.deinit();
        try self.Balances.deinit();
        try self.RandaoMixes.deinit();
        try self.Slashings.deinit();
        try self.JustificationBits.deinit();
        try self.AttestationData.deinit();
        try self.IndexedAttestation.deinit();
        try self.PendingAttestation.deinit();
        try self.SigningData.deinit();
        try self.Attestation.deinit();
        try self.AttesterSlashing.deinit();
        try self.Deposit.deinit();
        try self.ProposerSlashing.deinit();
        try self.VoluntaryExit.deinit();
        try self.SignedVoluntaryExit.deinit();
        try self.BeaconBlockBody.deinit();
        try self.BeaconBlock.deinit();
        try self.SignedBeaconBlock.deinit();
        try self.EpochAttestations.deinit();
        try self.BeaconState.deinit();
        try self.CommitteeAssignment.deinit();
        try self.AggregateAndProof.deinit();
        try self.SignedAggregateAndProof.deinit();
        try self.Status.deinit();
        try self.Goodbye.deinit();
        try self.Ping.deinit();
        try self.Metadata.deinit();
        try self.BeaconBlocksByRangeRequest.deinit();
        try self.BeaconBlocksByRootRequest.deinit();
        try self.Genesis.deinit();
    }
};

// Thread-local instance of `?Phase0SSZTypes`
threadlocal var instance: ?Phase0SSZTypes = null;

pub fn getPhase0SSZTypes(allocator: Allocator) !*const Phase0SSZTypes {
    if (instance == null) {
        instance = try Phase0SSZTypes.init(allocator);
    }

    return &instance.?;
}

// TODO: add more tests
test "auto generated types" {
    const Checkpoint = phase0.Checkpoint;
    // expected data structure
    const ECheckpoint = struct {
        epoch: u64,
        root: []u8,
    };
    try expectTypesEqual(ECheckpoint, Checkpoint);

    const AttestationData = phase0.AttestationData;
    // expected data structure
    const EAttestationData = struct {
        slot: u64,
        index: u64,
        beacon_block_root: []u8,
        source: ECheckpoint,
        target: ECheckpoint,
    };
    try expectTypesEqual(EAttestationData, AttestationData);
}

fn expectTypesEqual(a: type, b: type) !void {
    try std.testing.expectEqual(@alignOf(a), @alignOf(b));
    try std.testing.expectEqual(@sizeOf(a), @sizeOf(b));
}
