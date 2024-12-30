const std = @import("std");
const toRootHex = @import("util").toRootHex;
const fromHex = @import("util").fromHex;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createBitVectorType = @import("ssz").createBitVectorType;

test "BitVectorType of 128 bytes" {
    const testCases = [_]TestCase{
        TestCase{
            .id = "empty",
            .serializedHex = "0x00000000000000000000000000000001",
            .json =
            \\"0x00000000000000000000000000000001"
            ,
            .rootHex = "0x0000000000000000000000000000000100000000000000000000000000000000",
        },
        TestCase{ .id = "some value", .serializedHex = "0xb55b8592bcac475906631481bbc746bc", .json = 
        \\ "0xb55b8592bcac475906631481bbc746bc"
        , .rootHex = "0xb55b8592bcac475906631481bbc746bc00000000000000000000000000000000" },
    };

    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    const BitVectorType = createBitVectorType(128);
    var bitVectorType = try BitVectorType.init(allocator);
    defer bitVectorType.deinit();

    const TypeTest = @import("common.zig").typeTest(BitVectorType);
    for (testCases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("BitVectorType 128 bits - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&bitVectorType, tc);
    }
}

test "BitVectorType of 512 bytes" {
    const testCases = [_]TestCase{
        TestCase{
            .id = "empty",
            .serializedHex = "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            .json =
            \\"0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
            ,
            .rootHex = "0x90f4b39548df55ad6187a1d20d731ecee78c545b94afd16f42ef7592d99cd365",
        },
        TestCase{
            .id = "some value",
            .serializedHex = "0xb55b8592bcac475906631481bbc746bccb647cbb184136609574cacb2958b55bb55b8592bcac475906631481bbc746bccb647cbb184136609574cacb2958b55b",
            .json =
            \\"0xb55b8592bcac475906631481bbc746bccb647cbb184136609574cacb2958b55bb55b8592bcac475906631481bbc746bccb647cbb184136609574cacb2958b55b"
            ,
            .rootHex = "0xf5619a9b3c6831a68fdbd1b30b69843c778b9d36ed1ff6831339ba0f723dbea0",
        },
    };

    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    const BitVectorType = createBitVectorType(512);
    var bitVectorType = try BitVectorType.init(allocator);
    defer bitVectorType.deinit();

    const TypeTest = @import("common.zig").typeTest(BitVectorType);
    for (testCases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("BitVectorType 512 bits - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&bitVectorType, tc);
    }
}
