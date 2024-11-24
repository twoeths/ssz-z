const std = @import("std");
const testing = std.testing;
const list_basic = @import("type/list_basic.zig");

test "this will pass" {}

test {
    testing.refAllDecls(list_basic);
}
