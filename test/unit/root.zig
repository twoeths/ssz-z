const std = @import("std");
const testing = std.testing;
const list_basic = @import("type/list_basic.zig");
const vector_basic = @import("type/vector_basic.zig");
const container = @import("type/container.zig");

test "this will pass" {}

test {
    testing.refAllDecls(list_basic);
    testing.refAllDecls(vector_basic);
    testing.refAllDecls(container);
}
