const std = @import("std");
const expect = std.testing.expect;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();

pub fn createUintType(comptime T: type) type {
    if (@alignOf(T) > 32) {
        @compileError("T must have an alignment of 32 bytes or less");
    }

    return struct {
        allocator: *std.mem.Allocator,
        // caller should free the result
        fn hashTreeRoot(self: @This(), value: T) ![]u8 {
            const result = try self.allocator.alloc(u8, 32);
            @memset(result, 0);
            try @This().hashTreeRootInto(value, result);
            return result;
        }

        fn hashTreeRootInto(value: T, out: []u8) !void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }
            const endian_value = if (native_endian == .big) @byteSwap(value) else value;
            const slice = std.mem.bytesAsSlice(T, out);
            slice[0] = endian_value;
        }
    };
}

test "createUintType" {
    var allocator = std.testing.allocator;
    const UintType = createUintType(u64);
    const uintType = UintType{ .allocator = &allocator };
    var result = try uintType.hashTreeRoot(0xffffffffffffffff);
    std.debug.print("uintType.hashTreeRoot(0xffffffffffffffff) {any}\n", .{result});
    allocator.free(result);
    result = try uintType.hashTreeRoot(0xff);
    std.debug.print("uintType.hashTreeRoot(0xff) {any}\n", .{result});
    allocator.free(result);
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
