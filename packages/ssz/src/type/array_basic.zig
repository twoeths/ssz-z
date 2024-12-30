const std = @import("std");
const Allocator = std.mem.Allocator;
const Scanner = std.json.Scanner;
const ArrayList = std.ArrayList;
const Token = std.json.Token;
const array = @import("./array.zig").withElementTypes;
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const Parsed = @import("./type.zig").Parsed;

/// ST: ssz element type
/// ZT: zig type
pub fn withElementTypes(comptime ST: type, comptime ZT: type) type {
    const Array = array(ST, ZT);
    const ParsedResult = Parsed([]ZT);

    const ArrayBasic = struct {
        pub fn fromSsz(self: anytype, data: []const u8) SszError!ParsedResult {
            return Array.fromSsz(self, data);
        }

        pub fn fromJson(self: anytype, json: []const u8) JsonError!ParsedResult {
            return Array.fromJson(self, json);
        }

        pub fn clone(self: anytype, value: []const ZT) SszError!ParsedResult {
            return Array.clone(self, value);
        }

        pub fn serializeToBytes(element_type: *const ST, value: []const ZT, out: []u8) !usize {
            const elem_byte_length = element_type.byte_length;
            const byte_len = elem_byte_length * value.len;

            // out.len is not necessarily the same to byte_len

            for (value, 0..) |elem, i| {
                _ = try element_type.serializeToBytes(elem, out[i * elem_byte_length .. (i + 1) * elem_byte_length]);
            }

            return byte_len;
        }

        pub fn deserializeFromBytes(element_type: *const ST, data: []const u8, out: []ZT) JsonError!void {
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

        /// consumer need to free the memory
        /// out parameter is unused because it's always allocated inside the function
        pub fn deserializeFromSlice(arenaAllocator: Allocator, element_type: *const ST, data: []const u8, expected_len: ?usize, _: ?[]ZT) SszError![]ZT {
            const elem_byte_length = element_type.byte_length;
            if (data.len % elem_byte_length != 0) {
                return error.InCorrectLen;
            }

            const elem_count = data.len / elem_byte_length;
            if (expected_len != null and elem_count != expected_len.?) {
                return error.InCorrectLen;
            }

            const result = try arenaAllocator.alloc(ZT, elem_count);
            // TODO: use std.mem.bytesAsSlice() once for better performance?
            for (result, 0..) |*elem, i| {
                // improve this when we have benchmark test
                elem.* = (try element_type.deserializeFromSlice(arenaAllocator, data[i * elem_byte_length .. (i + 1) * elem_byte_length], null));
            }

            return result;
        }

        /// consumer need to free the memory
        /// out parameter is unused because it's always allocated inside the function
        pub fn deserializeFromJson(arena_allocator: Allocator, element_type: *const ST, source: *Scanner, expected_len: ?usize, _: ?[]ZT) ![]ZT {
            // validate start array token "["
            const start_array_token = try source.next();
            if (start_array_token != Token.array_begin) {
                return error.InvalidJson;
            }

            // Typical array, handle same to std.json.static.zig
            var arraylist = ArrayList(ZT).init(arena_allocator);
            while (true) {
                switch (try source.peekNextTokenType()) {
                    .array_end => {
                        _ = try source.next();
                        break;
                    },
                    else => {},
                }

                try arraylist.ensureUnusedCapacity(1);
                const elem = try element_type.deserializeFromJson(arena_allocator, source, null);
                arraylist.appendAssumeCapacity(elem);

                if (expected_len != null and arraylist.items.len > expected_len.?) {
                    return error.InCorrectLen;
                }
            }

            if (expected_len != null and arraylist.items.len != expected_len.?) {
                return error.InCorrectLen;
            }

            return arraylist.toOwnedSlice();
        }

        pub fn itemEquals(element_type: *const ST, a: []const ZT, b: []const ZT) bool {
            return Array.itemEquals(element_type, a, b);
        }

        pub fn itemClone(element_type: *const ST, arena_allocator: Allocator, value: []const ZT, out: ?[]ZT) ![]ZT {
            return Array.itemClone(element_type, arena_allocator, value, out);
        }
    };

    return ArrayBasic;
}
