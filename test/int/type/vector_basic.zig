const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createUintType = @import("ssz").createUintType;
const createVectorBasicType = @import("ssz").createVectorBasicType;

const testCases = [_]TestCase{
    TestCase{
        .id = "8 values",
        .serializedHex = "0xa086010000000000400d030000000000e093040000000000801a060000000000a086010000000000400d030000000000e093040000000000801a060000000000",
        .json =
        \\["100000", "200000", "300000", "400000", "100000", "200000", "300000", "400000"]
        ,
        .rootHex = "0xdd5160dd98e6daa77287c8940decad4eaa14dc98b99285da06ba5479cd570007",
    },
};

test "valid test for VectorBasicType" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    // uint of 8 bytes = u64
    const UintType = createUintType(8);
    const VectorBasicType = createVectorBasicType(UintType, u64);
    var uintType = try UintType.init();
    var listType = try VectorBasicType.init(allocator, &uintType, 8);
    defer uintType.deinit();
    defer listType.deinit();

    const TypeTest = @import("common.zig").typeTest(VectorBasicType);

    for (testCases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("VectorBasicType test case {s}\n", .{tc.id});
        try TypeTest.validSszTest(&listType, tc);
    }
}
