const std = @import("std");
const Allocator = std.mem.Allocator;
const Scanner = std.json.Scanner;
const maxChunksToDepth = @import("hash").maxChunksToDepth;
const merkleize = @import("hash").merkleizeBlocksBytes;
const sha256Hash = @import("hash").sha256Hash;
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const ArrayList = std.ArrayList;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const HashError = @import("./common.zig").HashError;
const Parsed = @import("./type.zig").Parsed;

/// List: ordered variable-length homogeneous collection, limited to N values
/// ST: ssz element type
/// ZT: zig element type
pub fn createListBasicType(comptime ST: type) type {
    const BlockBytes = ArrayList(u8);
    const ZT = ST.getZigType();
    const ArrayBasic = @import("./array_basic.zig").withElementTypes(ST, ZT);
    const ParsedResult = Parsed([]ZT);

    const ListBasicType = struct {
        allocator: std.mem.Allocator,
        element_type: *const ST,
        limit: usize,
        fixed_size: ?usize,
        depth: usize,
        chunk_depth: usize,
        max_chunk_count: usize,
        min_size: usize,
        max_size: usize,
        // this should always be a multiple of 64 bytes
        block_bytes: BlockBytes,
        mix_in_length_block_bytes: []u8,

        /// Zig Type definition
        pub fn getZigType() type {
            return []ZT;
        }

        pub fn getZigTypeAlignment() usize {
            return @alignOf([]ZT);
        }

        /// init_capacity is the initial capacity of elements, not bytes
        pub fn init(allocator: std.mem.Allocator, element_type: *const ST, limit: usize, init_capacity: usize) !@This() {
            const elem_byte_length = element_type.byte_length;
            const init_capacity_bytes = init_capacity * elem_byte_length;
            const max_chunk_count = (limit * elem_byte_length + 31) / 32;
            const chunk_depth = maxChunksToDepth(max_chunk_count);
            // Depth includes the extra level for the length node
            const depth = chunk_depth + 1;
            return @This(){ .allocator = allocator, .element_type = element_type, .limit = limit, .fixed_size = null, .depth = depth, .chunk_depth = chunk_depth, .max_chunk_count = max_chunk_count, .min_size = 0, .max_size = limit * element_type.max_size, .block_bytes = try BlockBytes.initCapacity(allocator, init_capacity_bytes), .mix_in_length_block_bytes = try allocator.alloc(u8, 64) };
        }

        pub fn deinit(self: *const @This()) void {
            self.block_bytes.deinit();
            self.allocator.free(self.mix_in_length_block_bytes);
        }

        /// public apis
        pub fn hashTreeRoot(self: *@This(), value: []const ZT, out: []u8) HashError!void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            if (value.len > self.limit) {
                return error.InCorrectLen;
            }

            const byte_len = self.element_type.byte_length * value.len;
            const block_len: usize = ((byte_len + 63) / 64) * 64;
            try self.block_bytes.resize(block_len);

            _ = try ArrayBasic.serializeToBytes(self.element_type, value, self.block_bytes.items[0..byte_len]);
            if (byte_len < block_len) {
                @memset(self.block_bytes.items[byte_len..block_len], 0);
            }

            // chunks root
            try merkleize(sha256Hash, self.block_bytes.items[0..block_len], self.max_chunk_count, self.mix_in_length_block_bytes[0..32]);

            // mixInLength
            @memset(self.mix_in_length_block_bytes[32..], 0);
            const slice = std.mem.bytesAsSlice(u64, self.mix_in_length_block_bytes[32..]);
            const len_le = if (native_endian == .big) @byteSwap(value.len) else value.len;
            slice[0] = len_le;

            // final root
            // one for hashTreeRoot(value), one for length
            const chunk_count = 2;
            try merkleize(sha256Hash, self.mix_in_length_block_bytes, chunk_count, out);
        }

        pub fn fromSsz(self: *const @This(), ssz: []const u8) SszError!ParsedResult {
            return ArrayBasic.fromSsz(self, ssz);
        }

        pub fn fromJson(self: *const @This(), json: []const u8) JsonError!ParsedResult {
            return ArrayBasic.fromJson(self, json);
        }

        pub fn clone(self: *const @This(), value: []const ZT) SszError!ParsedResult {
            return ArrayBasic.clone(self, value);
        }

        // Serialization + deserialization
        pub fn serializedSize(self: *const @This(), value: []const ZT) usize {
            return self.element_type.byte_length * value.len;
        }

        pub fn serializeToBytes(self: *const @This(), value: []const ZT, out: []u8) !usize {
            return try ArrayBasic.serializeToBytes(self.element_type, value, out);
        }

        pub fn deserializeFromBytes(self: *const @This(), data: []const u8, out: []ZT) !void {
            try ArrayBasic.deserializeFromBytes(self.element_type, data, out);
        }

        /// Same to deserializeFromBytes but this returns *T instead of out param
        /// Consumer need to free the memory
        /// out parameter is unused, just to conform to the api
        pub fn deserializeFromSlice(self: *const @This(), arenaAllocator: Allocator, slice: []const u8, out: ?[]ZT) SszError![]ZT {
            return try ArrayBasic.deserializeFromSlice(arenaAllocator, self.element_type, slice, null, out);
        }

        /// Implementation for parent
        /// Consumer need to free the memory
        /// out parameter is unused because parent does not allocate, just to conform to the api
        pub fn deserializeFromJson(self: *const @This(), arena_allocator: Allocator, source: *Scanner, out: ?[]ZT) JsonError![]ZT {
            return try ArrayBasic.deserializeFromJson(arena_allocator, self.element_type, source, null, out);
        }

        pub fn equals(self: *const @This(), a: []const ZT, b: []const ZT) bool {
            return ArrayBasic.itemEquals(self.element_type, a, b);
        }

        pub fn doClone(self: *const @This(), arena_allocator: Allocator, value: []const ZT, out: ?[]ZT) ![]ZT {
            return try ArrayBasic.itemClone(self.element_type, arena_allocator, value, out);
        }
    };

    return ListBasicType;
}

test "deserializeFromBytes" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    // uint of 8 bytes = u64
    const UintType = @import("./uint.zig").createUintType(8);
    const ListBasicType = createListBasicType(UintType);
    var uintType = try UintType.init();
    var listType = try ListBasicType.init(allocator, &uintType, 128, 128);
    defer uintType.deinit();
    defer listType.deinit();

    const TestCase = struct {
        serializedHex: []const u8,
        value: []const u64,
        root: []const u8,
    };

    const testCases = [_]TestCase{
        // empty
        TestCase{ .serializedHex = "0x", .value = ([_]u64{})[0..], .root = "0x52e2647abc3d0c9d3be0387f3f0d925422c7a4e98cf4489066f0f43281a899f3" },
        // 4 values
        TestCase{ .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000", .value = ([_]u64{ 100000, 200000, 300000, 400000 })[0..], .root = "0xd1daef215502b7746e5ff3e8833e399cb249ab3f81d824be60e174ff5633c1bf" },
        // 8 values
        TestCase{ .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000a086010000000000400d030000000000e093040000000000801a060000000000", .value = ([_]u64{ 100000, 200000, 300000, 400000, 100000, 200000, 300000, 400000 })[0..], .root = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1" },
    };

    // just declare max size on stack memory
    var serializedMax = [_]u8{0} ** 1024;
    var valueMax = [_]u64{0} ** 100;
    for (testCases) |tc| {
        const serialized = serializedMax[0..((tc.serializedHex.len - 2) / 2)];
        try fromHex(tc.serializedHex, serialized);
        var value = valueMax[0..tc.value.len];
        try listType.deserializeFromBytes(serialized, value);
        try std.testing.expectEqual(value.len, tc.value.len);
        for (value, tc.value) |a, b| {
            try std.testing.expectEqual(a, b);
        }
        var root = [_]u8{0} ** 32;
        try listType.hashTreeRoot(value[0..], root[0..]);
        const rootHex = try toRootHex(root[0..]);
        try std.testing.expectEqualSlices(u8, tc.root, rootHex);

        // clone
        const cloned_result = try listType.clone(value);
        defer cloned_result.deinit();
        const cloned = cloned_result.value;
        var root2 = [_]u8{0} ** 32;
        try listType.hashTreeRoot(cloned[0..], root2[0..]);
        try std.testing.expectEqualSlices(u8, root2[0..], root[0..]);

        // equals
        try std.testing.expect(listType.equals(value[0..], cloned[0..]));
    }
}

test "deserializeFromJson" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    // uint of 8 bytes = u64
    const UintType = @import("./uint.zig").createUintType(8);
    const ListBasicType = createListBasicType(UintType);
    var uintType = try UintType.init();
    var listType = try ListBasicType.init(allocator, &uintType, 4, 2);
    defer uintType.deinit();
    defer listType.deinit();

    const json = "[\"100000\", \"200000\", \"300000\", \"400000\"]";
    const expected = ([_]u64{ 100000, 200000, 300000, 400000 })[0..];

    const result = try listType.fromJson(json);
    defer result.deinit();
    try std.testing.expectEqual(result.value.len, expected.len);
    for (result.value, expected) |a, b| {
        try std.testing.expectEqual(a, b);
    }

    // missing "]" at the end
    const malformed_json_result = listType.fromJson("[\"100000\", \"200000\", \"300000\"");
    if (malformed_json_result) |_| {
        unreachable;
    } else |err| switch (err) {
        error.UnexpectedEndOfInput => {},
        else => unreachable,
    }
}
