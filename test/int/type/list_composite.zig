const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createUintType = @import("ssz").createUintType;
const createListCompositeType = @import("ssz").createListCompositeType;
const ByteVectorType = @import("ssz").ByteVectorType;
const createContainerType = @import("ssz").createContainerType;
const sha256Hash = @import("hash").sha256Hash;

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

test "ListCompositeType - element type Container" {
    const test_cases = [_]TestCase{
        TestCase{
            .id = "empty",
            .serializedHex = "0x",
            .json = "[]",
            .rootHex = "0x96559674a79656e540871e1f39c9b91e152aa8cddb71493e754827c4cc809d57",
        },
        TestCase{ .id = "2 values", .serializedHex = "0x0000000000000000000000000000000040e2010000000000f1fb090000000000", .json = 
        \\[
        \\ {"a": "0", "b": "0"},
        \\ {"a": "123456", "b": "654321"}
        \\]
        , .rootHex = "0x8ff94c10d39ffa84aa937e2a077239c2742cb425a2a161744a3e9876eb3c7210" },
    };

    const allocator = std.testing.allocator;
    const UintType = createUintType(8);
    const uintType = try UintType.init();
    defer uintType.deinit();

    const SszType = struct {
        a: UintType,
        b: UintType,
    };
    const ZigType = struct {
        a: u64,
        b: u64,
    };

    const ContainerType = createContainerType(SszType, ZigType, sha256Hash);
    var containerType = try ContainerType.init(allocator, SszType{
        .a = uintType,
        .b = uintType,
    });
    defer containerType.deinit();

    const ListCompositeType = createListCompositeType(ContainerType, ZigType);
    var list = try ListCompositeType.init(allocator, &containerType, 128, 4);
    defer list.deinit();

    const TypeTest = @import("common.zig").typeTest(ListCompositeType);

    for (test_cases[0..]) |*tc| {
        std.debug.print("ListCompositeType of Container - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&list, tc);
    }
}
