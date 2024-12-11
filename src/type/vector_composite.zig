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

/// Vector: Ordered fixed-length homogeneous collection, with N values
///
/// Array of Composite type:
/// - Composite types always take at least one chunk
/// - Composite types are always returned as views
pub fn createVectorCompositeType(comptime ST: type, comptime ZT: type) type {
    const ArrayComposite = @import("./array_composite.zig").withElementTypes(ST, ZT);
    const ParsedResult = Parsed([]ZT);

    const VectorCompositeType = struct {
        allocator: std.mem.Allocator,
        element_type: *ST,
        depth: usize,
        chunk_depth: usize,
        max_chunk_count: usize,
        fixed_size: ?usize,
        min_size: usize,
        max_size: usize,
        default_len: usize,
        // this should always be a multiple of 64 bytes
        block_bytes: []u8,

        pub fn init(allocator: std.mem.Allocator, element_type: *ST, length: usize) !@This() {
            const max_chunk_count = length;
            const chunk_depth = maxChunksToDepth(max_chunk_count);
            const depth = chunk_depth;
            const fixed_size = if (element_type.fixed_size != null) element_type.fixed_size.? * length else null;
            const min_size = ArrayComposite.minSize(element_type, length);
            const max_size = ArrayComposite.maxSize(element_type, length);
            const default_len = length;
            const blocks_bytes_len = ((max_chunk_count + 1) / 2) * 64;

            return @This(){
                .allocator = allocator,
                .element_type = element_type,
                .depth = depth,
                .chunk_depth = chunk_depth,
                .max_chunk_count = max_chunk_count,
                .fixed_size = fixed_size,
                .min_size = min_size,
                .max_size = max_size,
                .default_len = default_len,
                .block_bytes = try allocator.alloc(u8, blocks_bytes_len),
            };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.block_bytes);
        }

        pub fn hashTreeRoot(self: *@This(), value: []const ZT, out: []u8) HashError!void {
            if (value.len != self.default_len) {
                return error.InCorrectLen;
            }

            // populate self.block_bytes
            for (value, 0..) |*elem, i| {
                // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                const elem_ptr = if (@typeInfo(@TypeOf(elem.*)) == .Pointer) elem.* else elem;
                try self.element_type.hashTreeRoot(elem_ptr, self.block_bytes[i * 32 .. (i + 1) * 32]);
            }

            // zero out the last block if needed
            const value_chunk_bytes = value.len * 32;
            if (value_chunk_bytes < self.block_bytes.len) {
                @memset(self.block_bytes[value_chunk_bytes..], 0);
            }

            // merkleize the block_bytes
            try merkleize(sha256Hash, self.block_bytes, self.max_chunk_count, out);
        }

        // Serialization + deserialization
        pub fn serializedSize(self: @This(), value: []const ZT) usize {
            // TODO: should validate value here? serializeToBytes validate it through
            return ArrayComposite.serializedSize(self.element_type, value);
        }

        pub fn serializeToBytes(self: @This(), value: []const ZT, out: []u8) !usize {
            if (value.len != self.default_len) {
                return error.InCorrectLen;
            }

            const size = self.serializedSize(value);
            if (out.len != size) {
                return error.InCorrectLen;
            }

            return try ArrayComposite.serializeToBytes(self.element_type, value, out);
        }

        pub fn deserializeFromBytes(self: @This(), data: []const u8, out: []ZT) !void {
            try ArrayComposite.deserializeFromBytes(self.allocator, self.element_type, data, out);
        }

        pub fn deserializeFromSlice(self: @This(), arena_allocator: Allocator, data: []const u8, _: ?[]ZT) SszError![]ZT {
            // TODO: validate length
            return try ArrayComposite.deserializeFromSlice(arena_allocator, self.element_type, data, null);
        }

        /// public api
        pub fn fromSsz(self: @This(), ssz: []const u8) SszError!ParsedResult {
            return ArrayComposite.fromSsz(self, ssz);
        }

        pub fn fromJson(self: @This(), json: []const u8) JsonError!ParsedResult {
            return ArrayComposite.fromJson(self, json);
        }

        pub fn clone(self: @This(), value: []const ZT) SszError!ParsedResult {
            return ArrayComposite.clone(self, value);
        }

        /// out parameter is not used because memory is always allocated inside the function
        pub fn deserializeFromJson(self: @This(), arena_allocator: Allocator, source: *Scanner, _: ?[]ZT) JsonError![]ZT {
            return try ArrayComposite.deserializeFromJson(arena_allocator, self.element_type, source, self.default_len, null);
        }

        pub fn equals(self: @This(), a: []const ZT, b: []const ZT) bool {
            return ArrayComposite.itemEquals(self.element_type, a, b);
        }

        pub fn doClone(self: @This(), arena_allocator: Allocator, value: []const ZT, out: ?[]ZT) ![]ZT {
            return try ArrayComposite.itemClone(self.element_type, arena_allocator, value, out);
        }
    };

    return VectorCompositeType;
}

test "fromJson - VectorCompositeType of 4 roots" {
    const allocator = std.testing.allocator;
    const ByteVectorType = @import("./byte_vector_type.zig").ByteVectorType;
    var byteVectorType = try ByteVectorType.init(allocator, 32);
    defer byteVectorType.deinit();

    const VectorCompositeType = createVectorCompositeType(ByteVectorType, []u8);
    var vectorCompositeType = try VectorCompositeType.init(allocator, &byteVectorType, 4);
    defer vectorCompositeType.deinit();
    const json =
        \\[
        \\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        \\"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        \\"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        \\"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        \\]
    ;

    const json_result = try vectorCompositeType.fromJson(json);
    defer json_result.deinit();
    const value = json_result.value;
    // 0xbb = 187, 0xcc = 204, 0xdd = 221, 0xee = 238
    try std.testing.expect(value.len == 4);
    try std.testing.expectEqualSlices(u8, value[0], ([_]u8{187} ** 32)[0..]);
    try std.testing.expectEqualSlices(u8, value[1], ([_]u8{204} ** 32)[0..]);
    try std.testing.expectEqualSlices(u8, value[2], ([_]u8{221} ** 32)[0..]);
    try std.testing.expectEqualSlices(u8, value[3], ([_]u8{238} ** 32)[0..]);
    var root = [_]u8{0} ** 32;
    try vectorCompositeType.hashTreeRoot(value, root[0..]);

    const rootHex = try toRootHex(root[0..]);
    try std.testing.expectEqualSlices(u8, "0x56019bafbc63461b73e21c6eae0c62e8d5b8e05cb0ac065777dc238fcf9604e6", rootHex);
}

test "fromJson - VectorCompositeType of 4 ContainerType({a: uint64Type, b: uint64Type})" {
    const allocator = std.testing.allocator;
    const UintType = @import("./uint.zig").createUintType(8);
    const uintType = try UintType.init();
    defer uintType.deinit();

    const SszType = struct {
        a: UintType,
        b: UintType,
    };
    const ZigType = struct {
        a: u64,
        b: u64,
    };

    const ContainerType = @import("./container.zig").createContainerType(SszType, ZigType, sha256Hash);
    var containerType = try ContainerType.init(allocator, SszType{ .a = uintType, .b = uintType });
    defer containerType.deinit();

    const VectorCompositeType = createVectorCompositeType(ContainerType, ZigType);
    var vectorCompositeType = try VectorCompositeType.init(allocator, &containerType, 4);
    defer vectorCompositeType.deinit();
    const json =
        \\[
        \\{"a": "0", "b": "0"},
        \\{"a": "123456", "b": "654321"},
        \\{"a": "234567", "b": "765432"},
        \\{"a": "345678", "b": "876543"}
        \\]
    ;

    const json_result = try vectorCompositeType.fromJson(json);
    defer json_result.deinit();
    const value = json_result.value;
    try std.testing.expect(value.len == 4);
    try std.testing.expectEqual(0, value[0].a);
    try std.testing.expectEqual(0, value[0].b);
    try std.testing.expectEqual(123456, value[1].a);
    try std.testing.expectEqual(654321, value[1].b);
    try std.testing.expectEqual(234567, value[2].a);
    try std.testing.expectEqual(765432, value[2].b);
    try std.testing.expectEqual(345678, value[3].a);
    try std.testing.expectEqual(876543, value[3].b);
    var root = [_]u8{0} ** 32;
    try vectorCompositeType.hashTreeRoot(value, root[0..]);

    const rootHex = try toRootHex(root[0..]);
    try std.testing.expectEqualSlices(u8, "0xb1a797eb50654748ba239010edccea7b46b55bf740730b700684f48b0c478372", rootHex);
}
