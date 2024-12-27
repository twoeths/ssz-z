const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createUintType = @import("ssz").createUintType;
const createVectorCompositeType = @import("ssz").createVectorCompositeType;
const createContainerType = @import("ssz").createContainerType;
const sha256Hash = @import("hash").sha256Hash;

test "VectorCompositeType of Root" {
    const test_cases = [_]TestCase{
        TestCase{
            .id = "4 roots",
            .serializedHex = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            .json =
            \\["0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"]
            ,
            .rootHex = "0x56019bafbc63461b73e21c6eae0c62e8d5b8e05cb0ac065777dc238fcf9604e6",
        },
    };

    const allocator = std.testing.allocator;
    const ByteVectorType = @import("ssz").ByteVectorType;
    var byte_vector_type = try ByteVectorType.init(allocator, 32);
    defer byte_vector_type.deinit();

    const VectorCompositeType = createVectorCompositeType(ByteVectorType);
    var vector_composite_type = try VectorCompositeType.init(allocator, &byte_vector_type, 4);
    defer vector_composite_type.deinit();

    const TypeTest = @import("common.zig").typeTest(VectorCompositeType);

    for (test_cases[0..]) |*tc| {
        std.debug.print("VectorCompositeType of Root - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&vector_composite_type, tc);
    }
}

test "VectorCompositeType of Container" {
    const test_cases = [_]TestCase{
        TestCase{ .id = "4 arrays", .serializedHex = "0x0000000000000000000000000000000040e2010000000000f1fb0900000000004794030000000000f8ad0b00000000004e46050000000000ff5f0d0000000000", .json = 
        \\[
        \\{"a": "0", "b": "0"},
        \\{"a": "123456", "b": "654321"},
        \\{"a": "234567", "b": "765432"},
        \\{"a": "345678", "b": "876543"}
        \\]
        , .rootHex = "0xb1a797eb50654748ba239010edccea7b46b55bf740730b700684f48b0c478372" },
    };

    const allocator = std.testing.allocator;
    const UintType = createUintType(8);
    const uintType = try UintType.init();
    defer uintType.deinit();

    const SszType = struct {
        a: UintType,
        b: UintType,
    };

    const ContainerType = createContainerType(SszType, sha256Hash);
    var containerType = try ContainerType.init(allocator, SszType{
        .a = uintType,
        .b = uintType,
    });
    defer containerType.deinit();

    const VectorCompositeType = createVectorCompositeType(ContainerType);
    var vector_composite_type = try VectorCompositeType.init(allocator, &containerType, 4);
    defer vector_composite_type.deinit();

    const TypeTest = @import("common.zig").typeTest(VectorCompositeType);

    for (test_cases[0..]) |*tc| {
        std.debug.print("VectorCompositeType of Container - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&vector_composite_type, tc);
    }
}
