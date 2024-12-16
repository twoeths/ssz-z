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
const createListBasicType = @import("ssz").createListBasicType;

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

test "ListCompositeType - element type ListBasicType" {
    // TODO: fix serialization bug
    if (true) {
        return error.SkipZigTest;
    }

    const test_cases = [_]TestCase{
        TestCase{ .id = "empty", .serializedHex = "0x", .json = "[]", .rootHex = "0x7a0501f5957bdf9cb3a8ff4966f02265f968658b7a9c62642cba1165e86642f5" },
        TestCase{ .id = "2 full values", .serializedHex = "0x080000000c0000000100020003000400", .json = 
        \\[
        \\["1", "2"],
        \\["3", "4"]
        \\]
        , .rootHex = "0x58140d48f9c24545c1e3a50f1ebcca85fd40433c9859c0ac34342fc8e0a800b8" },
        TestCase{ .id = "2 empty values", .serializedHex = "0x0800000008000000", .json = 
        \\[
        \\[],
        \\[]
        \\]
        , .rootHex = "0xe839a22714bda05923b611d07be93b4d707027d29fd9eef7aa864ed587e462ec" },
    };

    const allocator = std.testing.allocator;
    const UintType = createUintType(2);
    var u16Type = try UintType.init();
    defer u16Type.deinit();

    const ListBasicType = createListBasicType(UintType, u16);
    var listBasicType = try ListBasicType.init(allocator, &u16Type, 2, 2);
    defer listBasicType.deinit();

    const ListCompositeType = createListCompositeType(ListBasicType, []u16);
    var listCompositeType = try ListCompositeType.init(allocator, &listBasicType, 2, 2);
    defer listCompositeType.deinit();

    const TypeTest = @import("common.zig").typeTest(ListCompositeType);

    for (test_cases[0..]) |*tc| {
        std.debug.print("ListCompositeType of ListBasicType - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&listCompositeType, tc);
    }
}
