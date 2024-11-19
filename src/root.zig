const std = @import("std");
const testing = std.testing;
// TODO: file exists in multiple modules
// pub const merkleizeBlocksBytes = @import("hash/merkleize.zig");
pub const createUintType = @import("type/uint.zig").createUintType;
pub const createContainerType = @import("type/container.zig").createContainerType;
pub const createByteListType = @import("type/byte_list.zig").createByteListType;
pub const createListBasicType = @import("type/list_basic.zig").createListBasicType;
pub const createVectorBasicType = @import("type/vector_basic.zig").createVectorBasicType;

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
