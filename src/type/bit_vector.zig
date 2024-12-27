const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const maxChunksToDepth = @import("hash").maxChunksToDepth;
const merkleize = @import("hash").merkleizeBlocksBytes;
const sha256Hash = @import("hash").sha256Hash;
const fromHex = @import("util").fromHex;
const BitArray = @import("./bit_array_value.zig").BitArray;
const Parsed = @import("./type.zig").Parsed;
const ParsedResult = Parsed(BitArray);
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const HashError = @import("./common.zig").HashError;
const SingleType = @import("./single.zig").withType(BitArray);

/// BitVector: ordered fixed-length collection of boolean values, with N bits
/// - Notation: `Bitvector[N]`
/// - Value: `BitArray`, @see BitArray for a justification of its memory efficiency and performance
pub const BitVectorType = struct {
    allocator: std.mem.Allocator,
    bit_len: usize,
    chunk_count: usize,
    depth: usize,
    // make it optional to be compatible with other types
    fixed_size: ?usize,
    min_size: usize,
    max_size: usize,
    max_chunk_count: usize,
    /// Mask to check if trailing bits are zero'ed. Mask returns bits that must be zero'ed
    /// ```
    /// lengthBits % 8 | zeroBitsMask
    /// 0              | 0
    /// 1              | 11111110
    /// 2              | 11111100
    /// 7              | 10000000
    /// ```
    zero_bit_mask: u8,
    // this should always be a multiple of 64 bytes
    block_bytes: []u8,

    /// Zig Type definition
    pub fn getZigType() type {
        return BitArray;
    }

    pub fn getZigTypeAlignment() usize {
        return @alignOf(BitArray);
    }

    pub fn init(allocator: std.mem.Allocator, comptime length_bits: usize) !@This() {
        if (length_bits <= 0) {
            return error.InvalidLength;
        }

        const length_bytes = (length_bits + 7) / 8;
        const chunk_count = (length_bytes + 31) / 32;
        const max_chunk_count = chunk_count;
        const depth = maxChunksToDepth(max_chunk_count);
        const fixed_size = length_bytes;
        const min_size = fixed_size;
        const max_size = fixed_size;
        const zero_bit_mask: u8 = if (length_bits % 8 == 0) 0 else @as(u8, 0xff << (length_bits % 8));
        const block_bytes_len = ((max_chunk_count + 1) / 2) * 64;

        return @This(){
            .allocator = allocator,
            .bit_len = length_bits,
            .chunk_count = chunk_count,
            .depth = depth,
            .fixed_size = fixed_size,
            .min_size = min_size,
            .max_size = max_size,
            .max_chunk_count = max_chunk_count,
            .zero_bit_mask = zero_bit_mask,
            .block_bytes = try allocator.alloc(u8, block_bytes_len),
        };
    }

    pub fn deinit(self: *const @This()) void {
        self.allocator.free(self.block_bytes);
    }

    /// public apis
    pub fn hashTreeRoot(self: *@This(), value: *const BitArray, out: []u8) HashError!void {
        if (out.len != 32) {
            return error.InCorrectLen;
        }
        const value_data = value.data;

        if (value_data.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        @memcpy(self.block_bytes[0..value_data.len], value_data);
        if (value_data.len < self.block_bytes.len) {
            @memset(self.block_bytes[value_data.len..], 0);
        }

        // chunks root
        try merkleize(sha256Hash, self.block_bytes, self.max_chunk_count, out);
    }

    pub fn fromSsz(self: *const @This(), ssz: []const u8) SszError!ParsedResult {
        return SingleType.fromSsz(self, ssz);
    }

    pub fn fromJson(self: *const @This(), json: []const u8) JsonError!ParsedResult {
        return SingleType.fromJson(self, json);
    }

    pub fn clone(self: *const @This(), value: *const BitArray) SszError!ParsedResult {
        return SingleType.clone(self, value);
    }

    pub fn equals(_: *const @This(), a: *const BitArray, b: *const BitArray) bool {
        return std.mem.eql(u8, a.data, b.data);
    }

    // Serialization + deserialization
    // unused param but want to follow the same interface as other types
    pub fn serializedSize(self: *const @This(), _: *const BitArray) usize {
        return self.fixed_size;
    }

    /// Serialize the object to bytes, return the number of bytes written
    pub fn serializeToBytes(self: *@This(), value: *const BitArray, out: []u8) !usize {
        if (value.bit_len != self.bit_len) {
            return error.InvalidLength;
        }

        if (self.fixed_size != null and out.len < self.fixed_size.?) {
            return error.InCorrectLen;
        }

        @memcpy(out, value.data);
        return self.fixed_size.?;
    }

    pub fn deserializeFromBytes(self: *const @This(), bytes: []const u8, out: *BitArray) !void {
        if (bytes.len != self.fixed_size or out.bit_len != self.bit_len) {
            return error.InCorrectLen;
        }

        @memcpy(out.data, bytes);
    }

    /// Same to deserializeFromBytes but this returns *T instead of out param
    /// Consumer need to free the memory
    /// out parameter is unused because parent does not allocate, just to conform to the api
    pub fn deserializeFromSlice(self: *const @This(), arena_allocator: Allocator, slice: []const u8, _: ?*BitArray) SszError!*BitArray {
        if (slice.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        const result = try BitArray.fromBitLen(arena_allocator, self.bit_len);
        @memcpy(result.data, slice);
        return result;
    }

    /// Implementation for parent
    /// Consumer need to free the memory
    /// out parameter is unused because parent does not allocate, just to conform to the api
    pub fn deserializeFromJson(self: *const @This(), arena_allocator: Allocator, source: *Scanner, _: ?[]u8) JsonError!*BitArray {
        const value = try source.next();
        const result = try BitArray.fromBitLen(arena_allocator, self.bit_len);
        try switch (value) {
            .string => |v| {
                try fromHex(v, result.data);
            },
            else => error.InvalidJson,
        };

        return result;
    }

    pub fn doClone(self: *const @This(), arena_allocator: Allocator, value: *const BitArray, _: ?*BitArray) !*BitArray {
        if (value.bit_len != self.bit_len) {
            return error.InvalidLength;
        }

        const result = try BitArray.fromBitLen(arena_allocator, self.bit_len);
        @memcpy(result.data, value.data);
        return result;
    }
};
