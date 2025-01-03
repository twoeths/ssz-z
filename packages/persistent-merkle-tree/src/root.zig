const std = @import("std");
const testing = std.testing;
const merkleize = @import("merkleize.zig");
const zero_hash = @import("zero_hash.zig");
pub const merkleizeBlocksBytes = merkleize.merkleizeBlocksBytes;
pub const maxChunksToDepth = merkleize.maxChunksToDepth;
pub const HashFn = merkleize.HashFn;
pub const initZeroHash = zero_hash.initZeroHash;
pub const getZeroHash = zero_hash.getZeroHash;
pub const deinitZeroHash = zero_hash.deinitZeroHash;
pub const sha256Hash = @import("./sha256.zig").sha256Hash;
pub const HashError = @import("./sha256.zig").HashError;

test {
    testing.refAllDecls(@This());
}
