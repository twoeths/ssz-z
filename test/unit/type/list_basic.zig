const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createUintType = @import("ssz").createUintType;
const createListBasicType = @import("ssz").createListBasicType;

const testCases = [_]TestCase{
    TestCase{ .id = "empty", .serializedHex = "0x", .json = "[]", .rootHex = "0x52e2647abc3d0c9d3be0387f3f0d925422c7a4e98cf4489066f0f43281a899f3" },
    TestCase{ .id = "4 values", .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000a086010000000000400d030000000000e093040000000000801a060000000000", .json = 
    \\["100000", "200000", "300000", "400000", "100000", "200000", "300000", "400000"]
    , .rootHex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1" },
    TestCase{
        .id = "8 values",
        .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000a086010000000000400d030000000000e093040000000000801a060000000000",
        .json =
        \\["100000", "200000", "300000", "400000", "100000", "200000", "300000", "400000"]
        ,
        .rootHex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1",
    },
};

test "valid test for ListBasicType" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    // uint of 8 bytes = u64
    const UintType = createUintType(8);
    // TODO
    const ListBasicType = createListBasicType(UintType, u64);
    var uintType = try UintType.init();
    var listType = try ListBasicType.init(allocator, &uintType, 128, 128);
    defer uintType.deinit();
    defer listType.deinit();

    const TypeTest = @import("common.zig").typeTest(ListBasicType, []u64);

    for (testCases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("ListBasicType test case {s}\n", .{tc.id});
        try TypeTest.validSszTest(&listType, tc);
    }
}
