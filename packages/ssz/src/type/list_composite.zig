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
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const HashError = @import("./common.zig").HashError;
const native_endian = builtin.target.cpu.arch.endian();
const Parsed = @import("./type.zig").Parsed;

/// List: ordered variable-length homogeneous collection, limited to N values
/// ST: ssz element type
/// ZT: zig element type
pub fn createListCompositeType(comptime ST: type) type {
    const BlockBytes = ArrayList(u8);
    const ZT = ST.getZigType();
    const ArrayComposite = @import("./array_composite.zig").withElementTypes(ST, ZT);
    const ParsedResult = Parsed([]ZT);

    const ListCompositeType = struct {
        allocator: std.mem.Allocator,
        element_type: *ST,
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
        pub fn init(allocator: std.mem.Allocator, element_type: *ST, limit: usize, init_capacity: usize) !@This() {
            const max_chunk_count = limit;
            const chunk_depth = maxChunksToDepth(max_chunk_count);
            const depth = chunk_depth + 1;
            const min_size = 0;
            const max_size = ArrayComposite.maxSize(element_type, limit);
            const init_capacity_bytes = ((init_capacity + 1) / 2) * 32;

            return @This(){
                .allocator = allocator,
                .element_type = element_type,
                .limit = limit,
                .fixed_size = null,
                .depth = depth,
                .chunk_depth = chunk_depth,
                .max_chunk_count = max_chunk_count,
                .min_size = min_size,
                .max_size = max_size,
                .block_bytes = try BlockBytes.initCapacity(allocator, init_capacity_bytes),
                .mix_in_length_block_bytes = try allocator.alloc(u8, 64),
            };
        }

        pub fn deinit(self: *const @This()) void {
            self.block_bytes.deinit();
            self.allocator.free(self.mix_in_length_block_bytes);
        }

        /// public apis
        pub fn hashTreeRoot(self: *@This(), value: []const ZT, out: []u8) HashError!void {
            if (value.len > self.limit) {
                return error.InCorrectLen;
            }

            const required_block_bytes = ((value.len + 1) / 2) * 64;
            try self.block_bytes.resize(required_block_bytes);

            // populate self.block_bytes
            for (value, 0..) |*elem, i| {
                // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                const elem_ptr = if (@typeInfo(@TypeOf(elem.*)) == .Pointer) elem.* else elem;
                try self.element_type.hashTreeRoot(elem_ptr, self.block_bytes.items[i * 32 .. (i + 1) * 32]);
            }

            // zero out the last block if needed
            if (value.len % 2 != 0) {
                @memset(self.block_bytes.items[value.len * 32 .. required_block_bytes], 0);
            }

            // compute hashTreeRoot
            try merkleize(sha256Hash, self.block_bytes.items[0..required_block_bytes], self.max_chunk_count, self.mix_in_length_block_bytes[0..32]);

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
            return ArrayComposite.fromSsz(self, ssz);
        }

        pub fn fromJson(self: *const @This(), json: []const u8) JsonError!ParsedResult {
            return ArrayComposite.fromJson(self, json);
        }

        pub fn clone(self: *const @This(), value: []const ZT) SszError!ParsedResult {
            return ArrayComposite.clone(self, value);
        }

        // Serialization + deserialization
        pub fn serializedSize(self: *const @This(), value: []const ZT) usize {
            return ArrayComposite.serializedSize(self.element_type, value);
        }

        pub fn serializeToBytes(self: *const @This(), value: []const ZT, out: []u8) !usize {
            // TODO: do we need this validation?
            const size = self.serializedSize(value);
            if (out.len != size) {
                return error.InCorrectLen;
            }

            return try ArrayComposite.serializeToBytes(self.element_type, value, out);
        }

        pub fn deserializeFromBytes(self: *const @This(), data: []const u8, out: []ZT) !void {
            try ArrayComposite.deserializeFromBytes(self.allocator, self.element_type, data, out);
        }

        pub fn deserializeFromSlice(self: *const @This(), arena_allocator: Allocator, data: []const u8, _: ?[]ZT) SszError![]ZT {
            return try ArrayComposite.deserializeFromSlice(arena_allocator, self.element_type, data, null, null);
        }

        /// out parameter is not used because memory is always allocated inside the function
        pub fn deserializeFromJson(self: *const @This(), arena_allocator: Allocator, source: *Scanner, _: ?[]ZT) JsonError![]ZT {
            return try ArrayComposite.deserializeFromJson(arena_allocator, self.element_type, source, null, null);
        }

        pub fn equals(self: *const @This(), a: []const ZT, b: []const ZT) bool {
            return ArrayComposite.itemEquals(self.element_type, a, b);
        }

        pub fn doClone(self: *const @This(), arena_allocator: Allocator, value: []const ZT, out: ?[]ZT) ![]ZT {
            return try ArrayComposite.itemClone(self.element_type, arena_allocator, value, out);
        }
    };

    return ListCompositeType;
}

test "ListCompositeType - element type ByteVectorType" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();
    const createByteVectorType = @import("./byte_vector_type.zig").createByteVectorType;
    const ByteVectorType = createByteVectorType(32);
    var byteVectorType = try ByteVectorType.init(allocator);
    defer byteVectorType.deinit();

    const ListCompositeType = createListCompositeType(ByteVectorType);
    var list = try ListCompositeType.init(allocator, &byteVectorType, 128, 4);
    defer list.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const json =
        \\[
        \\"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        \\"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        \\]
    ;
    const result = try list.fromJson(json);
    defer result.deinit();
    const value = result.value;
    // 0xdd = 221, 0xee = 238
    try std.testing.expect(value.len == 2);
    try std.testing.expectEqualSlices(u8, value[0], ([_]u8{221} ** 32)[0..]);
    try std.testing.expectEqualSlices(u8, value[1], ([_]u8{238} ** 32)[0..]);

    var root = [_]u8{0} ** 32;
    try list.hashTreeRoot(value, root[0..]);

    const rootHex = try toRootHex(root[0..]);
    try std.testing.expectEqualSlices(u8, rootHex, "0x0cb947377e177f774719ead8d210af9c6461f41baf5b4082f86a3911454831b8");
}

test "ListCompositeType - element type is ContainerType" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    const UintType = @import("./uint.zig").createUintType(8);
    const SSZElementType = struct {
        a: UintType,
        b: UintType,
    };

    const SSZContainerType = @import("./container.zig").createContainerType(SSZElementType, sha256Hash);
    const ZigContainerType = SSZContainerType.getZigType();
    const ListCompositeType = createListCompositeType(SSZContainerType);

    const uintType = try UintType.init();
    defer uintType.deinit();
    var elementType = try SSZContainerType.init(allocator, .{ .a = uintType, .b = uintType });
    defer elementType.deinit();

    var listType = try ListCompositeType.init(allocator, &elementType, 128, 64);
    defer listType.deinit();

    const TestCase = struct {
        serializedHex: []const u8,
        value: []const ZigContainerType,
        root: []const u8,
    };

    const testCases = [_]TestCase{
        // empty
        TestCase{ .serializedHex = "0x", .value = &[_]ZigContainerType{} ** 0, .root = "0x96559674a79656e540871e1f39c9b91e152aa8cddb71493e754827c4cc809d57" },
        // 2 values
        TestCase{ .serializedHex = "0x0000000000000000000000000000000040e2010000000000f1fb090000000000", .value = &[_]ZigContainerType{ .{ .a = 0, .b = 0 }, .{ .a = 123456, .b = 654321 } }, .root = "0x8ff94c10d39ffa84aa937e2a077239c2742cb425a2a161744a3e9876eb3c7210" },
    };

    // just declare max size on stack memory
    var serializedMax = [_]u8{0} ** 1024;
    var valueMax: [100]ZigContainerType = undefined;
    for (testCases) |tc| {
        const serialized = serializedMax[0..((tc.serializedHex.len - 2) / 2)];
        try fromHex(tc.serializedHex, serialized);
        // TODO: is it an issue having to know the length of the value?
        var value = valueMax[0..tc.value.len];
        try listType.deserializeFromBytes(serialized, value);
        try std.testing.expectEqual(value.len, tc.value.len);

        for (value, tc.value) |*a, *b| {
            try std.testing.expect(elementType.equals(a, b));
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

    // fromJson
    const json =
        \\[
        \\{"a": "0", "b": "0"},
        \\{"a": "123456", "b": "654321"}
        \\]
    ;
    const result = try listType.fromJson(json);
    defer result.deinit();
    const value = result.value;
    try std.testing.expectEqual(value.len, 2);
    try std.testing.expectEqual(value[0].a, 0);
    try std.testing.expectEqual(value[0].b, 0);
    try std.testing.expectEqual(value[1].a, 123456);
    try std.testing.expectEqual(value[1].b, 654321);

    var root = [_]u8{0} ** 32;
    try listType.hashTreeRoot(value, root[0..]);
    const rootHex = try toRootHex(root[0..]);
    try std.testing.expectEqualSlices(u8, rootHex, "0x8ff94c10d39ffa84aa937e2a077239c2742cb425a2a161744a3e9876eb3c7210");
}

test "ListCompositeType - element type is ListBasicType" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    const UintType = @import("./uint.zig").createUintType(2);

    const SSZListBasicType = @import("./list_basic.zig").createListBasicType(UintType);
    const ZigListBasicType = SSZListBasicType.getZigType();

    const ListCompositeType = createListCompositeType(SSZListBasicType);

    var uintType = try UintType.init();
    defer uintType.deinit();
    var elementType = try SSZListBasicType.init(allocator, &uintType, 2, 2);
    defer elementType.deinit();

    var listType = try ListCompositeType.init(allocator, &elementType, 2, 2);
    defer listType.deinit();

    const TestCaseValue = []const u16;
    const TestCase = struct {
        serializedHex: []const u8,
        value: []const TestCaseValue,
        root: []const u8,
    };

    // TODO: make this inline in test
    const test_1_value_0 = [_]u16{ 1, 2 };
    const test_1_value_1 = [_]u16{ 3, 4 };
    const test_1_value_0_slice = test_1_value_0[0..];
    const test_1_value_1_slice = test_1_value_1[0..];

    // const empty: []u16 = ([_]u16{})[0..];

    const testCases = [_]TestCase{
        // empty
        TestCase{ .serializedHex = "0x", .value = &[_]ZigListBasicType{} ** 0, .root = "0x7a0501f5957bdf9cb3a8ff4966f02265f968658b7a9c62642cba1165e86642f5" },
        // 2 full values
        TestCase{ .serializedHex = "0x080000000c0000000100020003000400", .value = &[_]TestCaseValue{ test_1_value_0_slice, test_1_value_1_slice }, .root = "0x58140d48f9c24545c1e3a50f1ebcca85fd40433c9859c0ac34342fc8e0a800b8" },
        // 2 empty values
        // TestCase{ .serializedHex = "0x0800000008000000", .value = &[_]ZigListBasicType{ empty, empty }, .root = "0xe839a22714bda05923b611d07be93b4d707027d29fd9eef7aa864ed587e462ec" },
    };

    // TODO: dedup to the above tests
    // just declare max size on stack memory
    var serializedMax = [_]u8{0} ** 1024;
    // var valueMax: [100]ZigListBasicType = undefined;
    for (testCases) |tc| {
        const serialized = serializedMax[0..((tc.serializedHex.len - 2) / 2)];
        try fromHex(tc.serializedHex, serialized);
        // deserializeFromBytes requries consumers to know the size in advance
        var totalBytes: usize = 0;
        for (tc.value) |*v| {
            totalBytes = totalBytes + v.len;
        }
        var buffer = try allocator.alloc(u16, totalBytes);
        defer allocator.free(buffer);
        var value = try allocator.alloc([]u16, tc.value.len);
        defer allocator.free(value);
        var buffer_offset: usize = 0;
        for (tc.value, 0..) |*v, i| {
            value[i] = buffer[buffer_offset .. buffer_offset + v.len];
            buffer_offset = buffer_offset + v.len;
        }
        try listType.deserializeFromBytes(serialized, value);
        try std.testing.expectEqual(value.len, tc.value.len);

        for (value, tc.value) |a, b| {
            try std.testing.expect(elementType.equals(a, b));
        }
        var root = [_]u8{0} ** 32;
        try listType.hashTreeRoot(value[0..], root[0..]);
        const rootHex = try toRootHex(root[0..]);
        try std.testing.expectEqualSlices(u8, tc.root, rootHex);

        // clone
        const cloned_result = try listType.clone(value);
        defer cloned_result.deinit();
        const value2 = cloned_result.value;
        var root2 = [_]u8{0} ** 32;
        try listType.hashTreeRoot(value2[0..], root2[0..]);
        try std.testing.expectEqualSlices(u8, root2[0..], root[0..]);

        // equals
        try std.testing.expect(listType.equals(value, value2));
    }
}
