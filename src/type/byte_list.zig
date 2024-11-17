const std = @import("std");
const ArrayList = std.ArrayList;
const merkleize = @import("hash").merkleizeBlocksBytes;
const sha256Hash = @import("hash").sha256Hash;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();

/// ByteList: Immutable alias of List[byte, N]
/// ByteList is an immutable value which is represented by a Uint8Array for memory efficiency and performance.
/// Note: Consumers of this type MUST never mutate the `Uint8Array` representation of a ByteList.
///
/// For a `ByteListType` with mutability, use `ListBasicType(byteType)`
pub fn createByteListType(comptime limit_bytes: usize) type {
    const max_chunk_count: usize = (limit_bytes + 31) / 32;
    const BlockBytes = ArrayList(u8);

    const ByteListType = struct {
        allocator: *std.mem.Allocator,
        // this should always be a multiple of 64 bytes
        block_bytes: BlockBytes,
        mix_in_length_block_bytes: []u8,

        pub fn init(allocator: *std.mem.Allocator, init_capacity: usize) !@This() {
            return @This(){ .allocator = allocator, .block_bytes = try BlockBytes.initCapacity(allocator.*, init_capacity), .mix_in_length_block_bytes = try allocator.alloc(u8, 64) };
        }

        pub fn deinit(self: @This()) void {
            self.block_bytes.deinit();
            self.allocator.free(self.mix_in_length_block_bytes);
        }

        pub fn hashTreeRoot(self: *@This(), value: []const u8, out: []u8) !void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            if (value.len > limit_bytes) {
                return error.InCorrectLen;
            }

            const block_len: usize = ((value.len + 63) / 64) * 64;
            try self.block_bytes.resize(block_len);

            std.mem.copyForwards(u8, self.block_bytes.items[0..value.len], value);
            if (value.len < block_len) {
                @memset(self.block_bytes.items[value.len..block_len], 0);
            }

            // TODO: avoid sha256 hard code
            // compute root of chunks
            try merkleize(sha256Hash, self.block_bytes.items[0..block_len], max_chunk_count, self.mix_in_length_block_bytes[0..32]);

            // mixInLength
            @memset(self.mix_in_length_block_bytes[32..], 0);
            const slice = std.mem.bytesAsSlice(u64, self.mix_in_length_block_bytes[32..]);
            const len_le = if (native_endian == .big) @byteSwap(value.len) else value.len;
            slice[0] = len_le;

            // final root
            // one for hashTreeRoot(value), one for length
            const chunk_count = 2;
            try merkleize(sha256Hash, self.mix_in_length_block_bytes, chunk_count, out);
        }

        // TODO: make sure this works with parent as containerType, make a unit test for it
        pub fn serializeSize(_: @This(), value: []const u8) usize {
            return value.len;
        }

        pub fn deserializeFromBytes(_: @This(), data: []const u8, out: []u8) !void {
            if (data.len > limit_bytes) {
                return error.InCorrectLen;
            }

            if (data.len != out.len) {
                return error.InCorrectLen;
            }

            std.mem.copyForwards(u8, out, data);
        }

        pub fn equals(_: @This(), a: []const u8, b: []const u8) bool {
            return std.mem.allEqual(u8, a, b);
        }

        pub fn clone(_: @This(), value: []const u8, out: []u8) !void {
            if (value.len > limit_bytes or value.len != out.len) {
                return error.InCorrectLen;
            }

            std.mem.copyForwards(u8, out, value);
        }
    };

    return ByteListType;
}

test "sanity" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();
    const ByteList = createByteListType(256);
    var byteList = try ByteList.init(&allocator, 256);
    defer byteList.deinit();

    const TestCase = struct {
        hex: []const u8,
        expected: []const u8,
    };

    const test_cases = comptime [_]TestCase{
        // empty
        TestCase{ .hex = "0x", .expected = "0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6" },
        // 4 bytes zero
        TestCase{ .hex = "0x00000000", .expected = "0xa39babe565305429771fc596a639d6e05b2d0304297986cdd2ef388c1936885e" },
        // 4 bytes some value
        TestCase{ .hex = "0x0cb94737", .expected = "0x2e14da116ecbec4c8d693656fb5b69bb0ea9e84ecdd15aba7be1c008633f2885" },
        // 32 bytes zero
        TestCase{ .hex = "0x0000000000000000000000000000000000000000000000000000000000000000", .expected = "0xbae146b221eca758702e29b45ee7f7dc3eea17d119dd0a3094481e3f94706c96" },
        // 32 bytes some value
        TestCase{ .hex = "0x0cb947377e177f774719ead8d210af9c6461f41baf5b4082f86a3911454831b8", .expected = "0x50425dbd7a34b50b20916e965ce5c060abe6516ac71bb00a4afebe5d5c4568b8" },
        // 96 bytes zero
        TestCase{ .hex = "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", .expected = "0xcd09661f4b2109fb26decd60c004444ea5308a304203412280bd2af3ace306bf" },
        // 96 bytes some value
        TestCase{ .hex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1", .expected = "0x5d3ae4b886c241ffe8dc7ae1b5f0e2fb9b682e1eac2ddea292ef02cc179e6903" },
    };

    inline for (test_cases) |tc| {
        const expected = tc.expected;
        var value = [_]u8{0} ** ((tc.hex.len - 2) / 2);
        try fromHex(tc.hex, value[0..]);
        var out = [_]u8{0} ** 32;
        try byteList.hashTreeRoot(value[0..], out[0..]);
        const root = try toRootHex(out[0..]);
        try std.testing.expectEqualSlices(u8, expected, root);
    }
}
