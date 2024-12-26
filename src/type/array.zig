const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Scanner = std.json.Scanner;
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const Parsed = @import("./type.zig").Parsed;

/// ST: ssz element type
/// ZT: zig type
pub fn withElementTypes(comptime ST: type, comptime ZT: type) type {
    const ParsedResult = Parsed([]ZT);
    const SingleType = @import("./single.zig").withType([]ZT);
    const Array = struct {
        pub fn fromSsz(self: anytype, ssz: []const u8) SszError!ParsedResult {
            return SingleType.fromSsz(self, ssz);
        }

        pub fn fromJson(self: anytype, json: []const u8) JsonError!ParsedResult {
            return SingleType.fromJson(self, json);
        }

        pub fn clone(self: anytype, value: []const ZT) SszError!ParsedResult {
            return SingleType.clone(self, value);
        }

        pub fn itemEquals(element_type: *const ST, a: []const ZT, b: []const ZT) bool {
            if (a.len != b.len) {
                return false;
            }

            const type_info = @typeInfo(ZT);
            const pass_by_value = type_info == .Pointer or type_info == .Bool or type_info == .Int;

            for (a, b) |*a_elem, *b_elem| {
                // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                const a_elem_ptr = if (pass_by_value) a_elem.* else a_elem;
                const b_elem_ptr = if (pass_by_value) b_elem.* else b_elem;
                if (!element_type.equals(a_elem_ptr, b_elem_ptr)) {
                    return false;
                }
            }

            return true;
        }

        pub fn itemClone(element_type: *ST, arena_allocator: Allocator, value: []const ZT, out: ?[]ZT) ![]ZT {
            const out2 = out orelse try arena_allocator.alloc(ZT, value.len);
            if (out2.len != value.len) {
                return error.InCorrectLen;
            }

            const type_info = @typeInfo(ZT);
            const pass_by_value = type_info == .Pointer or type_info == .Bool or type_info == .Int;

            for (value, out2, 0..) |*elem, *out_elem, i| {
                if (pass_by_value) {
                    // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                    const elem_ptr = elem.*;
                    out2[i] = try element_type.doClone(arena_allocator, elem_ptr, null);
                } else {
                    const elem_ptr = elem;
                    const out_elem_ptr = out_elem;
                    _ = try element_type.doClone(arena_allocator, elem_ptr, out_elem_ptr);
                }
            }

            return out2;
        }
    };

    return Array;
}
