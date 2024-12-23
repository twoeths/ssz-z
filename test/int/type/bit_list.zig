const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createBitListType = @import("ssz").createBitListType;

test "BitListType of 2048" {
    const test_cases = [_]TestCase{
        .{ .id = "empty", .serializedHex = "0x01", .json = 
        \\"0x01"
        , .rootHex = "0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6" },
        .{ .id = "zero'ed 1 bytes", .serializedHex = "0x0010", .json = 
        \\ "0x0010"
        , .rootHex = "0x07eb640282e16eea87300c374c4894ad69b948de924a158d2d1843b3cf01898a" },
        .{ .id = "zero'ed 8 bytes", .serializedHex = "0x000000000000000010", .json = 
        \\ "0x000000000000000010"
        , .rootHex = "0x5c597e77f879e249af95fe543cf5f4dd16b686948dc719707445a32a77ff6266" },
        .{ .id = "short value", .serializedHex = "0xb55b8592bcac475906631481bbc746bc", .json = 
        \\ "0xb55b8592bcac475906631481bbc746bc"
        , .rootHex = "0x9ab378cfbd6ec502da1f9640fd956bbef1f9fcbc10725397805c948865384e77" },
        .{
            .id = "long value",
            .serializedHex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bc",
            .json =
            \\"0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bc"
            ,
            .rootHex = "0x4b71a7de822d00a5ff8e7e18e13712a50424cbc0e18108ab1796e591136396a0",
        },
    };

    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    const BitListType = createBitListType(2048);
    var bit_list = try BitListType.init(allocator, 2048 / 8);
    defer bit_list.deinit();

    const TypeTest = @import("common.zig").typeTest(BitListType);
    for (test_cases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("BitListType 2048 bits - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&bit_list, tc);
    }
}
