const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

// the same to std.json but here we track *T instead of T
pub fn Parsed(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: *T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}
