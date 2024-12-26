const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

// the same to std.json but here we track *T instead of T
pub fn Parsed(comptime T: type) type {
    const type_info = @typeInfo(T);

    return struct {
        arena: *ArenaAllocator,
        // do not want to use pointer to pointer
        value: if (type_info == .Pointer or type_info == .Bool) T else *T,

        pub fn deinit(self: *const @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}
