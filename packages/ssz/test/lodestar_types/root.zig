const std = @import("std");
const testing = std.testing;

const phase0 = @import("./phase0.zig");

test {
    testing.refAllDecls(phase0);
}
