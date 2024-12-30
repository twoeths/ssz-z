const std = @import("std");
const zh = @import("./zero_hash.zig");
const toRootHex = @import("util").toRootHex;
const HashError = @import("./sha256.zig").HashError;
const sha256Hash = @import("./sha256.zig").sha256Hash;

pub const HashFn = *const fn (in: []const u8, out: []u8) HashError!void;

pub fn merkleizeBlocksBytes(hashFn: HashFn, data: []u8, chunk_count: usize, out: []u8) !void {
    if (chunk_count < 1) {
        return error.InvalidInput;
    }

    // Compute log2 and store it as f64
    const chunk_count_f64: f64 = @floatFromInt(chunk_count);
    const temp_f64 = std.math.log2(chunk_count_f64);

    // Cast the result of ceil to usize using @intCast
    const layer_count_f64 = @ceil(temp_f64);
    const layer_count: usize = @intFromFloat(layer_count_f64);

    if (data.len == 0) {
        const hash = try zh.getZeroHash(layer_count);
        std.mem.copyForwards(u8, out[0..], hash.*[0..]);
        return;
    }

    if (data.len % 32 != 0) {
        return error.InvalidInput;
    }

    if (chunk_count > 0 and data.len % 64 != 0) {
        return error.InvalidInput;
    }

    // hash into the same buffer
    var buffer_in = data;
    var output_len = data.len / 2;
    var input_len = data.len;

    for (0..layer_count) |i| {
        const buffer_out = data[0..output_len];
        try hashFn(buffer_in, buffer_out);
        const layer_chunk_count = buffer_out.len / 32;
        if (layer_chunk_count % 2 == 1 and i < layer_count - 1) {
            // extend to 1 more chunk
            input_len = output_len + 32;
            buffer_in = data[0..(output_len + 32)];
            std.mem.copyForwards(u8, buffer_in[(buffer_in.len - 32)..], try zh.getZeroHash(i + 1));
        } else {
            buffer_in = buffer_out;
            input_len = output_len;
        }
        output_len = input_len / 2;
    }

    std.mem.copyForwards(u8, out, buffer_in[0..32]);
}

/// Given maxChunkCount return the chunkDepth
/// ```
/// n: [0,1,2,3,4,5,6,7,8,9]
/// d: [0,0,1,2,2,3,3,3,3,4]
/// ```
pub fn maxChunksToDepth(n: usize) usize {
    if (n == 0) return 0;

    // Compute log2(n) and ceil it
    const temp_f64: f64 = @floatFromInt(n);
    const chunk_f64 = std.math.log2(temp_f64);
    const result = std.math.ceil(chunk_f64);
    return @intFromFloat(result);
}

test "merkleizeBlocksBytes" {
    var allocator = std.testing.allocator;
    try zh.initZeroHash(&allocator, 10);
    defer zh.deinitZeroHash();

    const TestCase = struct {
        chunk_count: usize,
        expected: []const u8,
    };

    // TODO: fix commented cases
    const test_cases = comptime [_]TestCase{
        TestCase{ .chunk_count = 0, .expected = "0x0000000000000000000000000000000000000000000000000000000000000000" },
        TestCase{ .chunk_count = 1, .expected = "0x0000000000000000000000000000000000000000000000000000000000000000" },
        TestCase{ .chunk_count = 2, .expected = "0x5c85955f709283ecce2b74f1b1552918819f390911816e7bb466805a38ab87f3" },
        TestCase{ .chunk_count = 3, .expected = "0xee9bc4a60987257d8d2027f6352b676c86ed3c246622b135436eb69314974c7c" },
        TestCase{ .chunk_count = 4, .expected = "0xd35f51699389da7eec7ce5eb02640c6d318cf51ae39eca890bbc7b84ecb5da68" },
        TestCase{ .chunk_count = 5, .expected = "0x26b864a5fd6483296b66858580164a884e7ba8797ebf4c4a2500843b354f438d" },
        TestCase{ .chunk_count = 6, .expected = "0xcc5c078ca453a6a13bfa84c18f111ccb77477bd6284988fc9e414691cdba276d" },
        TestCase{ .chunk_count = 7, .expected = "0x51778544b05e4255d74b710bae7b966a5e5e7a00e3311bcb1a4059053bf9ce01" },
        TestCase{ .chunk_count = 8, .expected = "0x5837f89a763ab800bd3b8de6562aadb4e7ba54da125d1f41a7ebdcdebc977883" },
    };

    inline for (test_cases) |tc| {
        const chunk_count = if (tc.chunk_count >= 1) tc.chunk_count else 1;

        const expected = tc.expected;
        var arrays = [_][32]u8{[_]u8{0} ** 32} ** chunk_count;
        const chunks: [][32]u8 = arrays[0..];
        for (chunks, 0..) |*chunk, i| {
            for (chunk) |*b| {
                b.* = @intCast(i);
            }
        }

        const chunk_with_pad = if (chunk_count % 2 == 1) chunk_count + 1 else chunk_count;
        var all_data = [_]u8{0} ** (32 * chunk_with_pad);
        concatChunks(chunks, &all_data);

        var output: [32]u8 = undefined;
        try merkleizeBlocksBytes(sha256Hash, all_data[0..], chunk_count, output[0..]);
        const hex = try toRootHex(output[0..]);
        try std.testing.expectEqualSlices(u8, expected, hex);
    }
}

fn concatChunks(chunks: []const [32]u8, out: []u8) void {
    for (chunks, 0..) |chunk, i| {
        std.mem.copyForwards(u8, out[i * 32 .. (i + 1) * 32], &chunk);
    }
}

test "maxChunksToDepth" {
    const results = [_]usize{ 0, 0, 1, 2, 2, 3, 3, 3, 3, 4 };
    for (0..results.len) |i| {
        const expected = results[i];
        const actual = maxChunksToDepth(i);
        try std.testing.expectEqual(expected, actual);
    }
}
