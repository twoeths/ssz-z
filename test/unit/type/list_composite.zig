const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createUintType = @import("ssz").createUintType;
const createListCompositeType = @import("ssz").createListCompositeType;
const ByteVectorType = @import("ssz").ByteVectorType;

test "ListCompositeType - element type ByteVectorType" {
    const test_cases = [_]TestCase{
        TestCase{
            .id = "empty",
            .serializedHex = "0x",
            .json = "[]",
            .rootHex = "0x96559674a79656e540871e1f39c9b91e152aa8cddb71493e754827c4cc809d57",
        },
        TestCase{ .id = "2 roots", .serializedHex = "0xddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", .json = 
        \\[
        \\ "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        \\ "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        \\]
        , .rootHex = "0x0cb947377e177f774719ead8d210af9c6461f41baf5b4082f86a3911454831b8" },
    };

    const allocator = std.testing.allocator;
    var byte_vector_type = try ByteVectorType.init(allocator, 32);
    defer byte_vector_type.deinit();

    const ListCompositeType = createListCompositeType(ByteVectorType, []u8);
    var list = try ListCompositeType.init(allocator, &byte_vector_type, 128, 4);
    defer list.deinit();

    const TypeTest = @import("common.zig").typeTest(ListCompositeType);

    for (test_cases[0..]) |*tc| {
        std.debug.print("ListCompositeType of Root - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&list, tc);
    }
}
