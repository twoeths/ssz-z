const std = @import("std");
const Allocator = std.mem.Allocator;
const ssz = @import("ssz");

pub const Boolean = ssz.BooleanType;
const Byte = ssz.createUintType(1);
const Bytes4 = ssz.createByteVectorType(4);
const Bytes8 = ssz.createByteVectorType(8);
const Bytes20 = ssz.createByteVectorType(20);
const Bytes32 = ssz.createByteVectorType(32);
const Bytes48 = ssz.createByteVectorType(48);
const Bytes96 = ssz.createByteVectorType(96);
pub const Uint8 = ssz.createUintType(1);
pub const Uint16 = ssz.createUintType(2);
pub const Uint32 = ssz.createUintType(4);
pub const Uint64 = ssz.createUintType(8);
pub const Uint128 = ssz.createUintType(16);
pub const Uint256 = ssz.createUintType(32);

pub const Slot = Uint64;
pub const Epoch = Uint64;
pub const SyncPeriod = Uint64;
pub const CommitteeIndex = Uint64;
pub const SubcommitteeIndex = Uint64;
pub const ValidatorIndex = Uint64;
pub const WithdrawalIndex = Uint64;
pub const Gwei = Uint64;
pub const Wei = Uint256;
pub const Root = Bytes32;
pub const BlobIndex = Uint64;

pub const Version = Bytes4;
pub const DomainType = Bytes4;
pub const ForkDigest = Bytes4;
pub const BLSPubkey = Bytes48;
pub const BLSSignature = Bytes96;
pub const Domain = Bytes32;
// TODO: implement setBitwiseOR
pub const ParticipationFlags = ssz.createUintType(1);
pub const ExecutionAddress = Bytes20;

pub const PrimitiveTypes = struct {
    Boolean: ssz.BooleanType,
    Byte: Uint8,
    Bytes4: Bytes4,
    Bytes8: Bytes8,
    Bytes20: Bytes20,
    Bytes32: Bytes32,
    Bytes48: Bytes48,
    Bytes96: Bytes96,
    Uint8: Uint8,
    Uint16: Uint16,
    Uint32: Uint32,
    Uint64: Uint64,
    Uint128: Uint128,
    Uint256: Uint256,
    /// Slot is a time unit, so in all usages it's bounded by the clock, ensuring < 2**53-1
    Slot: Uint64,
    /// Epoch is a time unit, so in all usages it's bounded by the clock, ensuring < 2**53-1
    Epoch: Uint64,
    SyncPeriod: Uint64,
    CommitteeIndex: Uint64,
    SubcommitteeIndex: Uint64,
    ValidatorIndex: Uint64,
    WithdrawalIndex: Uint64,
    Gwei: Uint64,
    Wei: Uint256,
    Root: Bytes32,
    BlobIndex: Uint64,
    Version: Bytes4,
    DomainType: Bytes4,
    ForkDigest: Bytes4,
    BLSPubkey: Bytes48,
    BLSSignature: Bytes96,
    Domain: Bytes32,
    ParticipationFlags: Uint8,
    ExecutionAddress: Bytes20,

    pub fn init(allocator: Allocator) !PrimitiveTypes {
        const uint8 = try Uint8.init();
        const uint64 = try Uint64.init();
        const bytes4 = try Bytes4.init(allocator);
        const bytes32 = try Bytes32.init(allocator);
        const bytes48 = try Bytes48.init(allocator);
        const bytes96 = try Bytes96.init(allocator);

        return PrimitiveTypes{
            .Boolean = ssz.BooleanType.init(),
            .Byte = uint8,
            .Bytes4 = bytes4,
            .Bytes8 = try Bytes8.init(allocator),
            .Bytes20 = try Bytes20.init(allocator),
            .Bytes32 = bytes32,
            .Bytes48 = bytes48,
            .Bytes96 = bytes96,
            .Uint8 = uint8,
            .Uint16 = try Uint16.init(),
            .Uint32 = try Uint32.init(),
            .Uint64 = uint64,
            .Uint128 = try Uint128.init(),
            .Uint256 = try Uint256.init(),
            .Slot = uint64,
            .Epoch = uint64,
            .SyncPeriod = uint64,
            .CommitteeIndex = uint64,
            .SubcommitteeIndex = uint64,
            .ValidatorIndex = uint64,
            .WithdrawalIndex = uint64,
            .Gwei = uint64,
            .Wei = try Uint256.init(),
            .Root = bytes32,
            .BlobIndex = uint64,
            .Version = bytes4,
            .DomainType = bytes4,
            .ForkDigest = bytes4,
            .BLSPubkey = bytes48,
            .BLSSignature = bytes96,
            .Domain = bytes32,
            .ParticipationFlags = uint8,
            .ExecutionAddress = try Bytes20.init(allocator),
        };
    }

    pub fn deinit(self: *const @This()) !void {
        try self.Boolean.deinit();
        try self.Byte.deinit();
        try self.Bytes4.deinit();
        try self.Bytes8.deinit();
        try self.Bytes20.deinit();
        try self.Bytes32.deinit();
        try self.Bytes48.deinit();
        try self.Bytes96.deinit();
        // try self.Uint8.deinit();
        try self.Uint16.deinit();
        try self.Uint32.deinit();
        try self.Uint64.deinit();
        // below are alias types so no need to deinit
        // Slot
        // Epoch
        // SyncPeriod
        // CommitteeIndex
        // SubcommitteeIndex
        // ValidatorIndex
        // WithdrawalIndex
        // Gwei
        try self.Wei.deinit();
        // Root
        // BlobIndex
        // Version
        // DomainType
        // ForkDigest
        // BLSPubkey
        // BLSSignature
        // Domain
        // ParticipationFlags
        // ExecutionAddress
    }
};

// Thread-local instance of `?PrimitiveTypes`
threadlocal var instance: ?PrimitiveTypes = null;

pub fn getPrimitiveTypes(allocator: Allocator) !*const PrimitiveTypes {
    if (instance == null) {
        instance = try PrimitiveTypes.init(allocator);
    }

    return &instance.?;
}
