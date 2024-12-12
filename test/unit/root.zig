const std = @import("std");
const testing = std.testing;
const list_basic = @import("type/list_basic.zig");
const vector_basic = @import("type/vector_basic.zig");
const container = @import("type/container.zig");
const vector_composite = @import("type/vector_composite.zig");
const list_composite = @import("type/list_composite.zig");

test {
    testing.refAllDecls(list_basic);
    testing.refAllDecls(vector_basic);
    testing.refAllDecls(container);
    testing.refAllDecls(vector_composite);
    testing.refAllDecls(list_composite);
}
