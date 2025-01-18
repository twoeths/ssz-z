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
/// consumer can use stack allocation for bit_array
pub fn populateBitArray(bit_array: []bool, gindex: u64) Error!u8 {
    const total_num_bits = numBits(gindex);
    if (bit_array.len < total_num_bits) {
        return error.TooFewBits;
    }
    var buf8: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf8, gindex, .little);
    // bits written starts from the right
    var num_bits_written: usize = 0;
    // byte_idx starts from the right most byte due to big endian
    outer: for (buf8, 0..) |byte, byte_idx| {
        const booleans_in_byte = getByteBoolArray(byte);
        // only the last `num_bits` bits have value
        //                         num_bits    num_bits_written
        // |-------- ... ---------|-----------|----------------|
        const num_bits: usize = @intCast(@min(total_num_bits - byte_idx * 8, 8));
        // write to the last num_bits except for num_bits_written
        for (booleans_in_byte[(8 - num_bits)..], 0..) |bit, bit_idx| {
            const global_bit_idx = total_num_bits - num_bits_written - num_bits + bit_idx;
            bit_array[global_bit_idx] = bit;
        }
        num_bits_written += num_bits;
        if (num_bits_written >= total_num_bits) {
            break :outer;
        }
    }

    return total_num_bits;
}

pub fn numBits(value: u64) u8 {
    if (value == 0) return 0;
    return 64 - @clz(value);
}

// expected result is the same to NodeJS Number.toString(2)
test "populateBitArray" {
    const TestCase = struct {
        gindex: u64,
        num_bits: u8,
        expected: []const bool,
    };

    const tcs = [_]TestCase{
        // 5 = 0b101
        .{ .gindex = 5, .num_bits = 3, .expected = &.{ true, false, true } },
        // 42 = 0b101010
        .{ .gindex = 42, .num_bits = 6, .expected = &.{ true, false, true, false, true, false } },
        // 1024 = 0b10000000000
        .{ .gindex = 1024, .num_bits = 11, .expected = &.{ true, false, false, false, false, false, false, false, false, false, false } },
        // 1025 = 0b10000000001
        .{ .gindex = 1025, .num_bits = 11, .expected = &.{ true, false, false, false, false, false, false, false, false, false, true } },
        // 1_000_000 = 0b11110100001001000000
        .{ .gindex = 1_000_000, .num_bits = 20, .expected = &.{ true, true, true, true, false, true, false, false, false, false, true, false, false, true, false, false, false, false, false, false } },
    };
    for (tcs[0..]) |tc| {
        var bit_array: [64]bool = [_]bool{false} ** 64;
        const num_bits = try populateBitArray(bit_array[0..], tc.gindex);
        try expect(num_bits == tc.num_bits);
        try std.testing.expectEqualSlices(bool, tc.expected, bit_array[0..num_bits]);
    }
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
