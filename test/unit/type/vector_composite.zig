const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createUintType = @import("ssz").createUintType;
const createVectorCompositeType = @import("ssz").createVectorCompositeType;

test "VectorCompositeType of Root" {
    const test_cases = [_]TestCase{
        // TODO: fix clone() issue
        // TestCase{
        // .id = "4 roots",
        // .serializedHex = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        // .json =
        // \\["0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"]
        // ,
        // .rootHex = "0x56019bafbc63461b73e21c6eae0c62e8d5b8e05cb0ac065777dc238fcf9604e6",
        // },
    };

    const allocator = std.testing.allocator;
    const ByteVectorType = @import("ssz").ByteVectorType;
    var byte_vector_type = try ByteVectorType.init(allocator, 32);
    defer byte_vector_type.deinit();

    const VectorCompositeType = createVectorCompositeType(ByteVectorType, []u8);
    var vector_composite_type = try VectorCompositeType.init(allocator, &byte_vector_type, 4);
    defer vector_composite_type.deinit();

    const TypeTest = @import("common.zig").typeTest(VectorCompositeType, [][]u8);

    for (test_cases[0..]) |*tc| {
        std.debug.print("VectorCompositeType of Root - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&vector_composite_type, tc);
    }
}
