const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Scanner = std.json.Scanner;
const JsonError = @import("./common.zig").JsonError;
const Parsed = @import("./type.zig").Parsed;

/// ST: ssz element type
/// ZT: zig type
pub fn withElementTypes(comptime ST: type, comptime ZT: type) type {
    const Array = struct {
        pub fn fromJson(self: anytype, json: []const u8) JsonError!Parsed([]ZT) {
            const arena = try self.allocator.create(ArenaAllocator);
            arena.* = ArenaAllocator.init(self.allocator);
            const allocator = arena.allocator();

            // must destroy before deinit()
            errdefer self.allocator.destroy(arena);
            errdefer arena.deinit();

            var source = Scanner.initCompleteInput(allocator, json);
            defer source.deinit();
            const result = try self.deserializeFromJson(allocator, &source, null);
            const end_document_token = try source.next();
            switch (end_document_token) {
                .end_of_document => {},
                else => return error.InvalidJson,
            }
            return .{
                .arena = arena,
                .value = result,
            };
        }

        pub fn valueEquals(element_type: *ST, a: []const ZT, b: []const ZT) bool {
            if (a.len != b.len) {
                return false;
            }

            for (a, b) |*a_elem, *b_elem| {
                // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                const a_elem_ptr = if (@typeInfo(@TypeOf(a_elem.*)) == .Pointer) a_elem.* else a_elem;
                const b_elem_ptr = if (@typeInfo(@TypeOf(b_elem.*)) == .Pointer) b_elem.* else b_elem;
                if (!element_type.equals(a_elem_ptr, b_elem_ptr)) {
                    return false;
                }
            }

            return true;
        }

        pub fn valueClone(element_type: *ST, value: []const ZT, out: []ZT) !void {
            for (value, out) |*elem, *out_elem| {
                // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                const elem_ptr = if (@typeInfo(@TypeOf(elem.*)) == .Pointer) elem.* else elem;
                const out_elem_ptr = if (@typeInfo(@TypeOf(out_elem.*)) == .Pointer) out_elem.* else out_elem;
                try element_type.clone(elem_ptr, out_elem_ptr);
            }
        }
    };

    return Array;
}
