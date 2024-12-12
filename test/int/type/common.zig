const std = @import("std");
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const toRootHex = @import("util").toRootHex;

pub const TypeTestCase = struct {
    id: []const u8,
    serializedHex: []const u8,
    json: []const u8,
    rootHex: []const u8,
};

const TypeTestError = error{
    InvalidRootHex,
};

/// ST: ssz type
pub fn typeTest(comptime ST: type) type {
    const TypeTest = struct {
        pub fn validSszTest(t: *ST, tc: *const TypeTestCase) !void {
            var allocator = std.testing.allocator;
            try initZeroHash(&allocator, 32);
            defer deinitZeroHash();

            var serializedMax = [_]u8{0} ** 1024;
            const serialized = serializedMax[0..((tc.serializedHex.len - 2) / 2)];
            try fromHex(tc.serializedHex, serialized);

            // fromSsz
            const ssz_result = try t.fromSsz(serialized);
            defer ssz_result.deinit();
            const value = ssz_result.value;

            // fromJson
            const json_result = try t.fromJson(tc.json);
            defer json_result.deinit();
            try std.testing.expect(t.equals(value, json_result.value));

            // TODO: toJson

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
            const cloned_result = try t.clone(value);
            defer cloned_result.deinit();
            try std.testing.expect(t.equals(value, cloned_result.value));

            // TODO: serialize, toJson on cloned value?
        }
    };

    return TypeTest;
}
