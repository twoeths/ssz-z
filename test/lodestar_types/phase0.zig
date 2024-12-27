const std = @import("std");
const Allocator = std.mem.Allocator;
const p = @import("./primitive.zig");
const ssz = @import("ssz");
const sha256Hash = @import("hash").sha256Hash;

/// SF stands for ssz_fields
const CheckpointSF = struct {
    epoch: p.Epoch,
    root: p.Root,
};

const CheckpointSSZ = ssz.createContainerType(CheckpointSF, sha256Hash);

const AttestationDataSF = struct {
    slot: p.Slot,
    index: p.CommitteeIndex,
    beacon_block_root: p.Root,
    source: CheckpointSSZ,
    target: CheckpointSSZ,
};

const AttestationDataSSZ = ssz.createContainerType(AttestationDataSF, sha256Hash);

/// phase0 namespace
pub const phase0 = struct {
    pub const Checkpoint = CheckpointSSZ.getZigType();
    pub const AttestationData = AttestationDataSSZ.getZigType();
};

pub const Phase0SSZTypes = struct {
    Checkpoint: CheckpointSSZ,
    AttestationData: AttestationDataSSZ,

    pub fn init(allocator: Allocator) !@This() {
        const primitiveTypes = try p.getPrimitiveTypes(allocator);
        const Checkpoint = try CheckpointSSZ.init(allocator, .{
            .epoch = primitiveTypes.Epoch,
            .root = primitiveTypes.Root,
        });
        const AttestationData = try AttestationDataSSZ.init(allocator, .{
            .slot = primitiveTypes.Slot,
            .index = primitiveTypes.CommitteeIndex,
            .beacon_block_root = primitiveTypes.Root,
            .source = Checkpoint,
            .target = Checkpoint,
        });

        return @This(){
            .Checkpoint = Checkpoint,
            .AttestationData = AttestationData,
        };
    }

    pub fn deinit(self: *const @This()) !void {
        try self.Checkpoint.deinit();
        try self.AttestationData.deinit();
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
    const Checkpoint = CheckpointSSZ.getZigType();
    const ECheckpoint = struct {
        epoch: u64,
        root: []u8,
    };
    try expectTypesEqual(ECheckpoint, Checkpoint);

    const AttestationData = AttestationDataSSZ.getZigType();
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
