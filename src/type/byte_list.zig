const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const merkleize = @import("hash").merkleizeBlocksBytes;
const sha256Hash = @import("hash").sha256Hash;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const SszError = @import("./common.zig").SszError;
const JsonError = @import("./common.zig").JsonError;
const HashError = @import("./common.zig").HashError;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const Parsed = @import("./type.zig").Parsed;
const ParsedResult = Parsed([]u8);
const SingleType = @import("./single.zig").withType([]u8);
const FromHexError = @import("util").FromHexError;

// TODO: int test for this type, miss some implementations
/// ByteList: Immutable alias of List[byte, N]
/// ByteList is an immutable value which is represented by a Uint8Array for memory efficiency and performance.
/// Note: Consumers of this type MUST never mutate the `Uint8Array` representation of a ByteList.
///
/// For a `ByteListType` with mutability, use `ListBasicType(byteType)`
pub fn createByteListType(comptime limit_bytes: usize) type {
    const max_chunk_count: usize = (limit_bytes + 31) / 32;
    const BlockBytes = ArrayList(u8);

    const ByteListType = struct {
        allocator: std.mem.Allocator,
        // this should always be a multiple of 64 bytes
        block_bytes: BlockBytes,
        mix_in_length_block_bytes: []u8,

        pub fn init(allocator: std.mem.Allocator, init_capacity: usize) !@This() {
            return @This(){ .allocator = allocator, .block_bytes = try BlockBytes.initCapacity(allocator, init_capacity), .mix_in_length_block_bytes = try allocator.alloc(u8, 64) };
        }

        pub fn deinit(self: *const @This()) void {
            self.block_bytes.deinit();
            self.allocator.free(self.mix_in_length_block_bytes);
        }

        /// public apis
        pub fn hashTreeRoot(self: *@This(), value: []const u8, out: []u8) HashError!void {
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

        pub fn fromSsz(self: *const @This(), ssz: []const u8) SszError!ParsedResult {
            return SingleType.fromSsz(self, ssz);
        }

        pub fn fromJson(self: *const @This(), json: []const u8) JsonError!ParsedResult {
            return SingleType.fromJson(self, json);
        }

        pub fn clone(self: *const @This(), value: []const u8) SszError!ParsedResult {
            return SingleType.clone(self, value);
        }

        pub fn equals(_: @This(), a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }

        // TODO: make sure this works with parent as containerType, make a unit test for it
        pub fn serializedSize(_: @This(), value: []const u8) usize {
            return value.len;
        }

        pub fn serializeToBytes(_: @This(), value: []const u8, out: []u8) !usize {
            if (value.len != out.len) {
                return error.InCorrectLen;
            }
            @memcpy(out, value);
            return value.len;
        }

        pub fn deserializeFromBytes(_: @This(), data: []const u8, out: []u8) !void {
            if (data.len > limit_bytes) {
                return error.InCorrectLen;
            }

            if (data.len != out.len) {
                return error.InCorrectLen;
            }

            @memcpy(out, data);
        }

        /// Consumer need to free the memory
        /// out parameter is unused because parent does not allocate, just to conform to the api
        pub fn deserializeFromSlice(_: *const @This(), arena_allocator: Allocator, slice: []const u8, _: ?[]u8) SszError![]u8 {
            if (slice.len > limit_bytes) {
                return error.InCorrectLen;
            }

            const result = try arena_allocator.alloc(u8, slice.len);
            @memcpy(result, slice);
            return result;
        }

        //// Implementation for parent
        /// Consumer need to free the memory
        /// out parameter is unused because parent does not allocate, just to conform to the api
        pub fn deserializeFromJson(_: @This(), arena_allocator: Allocator, source: *Scanner, _: ?[]u8) ![]u8 {
            const value = try source.next();
            const result = switch (value) {
                .string => |v| blk: {
                    var length: usize = undefined;
                    if (v.len >= 2 and (v[0] == '0' and (v[1] == 'x' or v[1] == 'X'))) {
                        length = (v.len - 2) / 2;
                    } else {
                        length = v.len / 2;
                    }
                    const result = try arena_allocator.alloc(u8, length);
                    try fromHex(v, result);
                    break :blk result;
                },
                else => return error.InvalidJson,
            };

            return result;
        }

        pub fn doClone(_: *const @This(), arena_allocator: Allocator, value: []const u8, out: ?[]u8) ![]u8 {
            const out2 = out orelse try arena_allocator.alloc(u8, value.len);
            @memcpy(out2, value);
            return out2;
        }
    };

    return ByteListType;
}
