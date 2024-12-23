const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BitArray = struct {
    allocator: Allocator,
    /// Underlying BitArray Uint8Array data
    data: []u8,
    // Immutable bitLen of this BitArray
    bit_len: usize,

    pub fn init(allocator: Allocator, data: []u8, bit_len: usize) !*@This() {
        if (data.len != (bit_len + 7) / 8) {
            return error.InCorrectLen;
        }

        var instance = try allocator.create(@This());
        instance.allocator = allocator;
        instance.data = data;
        instance.bit_len = bit_len;

        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.data);
        self.allocator.destroy(self);
    }

    /// Returns a zero'ed BitArray of `bit_len`
    pub fn fromBitLen(allocator: Allocator, bit_len: usize) !*@This() {
        const byte_len = (bit_len + 7) / 8;
        const data = try allocator.alloc(u8, byte_len);
        for (data) |*byte| {
            byte.* = 0;
        }
        return try init(allocator, data, bit_len);
    }

    /// Returns a BitArray of `bitLen` with a single bit set to true at position `bit_index`
    pub fn fromSingleBit(allocator: Allocator, bit_len: usize, bit_index: usize) !*@This() {
        const bit_array = try fromBitLen(allocator, bit_len);
        try bit_array.set(bit_index, true);
        return bit_array;
    }

    /// Returns a BitArray from an array of booleans representation
    pub fn fromBoolArray(allocator: Allocator, bool_array: []const bool) !*@This() {
        const bit_len = bool_array.len;
        const bit_array = try fromBitLen(allocator, bit_len);
        for (bool_array, 0..) |bit, i| {
            try bit_array.set(i, bit);
        }
        return bit_array;
    }

    /// consumer should free the returned BitArray
    pub fn clone(self: *const @This()) !*@This() {
        const data = try self.allocator.alloc(u8, self.data.len);
        @memcpy(data, self.data);
        return try init(self.allocator, data, self.bit_len);
    }

    /// Get bit value at index `bit_index`
    pub fn get(self: *const @This(), bit_index: usize) !bool {
        if (bit_index >= self.bit_len) {
            return error.OutOfRange;
        }

        const byte_idx = bit_index / 8;
        const offset_in_byte = bit_index % 8;
        const mask = 1 << offset_in_byte;
        return (self.data[byte_idx] & mask) == mask;
    }

    /// Set bit value at index `bit_index`
    pub fn set(self: *@This(), bit_index: usize, bit: bool) !void {
        if (bit_index >= self.bit_len) {
            return error.OutOfRange;
        }

        const byte_index = bit_index / 8;
        const offset_in_byte: u3 = @intCast(bit_index % 8);
        const mask = @as(u8, 1) << offset_in_byte;
        var byte = self.data[byte_index];
        if (bit) {
            // For bit in byte, 1,0 OR 1 = 1
            // byte 100110
            // mask 010000
            // res  110110
            byte |= mask;
            self.data[byte_index] = byte;
        } else {
            // For bit in byte, 1,0 OR 1 = 0
            if ((byte & mask) == mask) {
                // byte 110110
                // mask 010000
                // res  100110
                byte ^= mask;
                self.data[byte_index] = byte;
            } else {
                // Ok, bit is already 0
            }
        }
    }

    /// Merge two BitArray bitfields with OR. Must have the same bit_len
    pub fn mergeOrWith(self: *@This(), bit_array_2: *const @This()) !void {
        if (self.bit_len != bit_array_2.bit_len) {
            return error.InCorrectLen;
        }

        for (self.data, bit_array_2.data) |*byte1, byte2| {
            byte1.* = byte1.* | byte2;
        }
    }

    /// Returns an array with the indexes which have a bit set to true
    pub fn intersectValues(self: *const @This(), comptime T: type, values: []T, out: []T) !usize {
        if (self.bit_len != values.len or values.len != out.len) {
            return error.InCorrectLen;
        }

        var count = 0;
        outer: for (self.data, 0..) |byte, i_byte| {
            const booleans_in_byte = getByteBoolArray(byte);
            for (booleans_in_byte, 0..) |bit, i_bit| {
                const bit_idx = i_byte * 8 + i_bit;
                if (bit_idx >= self.bit_len) {
                    break :outer;
                }

                if (bit) {
                    out[count] = values[bit_idx];
                    count += 1;
                }
            }
        }

        return count;
    }

    /// Returns the positions of all bits that are set to true
    pub fn getTrueBitIndexes(self: *const @This(), out: []usize) !usize {
        if (self.bit_len != out.len) {
            return error.InCorrectLen;
        }

        var count = 0;
        outer: for (self.data, 0..) |byte, i_byte| {
            const booleans_in_byte = getByteBoolArray(byte);
            for (booleans_in_byte, 0..) |bit, i_bit| {
                const bit_idx = i_byte * 8 + i_bit;
                if (bit_idx >= self.bit_len) {
                    break :outer;
                }

                if (bit) {
                    out[count] = bit_idx;
                    count += 1;
                }
            }
        }
    }

    /// Return the position of a single bit set or error
    pub fn getSingleTrueBit(self: *const @This()) !usize {
        var found: bool = false;
        var result: usize = -1;
        outer: for (self.data, 0..) |byte, i_byte| {
            const booleans_in_byte = getByteBoolArray(byte);
            for (booleans_in_byte, 0..) |bit, i_bit| {
                const bit_idx = i_byte * 8 + i_bit;
                if (bit_idx >= self.bit_len) {
                    break :outer;
                }

                if (bit and found) {
                    return error.MoreThanOneBitSet;
                }
                found = true;
                result = bit_idx;
            }
        }

        if (found and result != -1) {
            return result;
        } else {
            return error.NoBitSet;
        }
    }

    pub fn toBoolArray(self: *const @This(), out: []bool) !void {
        if (self.bit_len != out.len) {
            return error.InCorrectLen;
        }

        outer: for (self.data, 0..) |byte, i_byte| {
            const booleans_in_byte = getByteBoolArray(byte);
            for (booleans_in_byte, 0..) |bit, i_bit| {
                const bit_idx = i_byte * 8 + i_bit;
                if (bit_idx >= self.bit_len) {
                    break :outer;
                }

                out[bit_idx] = bit;
            }
        }
    }
};

/// Globally cache this information
/// 1 => [true false false false false false false false]
/// 5 => [true false true false false fase false false]
var byteToBitBooleanArrays: [256]?[8]bool = [_]?[8]bool{null} ** 256;

pub fn getByteBoolArray(byte: u8) [8]bool {
    const value = byteToBitBooleanArrays[byte];
    return if (value == null) {
        var value2 = [_]bool{false} ** 8;
        for (0..8) |bit| {
            // little endian
            const to_shift: u3 = @intCast(bit);
            value2[bit] = (byte & (@as(u8, 1) << to_shift)) != 0;
        }
        byteToBitBooleanArrays[byte] = value2;
        return value2;
    } else value.?;
}
