const std = @import("std");
const Allocator = std.mem.Allocator;
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
    const BlockBytes = ArrayList(u8);
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
        block_bytes: BlockBytes,

        pub fn init(allocator: *std.mem.Allocator, element_type: *ST, length: usize) !@This() {
            const max_chunk_count = length;
            const chunk_depth = maxChunksToDepth(max_chunk_count);
            const depth = chunk_depth;
            const fixed_size = if (element_type.fixed_size != null) element_type.fixed_size.? * length else null;
            const min_size = ArrayComposite.minSize(element_type, length);
            const max_size = ArrayComposite.maxSize(element_type, length);
            const default_len = length;
            const init_capacity_bytes = ((max_chunk_count + 1) / 2) * 32;

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
                .block_bytes = try BlockBytes.initCapacity(allocator.*, init_capacity_bytes),
            };
        }

        pub fn deinit(self: @This()) void {
            self.block_bytes.deinit();
        }

        pub fn hashTreeRoot(self: *@This(), value: []const ZT, out: []u8) !void {
            if (value.len != self.default_len) {
                return error.InCorrectLen;
            }

            // populate self.block_bytes
            for (value, 0..) |*elem, i| {
                // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                const elem_ptr = if (@typeInfo(@TypeOf(elem.*)) == .Pointer) elem.* else elem;
                try self.element_type.hashTreeRoot(elem_ptr, self.block_bytes.items[i * 32 .. (i + 1) * 32]);
            }

            // zero out the last block if needed
            const value_chunk_bytes = value.len * 32;
            if (value_chunk_bytes < self.block_bytes.items.len) {
                @memset(self.block_bytes.items[value_chunk_bytes..], 0);
            }

            // merkleize the block_bytes
            try merkleize(sha256Hash, self.block_bytes.items[0..], self.max_chunk_count, out);
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

        pub fn equals(self: @This(), a: []const ZT, b: []const ZT) bool {
            return ArrayComposite.valueEquals(self.element_type, a, b);
        }

        pub fn clone(self: @This(), value: []const ZT, out: []ZT) !void {
            try ArrayComposite.valueClone(self.element_type, value, out);
        }
    };

    return VectorCompositeType;
}
