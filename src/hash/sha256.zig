const std = @import("std");
const os = std.os;
const assert = std.debug.assert;

const Sha256 = std.crypto.hash.sha2.Sha256;
const Options = Sha256.Options;

threadlocal var buf: [64]u8 = [_]u8{0} ** 64;
pub fn digest64Into(obj1: []const u8, obj2: []const u8, out: *[32]u8) void {
    assert(out.len == 32);
    // Copy obj1 and obj2 into the buffer
    std.mem.copyForwards(u8, buf[0..32], obj1[0..]);
    std.mem.copyForwards(u8, buf[32..64], obj2[0..]);
    Sha256.hash(&buf, out, Options{});
}

pub fn hashInto(in: []const u8, out: []u8) !void {
    if (in.len % 64 != 0) {
        return error.InvalidInput;
    }

    if (in.len != 2 * out.len) {
        return error.InvalidInput;
    }

    for (0..in.len / 64) |i| {
        // calling digest64Into is slow so call Sha256.hash() directly
        const chunkOut: *[32]u8 = @constCast(@ptrCast(out[i * 32 .. (i + 1) * 32]));
        Sha256.hash(in[i * 64 .. (i + 1) * 64], chunkOut, Options{});
    }
}

test "digest64Into works correctly" {
    const obj1: [32]u8 = [_]u8{1} ** 32;
    const obj2: [32]u8 = [_]u8{2} ** 32;
    var hash_result: [32]u8 = undefined;

    // Call the function and ensure it works without error
    digest64Into(&obj1, &obj2, &hash_result);

    // Print the hash for manual inspection (optional)
    // std.debug.print("Hash value: {any}\n", .{hash_result});
    // std.debug.print("Hash hex: {s}\n", .{std.fmt.bytesToHex(hash_result, .lower)});
    // try std.testing.expect(mem.eql(u8, &hash_result, &expected_hash));
}

test "hashInto" {
    const in = [_]u8{1} ** 128;
    var out: [64]u8 = undefined;
    try hashInto(&in, &out);
    // std.debug.print("@@@ out: {any}\n", .{out});
    var out2: [32]u8 = undefined;
    digest64Into(in[0..32], in[32..64], &out2);
    // std.debug.print("@@@ out2: {any}\n", .{out2});
    try std.testing.expectEqualSlices(u8, out2[0..], out[0..32]);
    try std.testing.expectEqualSlices(u8, out2[0..], out[32..64]);
}
