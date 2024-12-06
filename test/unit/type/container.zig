const std = @import("std");
const createContainerType = @import("ssz").createContainerType;
const createListBasicType = @import("ssz").createListBasicType;
const createUintType = @import("ssz").createUintType;
const sha256Hash = @import("hash").sha256Hash;
const TestCase = @import("common.zig").TypeTestCase;

test "ContainerType with 2 uints" {
    var allocator = std.testing.allocator;
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
    var containerType = try ContainerType.init(&allocator, SszType{
        .a = uintType,
        .b = uintType,
    });
    defer containerType.deinit();

    const testCases = [_]TestCase{
        TestCase{
            .id = "zero",
            .serializedHex = "0x00000000000000000000000000000000",
            .json =
            \\ {"a": "0", "b": "0"}
            ,
            .rootHex = "0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b",
        },
        TestCase{
            .id = "some value",
            .serializedHex = "0x40e2010000000000f1fb090000000000",
            .json =
            \\ {"a": "123456", "b": "654321"}
            ,
            .rootHex = "0x53b38aff7bf2dd1a49903d07a33509b980c6acc9f2235a45aac342b0a9528c22",
        },
    };

    const TypeTest = @import("common.zig").typeTest(ContainerType, *ZigType);
    for (testCases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("ContainerType with 2 uints - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&containerType, tc);
    }
}

// TODO: ContainerType with ByteVectorType

test "ContainerType with ListBasicType(uint64, 128) and uint64" {
    var allocator = std.testing.allocator;
    const UintType = createUintType(8);
    var uintType = try UintType.init();
    defer uintType.deinit();

    const ListBasicType = createListBasicType(UintType, u64);
    var listBasicType = try ListBasicType.init(&allocator, &uintType, 128, 128);
    defer listBasicType.deinit();

    const SszType = struct {
        a: ListBasicType,
        b: UintType,
    };
    const ZigType = struct {
        a: []u64,
        b: u64,
    };

    const ContainerType = createContainerType(SszType, ZigType, sha256Hash);
    var containerType = try ContainerType.init(&allocator, SszType{
        .a = listBasicType,
        .b = uintType,
    });
    defer containerType.deinit();

    const testCases = [_]TestCase{
        TestCase{
            .id = "zero",
            .serializedHex = "0x0c0000000000000000000000",
            .json =
            \\ {"a": [], "b": "0"}
            ,
            .rootHex = "0xdc3619cbbc5ef0e0a3b38e3ca5d31c2b16868eacb6e4bcf8b4510963354315f5",
        },
        TestCase{
            .id = "some value",
            .serializedHex = "0x0c000000f1fb09000000000040e2010000000000f1fb09000000000040e2010000000000f1fb09000000000040e2010000000000",
            .json =
            \\ {"a": ["123456", "654321", "123456", "654321", "123456"], "b": "654321"}
            ,
            .rootHex = "0x5ff1b92b2fa55eea1a14b26547035b2f5437814b3436172205fa7d6af4091748",
        },
    };

    const TypeTest = @import("common.zig").typeTest(ContainerType, *ZigType);
    for (testCases[0..]) |*tc| {
        // TODO: find other way not to write to stderror
        // may have to use `zig build test 2>&1` on CI?
        std.debug.print("ContainerType with ListBasicType(uint64, 128) and uint64 - {s}\n", .{tc.id});
        try TypeTest.validSszTest(&containerType, tc);
    }
}
