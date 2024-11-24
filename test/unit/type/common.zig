const std = @import("std");
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const toRootHex = @import("util").toRootHex;

pub const TypeTestCase = struct {
    serializedHex: []const u8,
    json: []const u8,
    rootHex: []const u8,
};

const TypeTestError = error{
    InvalidRootHex,
};

/// ST: ssz type
/// ZT: zig value type
pub fn typeTest(comptime ST: type, comptime ZT: type) type {
    const TypeTest = struct {
        pub fn validSszTest(t: *ST, tc: *const TypeTestCase) !void {
            var allocator = std.testing.allocator;
            try initZeroHash(&allocator, 32);
            defer deinitZeroHash();

            var serializedMax = [_]u8{0} ** 1024;
            const serialized = serializedMax[0..((tc.serializedHex.len - 2) / 2)];
            try fromHex(tc.serializedHex, serialized);

            // deserialize
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const value = try t.deserializeFromSlice(arena.allocator(), serialized);
            const parsedJson = try std.json.parseFromSlice(ZT, allocator, tc.json, .{});
            defer parsedJson.deinit();
            try std.testing.expect(t.equals(value, parsedJson.value));

            // serialize
            const serializedOut = try allocator.alloc(u8, serialized.len);
            defer allocator.free(serializedOut);
            _ = try t.serializeToBytes(value, serializedOut[0..]);
            try std.testing.expectEqualSlices(u8, serialized, serializedOut);

            // hashTreeRoot
            var root = [_]u8{0} ** 32;
            try t.hashTreeRoot(value, root[0..]);
            const rootHex = try toRootHex(root[0..]);
            try std.testing.expectEqualSlices(u8, tc.rootHex, rootHex);

            // clone + equals
            // Slice
            const value_type_info = @typeInfo(ZT);
            if (value_type_info == .Pointer) {
                const pointer_info = value_type_info.Pointer;
                if (pointer_info.size == .Slice) {
                    const elem_type = pointer_info.child;
                    const cloned = try allocator.alloc(elem_type, value.len);
                    defer allocator.free(cloned);
                    try t.clone(value, cloned);
                    try std.testing.expect(t.equals(value, cloned));
                }
            }

            // TODO: handle for other regular types
        }
    };

    return TypeTest;
}
