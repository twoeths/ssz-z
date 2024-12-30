const std = @import("std");
const testing = std.testing;
const list_basic = @import("type/list_basic.zig");
const vector_basic = @import("type/vector_basic.zig");
const container = @import("type/container.zig");
const vector_composite = @import("type/vector_composite.zig");
const list_composite = @import("type/list_composite.zig");
const bit_vector = @import("type/bit_vector.zig");
const bit_list = @import("type/bit_list.zig");
const byte_list = @import("type/byte_list.zig");

test {
    testing.refAllDecls(list_basic);
    testing.refAllDecls(vector_basic);
    testing.refAllDecls(container);
    testing.refAllDecls(vector_composite);
    testing.refAllDecls(list_composite);
    testing.refAllDecls(bit_vector);
    testing.refAllDecls(bit_list);
    testing.refAllDecls(byte_list);
}
