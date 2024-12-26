const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const maxChunksToDepth = @import("hash").maxChunksToDepth;
const merkleize = @import("hash").merkleizeBlocksBytes;
const sha256Hash = @import("hash").sha256Hash;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const HashError = @import("./common.zig").HashError;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const BitArray = @import("./bit_array_value.zig").BitArray;
const getByteBoolArray = @import("./bit_array_value.zig").getByteBoolArray;
const Parsed = @import("./type.zig").Parsed;
const ParsedResult = Parsed(BitArray);
const SingleType = @import("./single.zig").withType(BitArray);

pub fn createBitListType(comptime limit_bits: usize) type {
    const BlockBytes = ArrayList(u8);

    const BitListType = struct {
        allocator: std.mem.Allocator,
        depth: usize,
        chunk_depth: usize,
        fixed_size: ?usize,
        min_size: usize, // +1 for the extra padding bit
        max_size: usize,
        max_chunk_count: usize,
        // this should always be a multiple of 64 bytes
        block_bytes: BlockBytes,
        mix_in_length_block_bytes: []u8,

        pub fn init(allocator: std.mem.Allocator, init_capacity: usize) !@This() {
            const limit_bytes = (limit_bits + 7) / 8;
            const max_chunk_count: usize = (limit_bytes + 31) / 32;
            const chunk_depth = maxChunksToDepth(max_chunk_count);
            // Depth includes the extra level for the length node
            const depth = chunk_depth + 1;
            const fixed_size = null;
            const min_size = 1; // +1 for the extra padding bit
            const max_size = limit_bits + 1; // +1 for the extra padding bit

            return @This(){
                .allocator = allocator,
                .depth = depth,
                .chunk_depth = chunk_depth,
                .fixed_size = fixed_size,
                .min_size = min_size,
                .max_size = max_size,
                .max_chunk_count = max_chunk_count,
                .block_bytes = try BlockBytes.initCapacity(allocator, init_capacity),
                .mix_in_length_block_bytes = try allocator.alloc(u8, 64),
            };
        }

        pub fn deinit(self: *const @This()) void {
            self.block_bytes.deinit();
            self.allocator.free(self.mix_in_length_block_bytes);
        }

        /// public apis
        pub fn hashTreeRoot(self: *@This(), value: *const BitArray, out: []u8) HashError!void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            if (value.bit_len > limit_bits) {
                return error.InCorrectLen;
            }

            const value_data = value.data;
            const value_byte_len = value_data.len;
            const block_len: usize = ((value_byte_len + 63) / 64) * 64;
            try self.block_bytes.resize(block_len);

            @memcpy(self.block_bytes.items[0..value_byte_len], value_data);
            if (value_byte_len < block_len) {
                @memset(self.block_bytes.items[value_byte_len..block_len], 0);
            }

            // TODO: avoid sha256 hard code
            // compute root of chunks
            try merkleize(sha256Hash, self.block_bytes.items[0..block_len], self.max_chunk_count, self.mix_in_length_block_bytes[0..32]);

            // mixInLength
            @memset(self.mix_in_length_block_bytes[32..], 0);
            const slice = std.mem.bytesAsSlice(u64, self.mix_in_length_block_bytes[32..]);
            const len_le = if (native_endian == .big) @byteSwap(value.bit_len) else value.bit_len;
            slice[0] = len_le;

            // final root
            // one for hashTreeRoot(value), one for length
            const chunk_count = 2;
            try merkleize(sha256Hash, self.mix_in_length_block_bytes, chunk_count, out);
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
            return a.bit_len == b.bit_len and std.mem.eql(u8, a.data, b.data);
        }

        // Serialization + deserialization
        pub fn serializedSize(_: *const @This(), value: *const BitArray) usize {
            return bitLenToSerializedLength(value.bit_len);
        }

        /// Serialize the object to bytes, return the number of bytes written
        pub fn serializeToBytes(_: *const @This(), value: *const BitArray, out: []u8) !usize {
            if (value.bit_len > limit_bits) {
                return error.InvalidLength;
            }

            const value_byte_len = (value.bit_len + 7) / 8;
            if (out.len < value_byte_len) {
                return error.InCorrectLen;
            }

            @memcpy(out[0..value_byte_len], value.data);

            // Apply padding bit to a serialized BitList
            if (value.bit_len % 8 == 0) {
                out[value_byte_len] = 1;
                return value_byte_len + 1;
            } else {
                const shift: u3 = @intCast(value.bit_len % 8);
                out[value_byte_len - 1] |= @as(u8, 1) << shift;
                return value_byte_len;
            }
        }

        // TODO: is it necessary to implement deserializeFromBytes

        /// Same to deserializeFromBytes but this returns *T instead of out param
        /// Consumer need to free the memory
        /// out parameter is unused because parent does not allocate, just to conform to the api
        pub fn deserializeFromSlice(_: *const @This(), arena_allocator: Allocator, slice: []const u8, _: ?*BitArray) SszError!*BitArray {
            // TODO: make this reusable when we have tree backed implementation
            const last_byte = slice[slice.len - 1];
            if (last_byte == 0) {
                // Invalid deserialized bitlist, padding bit required
                return error.InvalidSsz;
            }

            if (last_byte == 1) {
                // Remove padding bit
                const ssz_data = slice[0 .. slice.len - 1];
                const result = try BitArray.fromBitLen(arena_allocator, ssz_data.len * 8);
                @memcpy(result.data, ssz_data);
                return result;
            }

            // the last byte is > 1, so a padding bit will exist in the last byte and need to be removed
            const last_byte_bool_array = getByteBoolArray(last_byte);

            // last_byte_bit_len should be > 0 becaues last_byte is > 1 at this point
            var last_byte_bit_len: u3 = 0;
            for (last_byte_bool_array, 0..) |bit, i| {
                if (bit) {
                    last_byte_bit_len = @intCast(i);
                }
            }

            const bit_len = (slice.len - 1) * 8 + last_byte_bit_len;
            const result = try BitArray.fromBitLen(arena_allocator, bit_len);
            @memcpy(result.data, slice);
            const shift_right_bits: u3 = @intCast((8 - @as(u8, last_byte_bit_len)) % 8);
            const max_u8: u8 = 0xFF;
            result.data[slice.len - 1] &= max_u8 >> shift_right_bits;

            return result;
        }

        /// Implementation for parent
        /// Consumer need to free the memory
        /// out parameter is unused because parent does not allocate, just to conform to the api
        pub fn deserializeFromJson(self: *const @This(), arena_allocator: Allocator, source: *Scanner, _: ?[]u8) JsonError!*BitArray {
            const value = try source.next();

            const hex = try switch (value) {
                .string => |v| blk: {
                    break :blk v;
                },
                else => error.InvalidJson,
            };

            const data_byte_len = if (hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) (hex.len - 2) / 2 else hex.len / 2;
            const slice = try arena_allocator.alloc(u8, data_byte_len);
            // should be freed by the consumer using arena_allocator
            try fromHex(hex, slice);

            const res = self.deserializeFromSlice(arena_allocator, slice, null) catch |err| switch (err) {
                else => return error.InvalidJson,
            };
            return res;
        }

        pub fn doClone(_: *const @This(), arena_allocator: Allocator, value: *const BitArray, _: ?*BitArray) !*BitArray {
            if (value.bit_len > limit_bits) {
                return error.InvalidLength;
            }

            const result = try BitArray.fromBitLen(arena_allocator, value.bit_len);
            @memcpy(result.data, value.data);
            return result;
        }
    };

    return BitListType;
}

fn bitLenToSerializedLength(bit_len: usize) usize {
    const bytes = (bit_len + 7) / 8;
    // +1 for the extra padding bit
    return if (bit_len % 8 == 0) bytes + 1 else bytes;
}

// Extra test cases to ensure padding bit is applied correctly
test "BitList padding bit" {
    const TestCase = struct {
        bools: []const bool,
        hex: []const u8,
    };

    const test_cases = [_]TestCase{ .{ .bools = ([_]bool{})[0..], .hex = ([_]u8{0b00000001})[0..] }, .{ .bools = ([_]bool{true})[0..], .hex = ([_]u8{0b11})[0..] }, .{ .bools = ([_]bool{false})[0..], .hex = ([_]u8{0b10})[0..] }, .{ .bools = ([_]bool{true} ** 3)[0..], .hex = ([_]u8{0b1111})[0..] }, .{ .bools = ([_]bool{false} ** 3)[0..], .hex = ([_]u8{0b1000})[0..] }, .{ .bools = ([_]bool{true} ** 8)[0..], .hex = ([_]u8{ 0b11111111, 0b00000001 })[0..] }, .{ .bools = ([_]bool{false} ** 8)[0..], .hex = ([_]u8{ 0b00000000, 0b00000001 })[0..] } };

    const BitList = createBitListType(128);
    const allocator = std.testing.allocator;
    const bit_list_type = try BitList.init(allocator, 1024);
    defer bit_list_type.deinit();

    for (test_cases) |tc| {
        const expected_serialized = tc.hex;
        const bools = tc.bools;

        const bit_array = try BitArray.fromBoolArray(allocator, bools);
        defer bit_array.deinit();

        const size = bit_list_type.serializedSize(bit_array);
        const serialized = try std.testing.allocator.alloc(u8, size);
        defer allocator.free(serialized);
        _ = try bit_list_type.serializeToBytes(bit_array, serialized);

        try std.testing.expect(std.mem.eql(u8, expected_serialized, serialized));

        const bit_array_des = try bit_list_type.deserializeFromSlice(allocator, expected_serialized, null);
        defer bit_array_des.deinit();

        const bit_array_bools = try allocator.alloc(bool, bit_array_des.bit_len);
        defer allocator.free(bit_array_bools);

        try bit_array_des.toBoolArray(bit_array_bools);
        try std.testing.expect(std.mem.eql(bool, bools, bit_array_bools));
    }
}
