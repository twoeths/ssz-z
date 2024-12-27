const std = @import("std");
const Allocator = std.mem.Allocator;
const ssz = @import("ssz");

pub const Uint8 = ssz.createUintType(1);
pub const Uint16 = ssz.createUintType(2);
pub const Uint32 = ssz.createUintType(4);
pub const Uint64 = ssz.createUintType(8);
pub const Slot = Uint64;
pub const Epoch = Uint64;
pub const CommitteeIndex = Uint64;
pub const Root = ssz.ByteVectorType;

pub const PrimitiveTypes = struct {
    Boolean: ssz.BooleanType,
    Byte: Uint8,
    Bytes4: ssz.ByteVectorType,
    Bytes8: ssz.ByteVectorType,
    Bytes20: ssz.ByteVectorType,
    Bytes32: ssz.ByteVectorType,
    Bytes48: ssz.ByteVectorType,
    Bytes96: ssz.ByteVectorType,
    Uint8: Uint8,
    Uint16: Uint16,
    Uint32: Uint32,
    Uint64: Uint64,
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
    // TODO: Wei
    Root: ssz.ByteVectorType,
    BlobIndex: Uint64,
    Version: ssz.ByteVectorType,
    DomainType: ssz.ByteVectorType,
    BLSPubkey: ssz.ByteVectorType,
    BLSSignature: ssz.ByteVectorType,

    pub fn init(allocator: Allocator) !PrimitiveTypes {
        const uint64 = try Uint64.init();
        const bytes4 = try ssz.ByteVectorType.init(allocator, 4);
        const bytes32 = try ssz.ByteVectorType.init(allocator, 32);
        const bytes48 = try ssz.ByteVectorType.init(allocator, 48);
        const bytes96 = try ssz.ByteVectorType.init(allocator, 96);

        return PrimitiveTypes{
            .Boolean = ssz.BooleanType.init(),
            .Byte = try Uint8.init(),
            .Bytes4 = bytes4,
            .Bytes8 = try ssz.ByteVectorType.init(allocator, 8),
            .Bytes20 = try ssz.ByteVectorType.init(allocator, 20),
            .Bytes32 = bytes32,
            .Bytes48 = bytes48,
            .Bytes96 = bytes96,
            .Uint8 = try Uint8.init(),
            .Uint16 = try Uint16.init(),
            .Uint32 = try Uint32.init(),
            .Uint64 = uint64,
            .Slot = uint64,
            .Epoch = uint64,
            .CommitteeIndex = uint64,
            .SubcommitteeIndex = uint64,
            .ValidatorIndex = uint64,
            .WithdrawalIndex = uint64,
            .Gwei = uint64,
            .SyncPeriod = uint64,
            .Root = bytes32,
            .BlobIndex = uint64,
            .Version = bytes4,
            .DomainType = bytes4,
            .BLSPubkey = bytes48,
            .BLSSignature = bytes96,
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
        try self.Uint8.deinit();
        try self.Uint16.deinit();
        try self.Uint32.deinit();
        try self.Uint64.deinit();
        // below are alias types so no need to deinit
        // Slot
        // Epoch
        // Root
        // BLSPubkey
        // BLSSignature
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
