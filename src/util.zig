const std = @import("std");

var buffer = [_]u8{0} ** 64;

pub fn toRootHex(root: []const u8) ![]u8 {
    if (root.len != 32) {
        return error.InvalidInput;
    }

    // const writer = std.io.fixedBufferStream(buffer[0..]).writer();

    var stream = std.io.fixedBufferStream(&buffer); // Mutable stream object
    const writer = stream.writer(); // Get a mutable writer from the stream

    for (root) |b| {
        try std.fmt.format(writer, "{x:0>2}", .{b});
    }
    return buffer[0..];
}

test "toRootHex" {
    const TestCase = struct {
        root: []const u8,
        expected: []const u8,
    };

    const test_cases = [_]TestCase{
        TestCase{ .root = &[_]u8{0} ** 32, .expected = "0000000000000000000000000000000000000000000000000000000000000000" },
        TestCase{ .root = &[_]u8{10} ** 32, .expected = "0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a" },
        TestCase{ .root = &[_]u8{17} ** 32, .expected = "1111111111111111111111111111111111111111111111111111111111111111" },
        TestCase{ .root = &[_]u8{255} ** 32, .expected = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" },
    };

    for (test_cases) |tc| {
        const hex = try toRootHex(tc.root);
        try std.testing.expectEqualSlices(u8, tc.expected, hex);
    }
}
