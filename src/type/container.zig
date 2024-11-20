const std = @import("std");
const expect = std.testing.expect;
const merkleize = @import("hash").merkleizeBlocksBytes;
const HashFn = @import("hash").HashFn;
const sha256Hash = @import("hash").sha256Hash;
const toRootHex = @import("util").toRootHex;

const BytesRange = struct {
    start: usize,
    end: usize,
};

// create a ssz type from type of an ssz object
// type of zig type will be used once and checked inside hashTreeRoot() function
pub fn createContainerType(comptime ST: type, comptime ZT: type, hashFn: HashFn) type {
    const zig_fields_info = @typeInfo(ZT).Struct.fields;
    const max_chunk_count = zig_fields_info.len;
    const native_endian = @import("builtin").target.cpu.arch.endian();

    const ContainerType = struct {
        allocator: *std.mem.Allocator,
        // TODO: *ST to avoid copy
        ssz_fields: ST,
        // a sha256 block is 64 byte
        blocks_bytes: []u8,
        min_size: usize,
        max_size: usize,
        fixed_size: ?usize,
        fixed_end: usize,
        variable_field_count: usize,

        pub fn init(allocator: *std.mem.Allocator, ssz_fields: ST) !@This() {
            var min_size: usize = 0;
            var max_size: usize = 0;
            var fixed_size: ?usize = 0;
            var fixed_end: usize = 0;
            var variable_field_count: usize = 0;
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = @field(ssz_fields, field_name);
                min_size = min_size + ssz_type.min_size;
                max_size = max_size + ssz_type.max_size;
                const field_fixed_size = ssz_type.fixed_size;
                if (field_fixed_size == null) {
                    fixed_size = null;
                    fixed_end += 4;
                    variable_field_count += 1;
                } else {
                    const field_fixed_size_value = field_fixed_size.?;
                    if (fixed_size) |fixed_size_value| {
                        fixed_size = fixed_size_value + field_fixed_size_value;
                    }
                    fixed_end += field_fixed_size_value;
                }
            }
            // same to round up, looks like a "/" round down
            const blocks_bytes_len: usize = ((max_chunk_count + 1) / 2) * 64;
            return @This(){
                .allocator = allocator,
                .ssz_fields = ssz_fields,
                .blocks_bytes = try allocator.alloc(u8, 32 * blocks_bytes_len),
                .min_size = min_size,
                .max_size = max_size,
                .fixed_size = fixed_size,
                .fixed_end = fixed_end,
                .variable_field_count = variable_field_count,
            };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.blocks_bytes);
        }

        pub fn hashTreeRoot(self: @This(), value: *const ZT, out: []u8) !void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            // this will also enforce all fields in value match ssz_fields
            inline for (zig_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                // this avoids a copy
                const field_value_ptr = &@field(value, field_name);
                const ssz_type = &@field(self.ssz_fields, field_name);
                try ssz_type.hashTreeRoot(field_value_ptr, self.blocks_bytes[(i * 32) .. (i + 1) * 32]);
            }

            const result = try merkleize(hashFn, self.blocks_bytes, max_chunk_count, out);
            return result;
        }

        // Serialization + deserialization
        // -------------------------------
        // Containers can mix fixed length and variable length data.
        //
        // Fixed part                         Variable part
        // [field1 offset][field2 data       ][field1 data               ]
        // [0x000000c]    [0xaabbaabbaabbaabb][0xffffffffffffffffffffffff]
        pub fn serializedSize(self: @This(), value: *const ZT) usize {
            var size: usize = 0;
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const field_value_ptr = &@field(value, field_name);
                const ssz_type = &@field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    size += 4;
                    size += ssz_type.serializedSize(field_value_ptr);
                } else {
                    size += ssz_type.fixed_size.?;
                }
            }
            return size;
        }

        pub fn serializeToBytes(self: @This(), value: *const ZT, out: []u8) !usize {
            var fixed_index: usize = 0;
            var variable_index = self.fixed_end;

            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const field_value_ptr = &@field(value, field_name);
                const ssz_type = &@field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    // write offset
                    const slice = std.mem.bytesAsSlice(u32, out[fixed_index..]);
                    const variable_index_endian = if (native_endian == .big) @byteSwap(variable_index) else variable_index;
                    slice[0] = @intCast(variable_index_endian);
                    fixed_index += 4;
                    variable_index = try ssz_type.serializeToBytes(field_value_ptr, out[variable_index..]);
                } else {
                    fixed_index = try ssz_type.serializeToBytes(field_value_ptr, out[fixed_index..]);
                }
            }

            return variable_index;
        }

        pub fn deserializeFromBytes(self: @This(), data: []const u8, out: *ZT) !void {
            // TODO: validate data length
            // max_chunk_count is known at compile time so we can allocate on stack
            var field_ranges = [_]BytesRange{.{ .start = 0, .end = 0 }} ** max_chunk_count;
            try self.getFieldRanges(data, field_ranges[0..]);
            inline for (zig_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                const field_range = field_ranges[i];
                const field_data = data[field_range.start..field_range.end];
                // this works, but it needs a copy of data
                // var field_value: field_info.type = undefined;
                // try ssz_type.deserializeFromBytes(field_data, &field_value);
                // @field(out, field_name) = field_value;

                // this involves a copy of data, and DOES NOT work
                // var field_value = @field(out, field_name);
                // try ssz_type.deserializeFromBytes(field_data, &field_value);
                // @field(out, field_name) = field_value;

                // no copy of data, and it works
                try ssz_type.deserializeFromBytes(field_data, &@field(out, field_name));
            }
        }

        pub fn equals(self: @This(), a: *const ZT, b: *const ZT) bool {
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                const a_field_ptr = &@field(a, field_name);
                const b_field_ptr = &@field(b, field_name);
                if (!ssz_type.equals(a_field_ptr, b_field_ptr)) {
                    return false;
                }
            }
            return true;
        }

        pub fn clone(self: @This(), value: *const ZT, out: *ZT) !void {
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                const field_value_ptr = &@field(value, field_name);
                try ssz_type.clone(field_value_ptr, &@field(out, field_name));
            }
        }

        // private functions

        // Deserializer helper: Returns the bytes ranges of all fields, both variable and fixed size.
        // Fields may not be contiguous in the serialized bytes, so the returned ranges are [start, end].
        // - For fixed size fields re-uses the pre-computed values this.fieldRangesFixedLen
        // - For variable size fields does a first pass over the fixed section to read offsets
        fn getFieldRanges(self: @This(), data: []const u8, out: []BytesRange) !void {
            if (out.len != max_chunk_count) {
                return error.InCorrectLen;
            }

            // avoid alloc as much as possible, add 1 at the end for data length
            var offsets = [_]u32{0} ** (max_chunk_count + 1);
            self.readVariableOffsets(data, offsets[0..]);

            var variable_index: usize = 0;
            var fixed_index: usize = 0;
            inline for (zig_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    out[i].start = offsets[variable_index];
                    out[i].end = offsets[variable_index + 1];
                    variable_index += 1;
                    fixed_index += 4;
                } else {
                    out[i].start = fixed_index;
                    out[i].end = fixed_index + ssz_type.fixed_size.?;
                    fixed_index += ssz_type.fixed_size.?;
                }
            }
        }

        // Returns the byte ranges of all variable size fields.
        fn readVariableOffsets(self: @This(), data: []const u8, offsets: []u32) void {
            var variable_index: usize = 0;
            var fixed_index: usize = 0;
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    const slice = std.mem.bytesAsSlice(u32, data[fixed_index..(fixed_index + 4)]);
                    const variable_index_endian = if (native_endian == .big) @byteSwap(slice[0]) else slice[0];
                    offsets[variable_index] = variable_index_endian;
                    variable_index += 1;
                    fixed_index += 4;
                } else {
                    fixed_index += ssz_type.fixed_size.?;
                }
            }
            // set 1 more at the end of the last variable field so that each variable field can consume 2 offsets
            offsets[variable_index] = @intCast(data.len);
        }
    };

    return ContainerType;
}

test "basic ContainerType {x: uint, y:uint}" {
    var allocator = std.testing.allocator;
    const UintType = @import("./uint.zig").createUintType(8);
    const uintType = try UintType.init();
    const SszType = struct {
        x: UintType,
        y: UintType,
    };
    const ZigType = struct {
        x: u64,
        y: u64,
    };
    const ContainerType = createContainerType(SszType, ZigType, sha256Hash);
    const containerType = try ContainerType.init(&allocator, SszType{
        .x = uintType,
        .y = uintType,
    });

    const obj = ZigType{ .x = 0xffffffffffffffff, .y = 0 };
    var root = [_]u8{0} ** 32;
    try containerType.hashTreeRoot(&obj, root[0..]);
    const rootHex = try toRootHex(root[0..]);
    // 0x59a751e5d7d17ee0f3eebab3ef17512aca150acc6f59173d6e217cccced5f0d4
    try std.testing.expectEqualSlices(u8, "0x59a751e5d7d17ee0f3eebab3ef17512aca150acc6f59173d6e217cccced5f0d4", rootHex);

    const size = containerType.serializedSize(&obj);
    // 2 uint64 = 2 * 8 = 16 bytes
    try expect(size == 16);
    const bytes = try allocator.alloc(u8, size);
    defer allocator.free(bytes);
    _ = try containerType.serializeToBytes(&obj, bytes);
    var obj2: ZigType = undefined;
    _ = try containerType.deserializeFromBytes(bytes, &obj2);
    try expect(obj2.x == obj.x);
    try expect(obj2.y == obj.y);
    try expect(containerType.equals(&obj, &obj2));

    // clone
    var obj3: ZigType = undefined;
    try containerType.clone(&obj, &obj3);
    try expect(containerType.equals(&obj, &obj3));
    try expect(obj3.x == obj.x);
    try expect(obj3.y == obj.y);

    containerType.deinit();
}

test "ContainerType with embedded struct" {
    var allocator = std.testing.allocator;
    const UintType = @import("./uint.zig").createUintType(8);
    const uintType = try UintType.init();
    defer uintType.deinit();
    const SszType0 = struct {
        x: UintType,
        y: UintType,
    };
    const ZigType0 = struct {
        x: u64,
        y: u64,
    };
    const ContainerType0 = createContainerType(SszType0, ZigType0, sha256Hash);
    const containerType0 = try ContainerType0.init(&allocator, SszType0{
        .x = uintType,
        .y = uintType,
    });
    defer containerType0.deinit();

    const SszType1 = struct {
        a: ContainerType0,
        b: ContainerType0,
    };
    const ZigType1 = struct {
        a: ZigType0,
        b: ZigType0,
    };
    const ContainerType1 = createContainerType(SszType1, ZigType1, sha256Hash);
    const containerType1 = try ContainerType1.init(&allocator, SszType1{
        .a = containerType0,
        .b = containerType0,
    });
    defer containerType1.deinit();

    const a = ZigType0{ .x = 0xffffffffffffffff, .y = 0 };
    const b = ZigType0{ .x = 0, .y = 0xffffffffffffffff };
    const obj = ZigType1{ .a = a, .b = b };
    const size = containerType1.serializedSize(&obj);
    // a = 2 * 8 bytes, b = 2 * 8 bytes
    try expect(size == 32);
    const bytes = try allocator.alloc(u8, size);
    defer allocator.free(bytes);

    // serialize + deserialize
    _ = try containerType1.serializeToBytes(&obj, bytes);
    var obj2: ZigType1 = undefined;
    _ = try containerType1.deserializeFromBytes(bytes, &obj2);
    try expect(obj2.a.x == obj.a.x);
    try expect(obj2.a.y == obj.a.y);
    try expect(obj2.b.x == obj.b.x);
    try expect(obj2.b.y == obj.b.y);
    try expect(containerType1.equals(&obj, &obj2));
    // confirm hash_tree_root
    var root = [_]u8{0} ** 32;
    try containerType1.hashTreeRoot(&obj, root[0..]);
    var root2 = [_]u8{0} ** 32;
    try containerType1.hashTreeRoot(&obj2, root2[0..]);
    try std.testing.expectEqualSlices(u8, root[0..], root2[0..]);

    // clone, equal
    var obj3: ZigType1 = undefined;
    try containerType1.clone(&obj, &obj3);
    try expect(containerType1.equals(&obj, &obj3));
    var root3 = [_]u8{0} ** 32;
    try containerType1.hashTreeRoot(&obj3, root3[0..]);
    try std.testing.expectEqualSlices(u8, root[0..], root3[0..]);
    obj3.a.x = 2024;
    try expect(obj.a.x != obj3.a.x);
}
