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

/// Vector: Ordered fixed-length homogeneous collection, with N values
///
/// Array of Composite type:
/// - Composite types always take at least one chunk
/// - Composite types are always returned as views
pub fn createVectorCompositeType(comptime ST: type, comptime ZT: type) type {
    const ArrayComposite = @import("./array_composite.zig").withElementTypes(ST, ZT);

    const VectorCompositeType = struct {
        allocator: *std.mem.Allocator,
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

        pub fn init(allocator: *std.mem.Allocator, element_type: *ST, length: usize) !@This() {
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

        pub fn hashTreeRoot(self: *@This(), value: []const ZT, out: []u8) !void {
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

        pub fn deserializeFromSlice(self: @This(), arena_allocator: Allocator, data: []const u8, _: ?[]ZT) ![]ZT {
            // TODO: validate length
            return try ArrayComposite.deserializeFromSlice(arena_allocator, self.element_type, data, null);
        }

        /// public api
        /// TODO: deduplicate with vector_basic.zig
        pub fn fromJson(self: @This(), arena_allocator: Allocator, json: []const u8) ![]ZT {
            var source = Scanner.initCompleteInput(arena_allocator, json);
            defer source.deinit();
            const result = try self.deserializeFromJson(arena_allocator, &source, null);
            const end_document_token = try source.next();
            switch (end_document_token) {
                .end_of_document => {},
                else => return error.InvalidJson,
            }
            return result;
        }

        /// out parameter is not used because memory is always allocated inside the function
        pub fn deserializeFromJson(self: @This(), arena_allocator: Allocator, source: *Scanner, _: ?[]ZT) ![]ZT {
            return try ArrayComposite.deserializeFromJson(arena_allocator, self.element_type, source, self.default_len, null);
        }

        pub fn equals(self: @This(), a: []const ZT, b: []const ZT) bool {
            return ArrayComposite.valueEquals(self.element_type, a, b);
        }

        pub fn clone(self: @This(), value: []const ZT, out: []ZT) !void {
            try ArrayComposite.valueClone(self.element_type, value, out);
        }
    };

    return VectorCompositeType;
}

test "fromJson - VectorCompositeType of 4 roots" {
    var allocator = std.testing.allocator;
    const ByteVectorType = @import("./byte_vector_type.zig").ByteVectorType;
    var byteVectorType = try ByteVectorType.init(&allocator, 32);
    defer byteVectorType.deinit();

    const VectorCompositeType = createVectorCompositeType(ByteVectorType, []u8);
    var vectorCompositeType = try VectorCompositeType.init(&allocator, &byteVectorType, 4);
    defer vectorCompositeType.deinit();
    const json =
        \\[
        \\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        \\"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        \\"0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        \\"0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        \\]
    ;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try vectorCompositeType.fromJson(arena.allocator(), json);
    // 0xbb = 187, 0xcc = 204, 0xdd = 221, 0xee = 238
    try std.testing.expect(value.len == 4);
    try std.testing.expectEqualSlices(u8, value[0], ([_]u8{187} ** 32)[0..]);
    try std.testing.expectEqualSlices(u8, value[1], ([_]u8{204} ** 32)[0..]);
    try std.testing.expectEqualSlices(u8, value[2], ([_]u8{221} ** 32)[0..]);
    try std.testing.expectEqualSlices(u8, value[3], ([_]u8{238} ** 32)[0..]);
    var root = [_]u8{0} ** 32;
    try vectorCompositeType.hashTreeRoot(value, root[0..]);

    // const rootHex = try toRootHex(root[0..]);
    // try std.testing.expectEqualSlices(u8, "0x56019bafbc63461b73e21c6eae0c62e8d5b8e05cb0ac065777dc238fcf9604e6", rootHex);
}