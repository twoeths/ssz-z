const std = @import("std");
const expect = std.testing.expect;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();

pub fn createUintType(comptime num_bytes: usize) type {
    if (num_bytes != 2 and num_bytes != 4 and num_bytes != 8) {
        @compileError("Only support num_bytes of 2, 4 or 8 bytes");
    }

    const T = switch (num_bytes) {
        2 => u16,
        4 => u32,
        8 => u64,
        else => unreachable,
    };

    return struct {
        fixed_size: ?usize,

        pub fn init() !@This() {
            return @This(){ .fixed_size = num_bytes };
        }

        pub fn deinit() void {
            // do nothing
        }

        pub fn hashTreeRoot(_: @This(), value: anytype, out: []u8) !void {
            if (out.len < num_bytes) {
                return error.InCorrectLen;
            }

            const value_type = @TypeOf(value);
            if (value_type != T) {
                @compileError("value type is not correct");
            }

            const slice = std.mem.bytesAsSlice(T, out);
            const endian_value = if (native_endian == .big) @byteSwap(value) else value;
            slice[0] = endian_value;
        }

        // Serialization + deserialization

        // unused param but want to follow the same interface as other types
        pub fn serializeSize(_: @This(), _: T) usize {
            return num_bytes;
        }

        pub fn serializeToBytes(self: @This(), value: anytype, out: []u8) !usize {
            try self.hashTreeRoot(value, out);
            return num_bytes;
        }

        pub fn deserializeFromBytes(_: @This(), bytes: []const u8, out: *T) !void {
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

        pub fn equals(_: @This(), a: *const T, b: *const T) bool {
            return a.* == b.*;
        }

        pub fn clone(_: @This(), value: *const T, out: *T) !void {
            if (value.* < 0) {
                return error.InvalidInput;
            }
            out.* = value.*;
        }
    };
}

test "createUintType" {
    const UintType = createUintType(8);
    const uintType = try UintType.init();
    // defer uintType.deinit();
    const value: u64 = 0xffffffffffffffff;
    var root = [_]u8{0} ** 32;
    try uintType.hashTreeRoot(value, root[0..]);
    // std.debug.print("uintType.hashTreeRoot(0xffffffffffffffff) {any}\n", .{root});

    // TODO: more unit tests: serialize + deserialize, clone, make sure can mutate output values
}

// we can use below code for hashTreeRoot() implementation above
test "pointer casting" {
    const bytes align(@alignOf(u32)) = [_]u8{ 0x12, 0x12, 0x12, 0x12 };
    const u32_ptr: *const u32 = @ptrCast(&bytes);
    try expect(u32_ptr.* == 0x12121212);

    // Even this example is contrived - there are better ways to do the above than
    // pointer casting. For example, using a slice narrowing cast:
    const u32_value = std.mem.bytesAsSlice(u32, bytes[0..])[0];
    try expect(u32_value == 0x12121212);

    // And even another way, the most straightforward way to do it:
    try expect(@as(u32, @bitCast(bytes)) == 0x12121212);

    return error.SkipZigTest;
}
