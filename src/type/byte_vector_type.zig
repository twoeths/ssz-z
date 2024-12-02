const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const maxChunksToDepth = @import("hash").maxChunksToDepth;
const merkleize = @import("hash").merkleizeBlocksBytes;
const sha256Hash = @import("hash").sha256Hash;
const fromHex = @import("util").fromHex;

pub const ByteVectorType = struct {
    allocator: *std.mem.Allocator,
    depth: usize,
    chunk_depth: usize,
    fixed_size: ?usize,
    min_size: usize,
    max_size: usize,
    max_chunk_count: usize,
    // this should always be a multiple of 64 bytes
    block_bytes: []u8,

    pub fn init(allocator: *std.mem.Allocator, length_bytes: usize) !@This() {
        const max_chunk_count: usize = (length_bytes + 31) / 32;
        const chunk_depth = maxChunksToDepth(max_chunk_count);
        const depth = chunk_depth;
        const fixed_size = length_bytes;
        const min_size = fixed_size;
        const max_size = fixed_size;
        const blocks_bytes_len: usize = ((max_chunk_count + 1) / 2) * 64;

        return @This(){
            .allocator = allocator,
            .depth = depth,
            .chunk_depth = chunk_depth,
            .fixed_size = fixed_size,
            .min_size = min_size,
            .max_size = max_size,
            .max_chunk_count = max_chunk_count,
            .block_bytes = try allocator.alloc(u8, blocks_bytes_len),
        };
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.block_bytes);
    }

    pub fn hashTreeRoot(self: *@This(), value: []const u8, out: []u8) !void {
        if (out.len != 32) {
            return error.InCorrectLen;
        }

        if (value.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        @memcpy(self.block_bytes[0..value.len], value);
        if (value.len < self.block_bytes.len) {
            @memset(self.block_bytes[value.len..], 0);
        }

        // chunks root
        try merkleize(sha256Hash, self.block_bytes, self.max_chunk_count, out);
    }

    // Serialization + deserialization
    pub fn serializedSize(self: @This(), _: []const u8) usize {
        return self.fixed_size.?;
    }

    pub fn serializeToBytes(self: @This(), value: []const u8, out: []u8) !usize {
        if (out.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        @memcpy(out, value);
        return self.fixed_size.?;
    }

    pub fn deserializeFromBytes(self: @This(), data: []const u8, out: []u8) !void {
        if (data.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        if (out.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        @memcpy(out, data);
    }

    /// Same to deserializeFromBytes but this returns *T instead of out param
    /// Consumer need to free the memory
    /// out parameter is unused because parent does not allocate, just to conform to the api
    pub fn deserializeFromSlice(self: @This(), arenaAllocator: Allocator, slice: []const u8, _: ?[]u8) ![]u8 {
        if (slice.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        const result = try arenaAllocator.alloc(u8, self.fixed_size.?);
        @memcpy(result, slice);
        return result;
    }

    /// fromJson
    /// public function
    pub fn fromJson(self: @This(), arena_allocator: Allocator, json: []const u8) ![]u8 {
        const result = try arena_allocator.alloc(u8, self.fixed_size.?);
        try fromHex(json, result);
        return result;
    }

    /// Implementation for parent
    /// Consumer need to free the memory
    /// out parameter is unused because parent does not allocate, just to conform to the api
    pub fn deserializeFromJson(self: @This(), arena_allocator: Allocator, source: *Scanner, _: ?[]u8) ![]u8 {
        const value = try source.next();
        const result = try arena_allocator.alloc(u8, self.fixed_size.?);
        try switch (value) {
            .string => |v| {
                try fromHex(v, result);
            },
            else => error.InvalidJson,
        };

        return result;
    }

    pub fn equals(_: @This(), a: []const u8, b: []const u8) bool {
        if (a.len != b.len) {
            return false;
        }

        return std.mem.eql(u8, a, b);
    }

    pub fn clone(self: @This(), value: []const u8, out: []u8) !void {
        if (value.len != self.fixed_size) {
            return error.InCorrectLen;
        }

        if (value.len != out.len) {
            return error.InCorrectLen;
        }

        @memcpy(out, value);
    }
};
