const std = @import("std");
const expect = std.testing.expect;

/// Globally cache this information
/// 1 => [true false false false false false false false]
/// 5 => [true false true false false fase false false]
/// 42 => [true false true false true false false false] = 0b101010
var byteToBitBooleanArrays: [256]?[8]bool = [_]?[8]bool{null} ** 256;

pub const Error = error{
    TooFewBits,
};

/// equivalent version of javascript's Number.toString(2)
/// it returns big-endian format
pub fn getByteBoolArray(byte: u8) [8]bool {
    const value = byteToBitBooleanArrays[byte];
    return if (value == null) {
        var value2 = [_]bool{false} ** 8;
        for (0..8) |bit| {
            const to_shift: u3 = @intCast(bit);
            value2[7 - bit] = (byte & (@as(u8, 1) << to_shift)) != 0;
        }
        byteToBitBooleanArrays[byte] = value2;
        return value2;
    } else value.?;
}

/// given a big bit_array and a gindex, populate the bit_array with the bits of gindex using getByteBoolArray
/// return the total number of bits populated
/// note that this is big-endian, which is the same to javascript's Number.toString(2)
pub fn populateBitArray(bit_array: []bool, gindex: u64) Error!u8 {
    const total_num_bits = numBits(gindex);
    if (bit_array.len < total_num_bits) {
        return error.TooFewBits;
    }
    var buf8: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf8, gindex, .little);
    outer: for (buf8, 0..) |byte, i| {
        const booleans_in_byte = getByteBoolArray(byte);
        // only the last `num_bits` bits have value
        const num_bits: usize = @intCast(total_num_bits - i * 8);
        for (booleans_in_byte[(8 - num_bits)..], 0..) |bit, j| {
            const bit_idx = i * 8 + j;
            bit_array[bit_idx] = bit;
            if (bit_idx >= total_num_bits - 1) {
                break :outer;
            }
        }
    }

    return total_num_bits;
}

pub fn numBits(value: u64) u8 {
    if (value == 0) return 0;
    return 64 - @clz(value);
}

test "populateBitArray" {
    var bit_array: [64]bool = [_]bool{false} ** 64;
    // 5 = 0b101
    var num_bits = try populateBitArray(bit_array[0..], 5);
    try expect(num_bits == 3);
    try std.testing.expectEqualSlices(bool, &[_]bool{ true, false, true }, bit_array[0..num_bits]);
    // 42 = 0b101010
    num_bits = try populateBitArray(bit_array[0..], 42);
    try expect(num_bits == 6);
    try std.testing.expectEqualSlices(bool, &[_]bool{ true, false, true, false, true, false }, bit_array[0..num_bits]);
}

test "numBits" {
    try expect(numBits(0) == 0);
    try expect(numBits(1) == 1);
    // 42 = 0b101010
    try expect(numBits(42) == 6);
    // 64 = 0b1000000
    try expect(numBits(64) == 7);
}

test "getByteBoolArray" {
    // // 5 = 0b101
    var booleans = getByteBoolArray(5);
    try std.testing.expectEqualSlices(bool, &[_]bool{ false, false, false, false, false, true, false, true }, booleans[0..]);
    // 42 = 0b101010
    booleans = getByteBoolArray(42);
    try std.testing.expectEqualSlices(bool, &[_]bool{ false, false, true, false, true, false, true, false }, booleans[0..]);
}
