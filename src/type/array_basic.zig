const std = @import("std");
const Allocator = std.mem.Allocator;
const array = @import("./array.zig").withElementTypes;

/// ST: ssz element type
/// ZT: zig type
pub fn withElementTypes(comptime ST: type, comptime ZT: type) type {
    const Array = array(ST, ZT);
    const ArrayBasic = struct {
        pub fn serializeToBytes(element_type: *ST, value: []const ZT, out: []u8) !usize {
            const elem_byte_length = element_type.byte_length;
            const byte_len = elem_byte_length * value.len;
            if (byte_len != out.len) {
                return error.InCorrectLen;
            }

            for (value, 0..) |*elem, i| {
                _ = try element_type.serializeToBytes(elem, out[i * elem_byte_length .. (i + 1) * elem_byte_length]);
            }

            return byte_len;
        }

        pub fn deserializeFromBytes(element_type: *ST, data: []const u8, out: []ZT) !void {
            const elem_byte_length = element_type.byte_length;
            if (data.len % elem_byte_length != 0) {
                return error.InCorrectLen;
            }

            const elem_count = data.len / elem_byte_length;
            if (elem_count != out.len) {
                return error.InCorrectLen;
            }

            for (out, 0..) |*elem, i| {
                try element_type.deserializeFromBytes(data[i * elem_byte_length .. (i + 1) * elem_byte_length], elem);
            }
        }

        pub fn deserializeFromSlice(arenaAllocator: Allocator, element_type: *ST, data: []const u8, _: ?[]ZT) ![]ZT {
            const elem_byte_length = element_type.byte_length;
            if (data.len % elem_byte_length != 0) {
                return error.InCorrectLen;
            }

            const elem_count = data.len / elem_byte_length;
            const result = try arenaAllocator.alloc(ZT, elem_count);
            for (result, 0..) |*elem, i| {
                // TODO: how to avoid the copy?
                // improve this when we have benchmark test
                elem.* = (try element_type.deserializeFromSlice(arenaAllocator, data[i * elem_byte_length .. (i + 1) * elem_byte_length])).*;
            }

            return result;
        }

        pub fn valueEquals(element_type: *ST, a: []const ZT, b: []const ZT) bool {
            return Array.valueEquals(element_type, a, b);
        }

        pub fn valueClone(element_type: *ST, value: []const ZT, out: []ZT) !void {
            return Array.valueClone(element_type, value, out);
        }
    };

    return ArrayBasic;
}
