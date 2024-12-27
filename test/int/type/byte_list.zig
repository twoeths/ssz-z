const std = @import("std");
const createContainerType = @import("ssz").createContainerType;
const createListBasicType = @import("ssz").createListBasicType;
const createUintType = @import("ssz").createUintType;
const sha256Hash = @import("hash").sha256Hash;
const initZeroHash = @import("hash").initZeroHash;
const deinitZeroHash = @import("hash").deinitZeroHash;
const TestCase = @import("common.zig").TypeTestCase;
const createByteListType = @import("ssz").createByteListType;
const fromHex = @import("util").fromHex;

const test_cases = [_]TestCase{
    .{ .id = "empty", .serializedHex = "0x", .json = 
    \\"0x"
    , .rootHex = "0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6" },
    .{ .id = "4 bytes zero", .serializedHex = "0x00000000", .json = 
    \\"0x00000000"
    , .rootHex = "0xa39babe565305429771fc596a639d6e05b2d0304297986cdd2ef388c1936885e" },
    .{
        .id = "4 bytes some value",
        .serializedHex = "0x0cb94737",
        .json =
        \\"0x0cb94737"
        ,
        .rootHex = "0x2e14da116ecbec4c8d693656fb5b69bb0ea9e84ecdd15aba7be1c008633f2885",
    },
    .{
        .id = "32 bytes zero",
        .serializedHex = "0x0000000000000000000000000000000000000000000000000000000000000000",
        .json =
        \\"0x0000000000000000000000000000000000000000000000000000000000000000"
        ,
        .rootHex = "0xbae146b221eca758702e29b45ee7f7dc3eea17d119dd0a3094481e3f94706c96",
    },
    .{
        .id = "32 bytes some value",
        .serializedHex = "0x0cb947377e177f774719ead8d210af9c6461f41baf5b4082f86a3911454831b8",
        .json =
        \\"0x0cb947377e177f774719ead8d210af9c6461f41baf5b4082f86a3911454831b8"
        ,
        .rootHex = "0x50425dbd7a34b50b20916e965ce5c060abe6516ac71bb00a4afebe5d5c4568b8",
    },
    .{
        .id = "96 bytes zero",
        .serializedHex = "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        .json =
        \\"0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        ,
        .rootHex = "0xcd09661f4b2109fb26decd60c004444ea5308a304203412280bd2af3ace306bf",
    },
    .{
        .id = "96 bytes some value",
        .serializedHex = "0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1",
        .json =
        \\"0xb55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1b55b8592bcac475906631481bbc746bca7339d04ab1085e84884a700c03de4b1"
        ,
        .rootHex = "0x5d3ae4b886c241ffe8dc7ae1b5f0e2fb9b682e1eac2ddea292ef02cc179e6903",
    },
};

test "ByteListType of 256" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();
    const ByteListType = createByteListType(256);
    var byte_list_type = try ByteListType.init(allocator, 256);
    defer byte_list_type.deinit();

    const TypeTest = @import("common.zig").typeTest(ByteListType);
    for (test_cases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("ByteListType of 256 - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&byte_list_type, tc);
    }
}

test "ListBasicType[u8, 256]" {
    var allocator = std.testing.allocator;
    try initZeroHash(&allocator, 32);
    defer deinitZeroHash();

    // uint of 1 bytes = u8
    const UintType = createUintType(1);
    const ListBasicType = createListBasicType(UintType);
    var uintType = try UintType.init();
    var list_type = try ListBasicType.init(allocator, &uintType, 256, 256);
    defer uintType.deinit();
    defer list_type.deinit();

    const TypeTest = @import("common.zig").typeTest(ListBasicType);
    for (test_cases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?

        // skip 0x and 2 double quotes
        const u8_list = try allocator.alloc(u8, ((tc.json.len - 4) / 2));
        defer allocator.free(u8_list);

        std.debug.print("ListBasicType[u8, 256] - {s}\n", .{tc.id});

        // skip double quotes at the start and end of json string
        try fromHex(tc.json[1..(tc.json.len - 1)], u8_list);
        const json_array_list = try toJsonStr(allocator, u8_list);
        defer json_array_list.deinit();

        try TypeTest.validSszTest(&list_type, &.{
            .id = tc.id,
            .serializedHex = tc.serializedHex,
            .json = json_array_list.items,
            .rootHex = tc.rootHex,
        });
    }
}

// [1,3] => ["1", "3"]
fn toJsonStr(allocator: std.mem.Allocator, bytes: []const u8) !std.ArrayList(u8) {
    var result = std.ArrayList(u8).init(allocator);

    try result.append('[');
    for (bytes, 0..) |byte, i| {
        const str = try std.fmt.allocPrint(allocator, "\"{}\"", .{byte});
        defer allocator.free(str);
        try result.appendSlice(str);
        if (i < bytes.len - 1) {
            try result.append(',');
        }
    }
    try result.append(']');

    return result;
}
