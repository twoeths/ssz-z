const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const Parsed = @import("./type.zig").Parsed;
const ParsedResult = Parsed(bool);
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const HashError = @import("./common.zig").HashError;
const SingleType = @import("./single.zig").withType(bool);

pub const BooleanType = struct {
    byte_len: usize,
    items_per_chunk: usize,
    fixed_size: ?usize,
    min_size: usize,
    max_size: usize,

    /// Zig type definition
    pub fn getZigType() type {
        return bool;
    }

    pub fn getViewDUType() type {
        return bool;
    }

    pub fn getZigTypeAlignment() usize {
        return 1;
    }

    pub fn init() @This() {
        return @This(){ .fixed_size = 1, .byte_len = 1, .items_per_chunk = 32, .min_size = 1, .max_size = 1 };
    }

    pub fn deinit(_: *const @This()) void {
        // do nothing
    }

    pub fn hashTreeRoot(self: *const @This(), value: bool, out: []u8) !void {
        if (out.len != 32) {
            return error.InCorrectLen;
        }
        _ = try self.serializeToBytes(value, out);
    }

    pub fn fromSsz(self: *const @This(), ssz: []const u8) SszError!ParsedResult {
        return SingleType.fromSsz(self, ssz);
    }

    pub fn fromJson(self: *const @This(), json: []const u8) JsonError!ParsedResult {
        return SingleType.fromJson(self, json);
    }

    pub fn clone(self: *const @This(), value: bool) SszError!ParsedResult {
        return SingleType.clone(self, value);
    }

    pub fn equals(_: *const @This(), a: bool, b: bool) bool {
        return a == b;
    }

    // Serialization + deserialization

    // unused param but want to follow the same interface as other types
    pub fn serializedSize(_: *const @This(), _: bool) usize {
        return 1;
    }

    pub fn serializeToBytes(_: *const @This(), value: bool, out: []u8) !usize {
        out[0] = if (value) 1 else 0;
        return 1;
    }

    // TODO: consider if it's necessary to implement deserializeFromBytes
    // out and arena_allocator parameter is just to conform to the interface
    pub fn deserializeFromSlice(_: *const @This(), _: Allocator, slice: []const u8, _: ?bool) SszError!bool {
        if (slice.len == 0) {
            return error.InCorrectLen;
        }
        return switch (slice[0]) {
            0 => false,
            1 => true,
            else => error.InvalidSsz,
        };
    }

    /// an implementation for parent types
    /// arena_allocator and out parameters are just to conform to the interface
    pub fn deserializeFromJson(_: *const @This(), _: Allocator, source: *Scanner, _: ?bool) JsonError!bool {
        const value = try source.next();
        return switch (value) {
            .true => return true,
            .false => return false,
            else => error.InvalidJson,
        };
    }

    pub fn doClone(_: *const @This(), _: Allocator, value: bool, _: ?bool) !bool {
        return value;
    }
};
