const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const HashError = @import("./common.zig").HashError;
const Parsed = @import("./type.zig").Parsed;

pub fn createUintType(comptime num_bytes: usize) type {
    if (num_bytes != 1 and num_bytes != 2 and num_bytes != 4 and num_bytes != 8 and num_bytes != 16 and num_bytes != 32 and num_bytes != 64) {
        @compileError("Only support num_bytes of 1, 2, 4 or 8 bytes");
    }

    const T = switch (num_bytes) {
        1 => u8,
        2 => u16,
        4 => u32,
        8 => u64,
        16 => u128,
        32 => u256,
        64 => u512,
        else => unreachable,
    };
    const SingleType = @import("./single.zig").withType(T);
    const ParsedResult = Parsed(T);

    return struct {
        fixed_size: ?usize,
        byte_length: usize,
        min_size: usize,
        max_size: usize,

        /// Zig Type definition
        pub fn getZigType() type {
            return T;
        }

        pub fn getViewDUType() type {
            return T;
        }

        pub fn getZigTypeAlignment() usize {
            return num_bytes;
        }

        pub fn init() !@This() {
            return @This(){ .fixed_size = num_bytes, .byte_length = num_bytes, .min_size = 0, .max_size = num_bytes };
        }

        pub fn deinit(_: @This()) void {
            // do nothing
        }

        // public apis

        // TODO: no need to pass value as pointer here?
        pub fn hashTreeRoot(_: *const @This(), value: T, out: []u8) HashError!void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            for (out) |*byte| {
                byte.* = 0;
            }

            const slice = std.mem.bytesAsSlice(T, out);
            const endian_value = if (native_endian == .big) @byteSwap(value) else value;
            slice[0] = endian_value;
        }

        pub fn fromSsz(self: *const @This(), ssz: []const u8) SszError!ParsedResult {
            return SingleType.fromSsz(self, ssz);
        }

        pub fn fromJson(self: *const @This(), json: []const u8) JsonError!ParsedResult {
            return SingleType.fromJson(self, json);
        }

        pub fn clone(self: *const @This(), value: T) SszError!ParsedResult {
            return SingleType.clone(self, value);
        }

        pub fn equals(_: *const @This(), a: T, b: T) bool {
            return a == b;
        }

        // Serialization + deserialization

        // unused param but want to follow the same interface as other types
        pub fn serializedSize(_: *const @This(), _: T) usize {
            return num_bytes;
        }

        pub fn serializeToBytes(_: *const @This(), value: T, out: []u8) !usize {
            // bytesAsSlice has @divExact so need to be multiple of T
            const end = (out.len / @sizeOf(T)) * @sizeOf(T);
            const slice = std.mem.bytesAsSlice(T, out[0..end]);
            const endian_value = if (native_endian == .big) @byteSwap(value) else value;
            slice[0] = endian_value;
            return num_bytes;
        }

        pub fn deserializeFromBytes(_: *const @This(), bytes: []const u8, out: *T) !void {
            if (bytes.len < num_bytes) {
                return error.InCorrectLen;
            }

            const slice = std.mem.bytesAsSlice(T, bytes);
            // TODO: is this the same memory?
            const value = slice[0];
            // use var to make the compiler happy
            const endian_value = if (native_endian == .big) @byteSwap(value) else value;
            out.* = endian_value;
        }

        /// Same to deserializeFromBytes but this returns T instead of out param
        /// both arena_allocator and out parameter are not used, this is just to follow the same interface
        pub fn deserializeFromSlice(_: *const @This(), _: Allocator, slice: []const u8, _: ?T) SszError!T {
            if (slice.len < num_bytes) {
                return error.InCorrectLen;
            }

            const sliceT = std.mem.bytesAsSlice(T, slice);
            const value = sliceT[0];
            return if (native_endian == .big) @byteSwap(value) else value;
        }

        /// an implementation for parent types
        pub fn deserializeFromJson(_: *const @This(), _: Allocator, source: *Scanner, _: ?T) JsonError!T {
            const value = try source.next();
            try switch (value) {
                // uintN is mapped to string in consensus spec https://github.com/ethereum/consensus-specs/blob/dev/ssz/simple-serialize.md#json-mapping
                .string => |v| {
                    return try sliceToInt(T, v);
                },
                else => return error.InvalidJson,
            };
        }

        pub fn doClone(_: *const @This(), _: Allocator, value: T, _: ?*T) !T {
            return value;
        }
    };
}

/// copy from std.json.static.zig
fn sliceToInt(comptime T: type, slice: []const u8) !T {
    if (isNumberFormattedLikeAnInteger(slice))
        return std.fmt.parseInt(T, slice, 10);
    // Try to coerce a float to an integer.
    const float = try std.fmt.parseFloat(f128, slice);
    if (@round(float) != float) return error.InvalidNumber;
    if (float > std.math.maxInt(T) or float < std.math.minInt(T)) return error.Overflow;
    return @as(T, @intCast(@as(i128, @intFromFloat(float))));
}

/// copy from std.json.scanner.zig
pub fn isNumberFormattedLikeAnInteger(value: []const u8) bool {
    if (std.mem.eql(u8, value, "-0")) return false;
    return std.mem.indexOfAny(u8, value, ".eE") == null;
}

test "createUintType" {
    const UintType = createUintType(8);
    const uintType = try UintType.init();
    defer uintType.deinit();
    const value: u64 = 0xffffffffffffffff;
    var root = [_]u8{0} ** 32;
    try uintType.hashTreeRoot(value, root[0..]);

    // TODO: more unit tests: serialize + deserialize, clone, make sure can mutate output values
    // var out: [8]u8 = undefined;
    // 0xffffffffffffffff is too big for json
    // TODO: implement toJson and test again
    // const valueToJson: u64 = 1;
    // _ = try uintType.serializeToBytes(&valueToJson, out[0..]);

    // const allocator = std.testing.allocator;
    // var arena = std.heap.ArenaAllocator.init(allocator);
    // defer arena.deinit();
    // const valueFromJson = try uintType.fromJson(arena.allocator(), out[0..]);
    // try expect(valueFromJson.* == valueToJson);
}
