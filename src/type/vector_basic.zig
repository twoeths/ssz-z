const std = @import("std");
const maxChunksToDepth = @import("hash").maxChunksToDepth;
const merkleize = @import("hash").merkleizeBlocksBytes;
const sha256Hash = @import("hash").sha256Hash;
const fromHex = @import("util").fromHex;
const toRootHex = @import("util").toRootHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;

/// Vector: Ordered fixed-length homogeneous collection, with N values
/// ST: ssz element type
/// ZT: zig element type
pub fn createVectorBasicType(comptime ST: type, comptime ZT: type) type {
    const ArrayBasic = @import("./array_basic.zig").withElementTypes(ST, ZT);

    const VectorBasicType = struct {
        allocator: *std.mem.Allocator,
        element_type: *ST,
        length: usize,
        fixed_size: ?usize,
        depth: usize,
        chunk_depth: usize,
        max_chunk_count: usize,
        min_size: usize,
        max_size: usize,
        // this should always be a multiple of 64 bytes
        block_bytes: []u8,

        pub fn init(allocator: *std.mem.Allocator, element_type: *ST, length: usize) !@This() {
            const elem_byte_length = element_type.byte_length;
            const byte_len = elem_byte_length * length;
            const max_chunk_count: usize = (byte_len + 31 / 32);
            const chunk_depth = maxChunksToDepth(max_chunk_count);
            const depth = chunk_depth;
            const blocks_bytes_len: usize = ((max_chunk_count + 1) / 2) * 64;
            return @This(){
                .allocator = allocator,
                .element_type = element_type,
                .length = length,
                .fixed_size = byte_len,
                .depth = depth,
                .chunk_depth = chunk_depth,
                .max_chunk_count = max_chunk_count,
                .min_size = byte_len,
                .max_size = byte_len,
                .block_bytes = try allocator.alloc(u8, blocks_bytes_len),
            };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.block_bytes);
        }

        pub fn hashTreeRoot(self: *@This(), value: []const ZT, out: []u8) !void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            if (value.len > self.length) {
                return error.InCorrectLen;
            }

            const byte_len = self.element_type.byte_length * value.len;
            _ = try ArrayBasic.serializeToBytes(self.element_type, value, self.block_bytes[0..byte_len]);
            if (byte_len < self.block_bytes.len) {
                @memset(self.block_bytes[byte_len..], 0);
            }

            // chunks root
            try merkleize(sha256Hash, self.block_bytes, self.max_chunk_count, out);
        }

        // Serialization + deserialization
        pub fn serializedSize(self: @This(), _: []const ZT) usize {
            return self.fixed_size;
        }

        pub fn serializeToBytes(self: @This(), value: []const ZT, out: []u8) !usize {
            if (out.len != self.fixed_size) {
                return error.InCorrectLen;
            }

            return ArrayBasic.serializeToBytes(self.element_type, value, out);
        }

        pub fn deserializeFromBytes(self: @This(), data: []const u8, out: []ZT) !void {
            if (out.len != self.length or data.len != self.fixed_size) {
                return error.InCorrectLen;
            }

            return ArrayBasic.deserializeFromBytes(self.element_type, data, out);
        }

        pub fn equals(self: @This(), a: []const ZT, b: []const ZT) bool {
            return ArrayBasic.valueEquals(self.element_type, a, b);
        }

        pub fn clone(self: @This(), value: []const ZT, out: []ZT) !void {
            return ArrayBasic.valueClone(self.element_type, value, out);
        }
    };

    return VectorBasicType;
}

test "deserializeFromBytes" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    // uint of 8 bytes = u64
    const UintType = @import("./uint.zig").createUintType(8);
    const VectorBasicType = createVectorBasicType(UintType, u64);
    var uintType = try UintType.init();
    var vectorType = try VectorBasicType.init(&allocator, &uintType, 8);
    defer uintType.deinit();
    defer vectorType.deinit();

    const TestCase = struct {
        serializedHex: []const u8,
        value: []const u64,
        root: []const u8,
    };

    const testCases = [_]TestCase{
        // 8 values
        TestCase{ .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000a086010000000000400d030000000000e093040000000000801a060000000000", .value = ([_]u64{ 100000, 200000, 300000, 400000, 100000, 200000, 300000, 400000 })[0..], .root = "0xdd5160dd98e6daa77287c8940decad4eaa14dc98b99285da06ba5479cd570007" },
    };

    // just declare max size on stack memory
    var serializedMax = [_]u8{0} ** 1024;
    var valueMax = [_]u64{0} ** 100;
    for (testCases) |tc| {
        const serialized = serializedMax[0..((tc.serializedHex.len - 2) / 2)];
        try fromHex(tc.serializedHex, serialized);
        var value = valueMax[0..tc.value.len];
        try vectorType.deserializeFromBytes(serialized, value);
        try std.testing.expectEqual(value.len, tc.value.len);
        for (value, tc.value) |a, b| {
            try std.testing.expectEqual(a, b);
        }
        var root = [_]u8{0} ** 32;
        try vectorType.hashTreeRoot(value[0..], root[0..]);
        const rootHex = try toRootHex(root[0..]);
        try std.testing.expectEqualSlices(u8, tc.root, rootHex);

        // clone
        const cloned = valueMax[tc.value.len..(tc.value.len * 2)];
        try vectorType.clone(value, cloned);
        var root2 = [_]u8{0} ** 32;
        try vectorType.hashTreeRoot(cloned[0..], root2[0..]);
        try std.testing.expectEqualSlices(u8, root2[0..], root[0..]);

        // equals
        try std.testing.expect(vectorType.equals(value[0..], cloned[0..]));
    }
}
