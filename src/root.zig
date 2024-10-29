const std = @import("std");
const testing = std.testing;
pub const merkleizeInto = @import("hash/merkleize.zig");

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
    std.debug.print("add(3, 7) == 10\n", .{});
}

test {
    testing.refAllDecls(@This());
}
