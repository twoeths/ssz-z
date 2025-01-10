const std = @import("std");
const digest64Into = @import("./sha256.zig").digest64Into;

pub const ZeroHash = struct {
    allocator: *const std.mem.Allocator,
    zero_hashes: []?[32]u8,

    pub fn init(allocator: *const std.mem.Allocator, max_depth: usize) !ZeroHash {
        var hashes = try allocator.alloc(?[32]u8, max_depth + 1);
        // Use indexing to assign `null` to each element
        for (0..hashes.len) |i| {
            if (i == 0) {
                hashes[i] = [_]u8{0} ** 32;
            } else {
                hashes[i] = null;
            }
        }
        return ZeroHash{ .allocator = allocator, .zero_hashes = hashes };
    }

    pub fn get(self: *ZeroHash, depth: usize) !*[32]u8 {
        if (depth >= self.zero_hashes.len) {
            return error.OutOfBounds;
        }

        if (self.zero_hashes[depth] == null) {
            const prev = try self.get(depth - 1);
            var new_hash: [32]u8 = undefined;
            digest64Into(prev, prev, &new_hash);
            self.zero_hashes[depth] = new_hash;
        }

        return &self.zero_hashes[depth].?;
    }

    pub fn deinit(self: *ZeroHash) void {
        self.allocator.free(self.zero_hashes);
    }
};

// Thread-local instance of `?ZeroHash`
threadlocal var instance: ?ZeroHash = null;

pub fn initZeroHash(allocator: *const std.mem.Allocator, max_depth: usize) !void {
    if (instance == null) {
        instance = try ZeroHash.init(allocator, max_depth);
    }
}

pub fn getZeroHash(depth: usize) !*const [32]u8 {
    if (instance == null) {
        return error.noInitZeroHash;
    }
    return try instance.?.get(depth);
}

pub fn deinitZeroHash() void {
    if (instance != null) {
        instance.?.deinit();
        instance = null;
    }
}

test "ZeroHash" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 10);
    defer deinitZeroHash();
    const hash = try getZeroHash(1);
    const expected_hash = [_]u8{
        245, 165, 253, 66,  209, 106, 32,  48,
        39,  152, 239, 110, 211, 9,   151, 155,
        67,  0,   61,  35,  32,  217, 240, 232,
        234, 152, 49,  169, 39,  89,  251, 75,
    };
    try std.testing.expectEqualSlices(u8, hash[0..], expected_hash[0..]);
    // std.debug.print("Hash value: {any}\n", .{hash});
}

test "memory allocation" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 64);
    defer deinitZeroHash();

    for (0..64) |i| {
        _ = try getZeroHash(i);
    }
}
