const std = @import("std");
const Token = std.json.Token;
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const expect = std.testing.expect;
const merkleize = @import("hash").merkleizeBlocksBytes;
const HashFn = @import("hash").HashFn;
const sha256Hash = @import("hash").sha256Hash;
const toRootHex = @import("util").toRootHex;
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;
const HashError = @import("./common.zig").HashError;
const Parsed = @import("./type.zig").Parsed;

const BytesRange = struct {
    start: usize,
    end: usize,
};

/// TODO: defaultValue() for all types
// create a ssz type from type of an ssz object
// type of zig type will be used once and checked inside hashTreeRoot() function
pub fn createContainerType(comptime ST: type, hashFn: HashFn) type {
    const ssz_struct_info = switch (@typeInfo(ST)) {
        .Struct => |struct_info| struct_info,
        else => @compileError("Expected a struct type."),
    };

    comptime var new_fields: [ssz_struct_info.fields.len]std.builtin.Type.StructField = undefined;
    comptime var alignment: usize = 0;
    inline for (ssz_struct_info.fields, 0..) |field, i| {
        if (field.type.getZigTypeAlignment() > alignment) {
            alignment = field.type.getZigTypeAlignment();
        }
        new_fields[i] = .{
            .name = field.name,
            .type = field.type.getZigType(),
            // TODO: implement this
            .default_value = null,
            .is_comptime = false,
            .alignment = field.type.getZigTypeAlignment(),
        };
    }

    // this works for Zig 0.13
    // syntax in 0.14 or later could change, see https://github.com/ziglang/zig/issues/10710
    const ZT = comptime @Type(.{
        .Struct = .{
            .layout = .auto,
            .backing_integer = null,
            .fields = new_fields[0..],
            // TODO: do we need to assign this value?
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });

    const zig_fields_info = @typeInfo(ZT).Struct.fields;
    const max_chunk_count = zig_fields_info.len;
    const native_endian = @import("builtin").target.cpu.arch.endian();
    const SingleType = @import("./single.zig").withType(ZT);
    const ParsedResult = Parsed(ZT);

    const ContainerType = struct {
        allocator: Allocator,
        // TODO: *ST to avoid copy
        ssz_fields: ST,
        // a sha256 block is 64 byte
        blocks_bytes: []u8,
        min_size: usize,
        max_size: usize,
        fixed_size: ?usize,
        fixed_end: usize,
        variable_field_count: usize,

        /// Zig Type definition
        pub fn getZigType() type {
            return ZT;
        }

        /// to be used by parent
        /// an alignment of struct is max of all fields' alignment
        pub fn getZigTypeAlignment() usize {
            return alignment;
        }

        /// public function for consumers
        /// TODO: consider returning *@This(), see BitArray
        pub fn init(allocator: Allocator, ssz_fields: ST) !@This() {
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
                .blocks_bytes = try allocator.alloc(u8, blocks_bytes_len),
                .min_size = min_size,
                .max_size = max_size,
                .fixed_size = fixed_size,
                .fixed_end = fixed_end,
                .variable_field_count = variable_field_count,
            };
        }

        pub fn deinit(self: *const @This()) void {
            self.allocator.free(self.blocks_bytes);
        }

        pub fn hashTreeRoot(self: *@This(), value: *const ZT, out: []u8) HashError!void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            // this will also enforce all fields in value match ssz_fields
            inline for (zig_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const field_type = @typeInfo(field_info.type);
                // by default use pointer to avoid a copy
                const field_value_ptr = if (field_type == .Pointer or field_type == .Bool or field_type == .Int) @field(value, field_name) else &@field(value, field_name);
                const ssz_type = &@field(self.ssz_fields, field_name);
                try ssz_type.hashTreeRoot(field_value_ptr, self.blocks_bytes[(i * 32) .. (i + 1) * 32]);
            }

            return merkleize(hashFn, self.blocks_bytes, max_chunk_count, out);
        }

        pub fn fromSsz(self: *const @This(), ssz: []const u8) SszError!ParsedResult {
            return SingleType.fromSsz(self, ssz);
        }

        /// public function for consumers
        pub fn fromJson(self: *const @This(), json: []const u8) JsonError!ParsedResult {
            return SingleType.fromJson(self, json);
        }

        // public function for consumers
        pub fn clone(self: *const @This(), value: *const ZT) SszError!ParsedResult {
            return SingleType.clone(self, value);
        }

        pub fn equals(self: *const @This(), a: *const ZT, b: *const ZT) bool {
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                const field_type = @typeInfo(field_info.type);
                const a_field_ptr = if (field_type == .Pointer or field_type == .Bool or field_type == .Int) @field(a, field_name) else &@field(a, field_name);
                const b_field_ptr = if (field_type == .Pointer or field_type == .Bool or field_type == .Int) @field(b, field_name) else &@field(b, field_name);
                if (!ssz_type.equals(a_field_ptr, b_field_ptr)) {
                    return false;
                }
            }
            return true;
        }

        // Serialization + deserialization
        // -------------------------------
        // Containers can mix fixed length and variable length data.
        //
        // Fixed part                         Variable part
        // [field1 offset][field2 data       ][field1 data               ]
        // [0x000000c]    [0xaabbaabbaabbaabb][0xffffffffffffffffffffffff]
        pub fn serializedSize(self: *const @This(), value: *const ZT) usize {
            var size: usize = 0;
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const field_type = @typeInfo(field_info.type);
                const field_value = @field(value, field_name);
                const field_value_or_ptr = if (field_type == .Pointer or field_type == .Bool or field_type == .Int) field_value else &field_value;
                const ssz_type = &@field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    size += 4;
                    size += ssz_type.serializedSize(field_value_or_ptr);
                } else {
                    size += ssz_type.fixed_size.?;
                }
            }
            return size;
        }

        /// Serialize the object to bytes, return the number of bytes written
        pub fn serializeToBytes(self: *const @This(), value: *const ZT, out: []u8) !usize {
            var fixed_index: usize = 0;
            var variable_index = self.fixed_end;

            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const field_type = @typeInfo(field_info.type);
                const field_value = @field(value, field_name);
                const field_value_or_ptr = if (field_type == .Pointer or field_type == .Bool or field_type == .Int) field_value else &field_value;
                const ssz_type = &@field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    // write offset
                    const slice = std.mem.bytesAsSlice(u32, out[fixed_index..]);
                    const variable_index_endian = if (native_endian == .big) @byteSwap(variable_index) else variable_index;
                    slice[0] = @intCast(variable_index_endian);
                    fixed_index += 4;
                    // write serialized element to variable section
                    // ssz_type.serializeToBytes returns number of bytes written
                    variable_index += try ssz_type.serializeToBytes(field_value_or_ptr, out[variable_index..]);
                } else {
                    fixed_index += try ssz_type.serializeToBytes(field_value_or_ptr, out[fixed_index..]);
                }
            }

            return variable_index;
        }

        // TODO: not sure if we need this or not as there is no way to know the size of internal slice size
        pub fn deserializeFromBytes(self: *const @This(), data: []const u8, out: *ZT) !void {
            // TODO: validate data length
            // max_chunk_count is known at compile time so we can allocate on stack
            var field_ranges = [_]BytesRange{.{ .start = 0, .end = 0 }} ** max_chunk_count;
            try self.getFieldRanges(data, field_ranges[0..]);
            inline for (zig_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                const field_range = field_ranges[i];
                const field_data = data[field_range.start..field_range.end];
                // no copy of data, and it works
                try ssz_type.deserializeFromBytes(field_data, &@field(out, field_name));
            }
        }

        /// for embedded struct, it's allocated by the parent struct
        /// for pointer or slice, it's allocated on its own
        pub fn deserializeFromSlice(self: *const @This(), arenaAllocator: Allocator, slice: []const u8, out: ?*ZT) SszError!*ZT {
            var out2 = out orelse try arenaAllocator.create(ZT);

            // TODO: validate data length
            // max_chunk_count is known at compile time so we can allocate on stack
            var field_ranges = [_]BytesRange{.{ .start = 0, .end = 0 }} ** max_chunk_count;
            try self.getFieldRanges(slice, field_ranges[0..]);
            inline for (zig_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                const field_range = field_ranges[i];
                const field_data = slice[field_range.start..field_range.end];
                const field_type = @typeInfo(field_info.type);

                if (field_type == .Pointer or field_type == .Bool or field_type == .Int) {
                    @field(out2, field_name) = try ssz_type.deserializeFromSlice(arenaAllocator, field_data, null);
                } else {
                    _ = try ssz_type.deserializeFromSlice(arenaAllocator, field_data, &@field(out2, field_name));
                }
            }

            return out2;
        }

        /// a recursive implementation for parent types or fromJson
        pub fn deserializeFromJson(self: *const @This(), arena_allocator: Allocator, source: *Scanner, out: ?*ZT) JsonError!*ZT {
            var out2 = out orelse try arena_allocator.create(ZT);
            // validate begin token "{"
            const begin_object_token = try source.next();
            if (begin_object_token != Token.object_begin) {
                return error.InvalidJson;
            }

            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const json_field_name = try source.next();
                switch (json_field_name) {
                    .string => |v| {
                        // TODO: map case, make a separate function, create a separate type for mapping?
                        if (!std.mem.eql(u8, v, field_name)) {
                            return error.InvalidJson;
                        }
                    },
                    else => return error.InvalidJson,
                }

                const ssz_type = &@field(self.ssz_fields, field_name);
                const field_type = @typeInfo(field_info.type);
                if (field_type == .Pointer or field_type == .Bool or field_type == .Int) {
                    @field(out2, field_name) = try ssz_type.deserializeFromJson(arena_allocator, source, null);
                } else {
                    _ = try ssz_type.deserializeFromJson(arena_allocator, source, &@field(out2, field_name));
                }
            }

            // validate end token "}"
            const end_object_token = try source.next();
            if (end_object_token != Token.object_end) {
                return error.InvalidJson;
            }

            return out2;
        }

        pub fn doClone(self: *const @This(), arena_allocator: Allocator, value: *const ZT, out: ?*ZT) !*ZT {
            var out2 = out orelse try arena_allocator.create(ZT);
            inline for (zig_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = &@field(self.ssz_fields, field_name);
                const field_type = @typeInfo(field_info.type);
                if (field_type == .Pointer or field_type == .Bool or field_type == .Int) {
                    @field(out2, field_name) = try ssz_type.doClone(arena_allocator, @field(value, field_name), null);
                } else {
                    _ = try ssz_type.doClone(arena_allocator, &@field(value, field_name), &@field(out2, field_name));
                }
            }

            return out2;
        }

        // private functions

        // Deserializer helper: Returns the bytes ranges of all fields, both variable and fixed size.
        // Fields may not be contiguous in the serialized bytes, so the returned ranges are [start, end].
        // - For fixed size fields re-uses the pre-computed values this.fieldRangesFixedLen
        // - For variable size fields does a first pass over the fixed section to read offsets
        fn getFieldRanges(self: *const @This(), data: []const u8, out: []BytesRange) !void {
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
        fn readVariableOffsets(self: *const @This(), data: []const u8, offsets: []u32) void {
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

test "basic ContainerType {x: uint, y:bool}" {
    std.debug.print("basic ContainerType x: uint, y:bool\n", .{});
    var allocator = std.testing.allocator;
    const UintType = @import("./uint.zig").createUintType(8);
    const uintType = try UintType.init();
    defer uintType.deinit();
    const BooleanType = @import("./boolean.zig").BooleanType;
    const booleanType = BooleanType.init();
    defer booleanType.deinit();
    const SszType = struct {
        x: UintType,
        y: BooleanType,
    };
    const ContainerType = createContainerType(SszType, sha256Hash);
    const ZigType = ContainerType.getZigType();
    var containerType = try ContainerType.init(allocator, SszType{
        .x = uintType,
        .y = booleanType,
    });

    defer containerType.deinit();

    const obj = ZigType{ .x = 0xffffffffffffffff, .y = false };
    var root = [_]u8{0} ** 32;
    try containerType.hashTreeRoot(&obj, root[0..]);
    const rootHex = try toRootHex(root[0..]);
    try std.testing.expectEqualSlices(u8, "0x6f8396f940737bdb29cc6ba2aba7ec405050f70871c05ed2a2c30b800cb79df6", rootHex);

    const size = containerType.serializedSize(&obj);
    // 1 uint64 + 1 bool = 8 + 1 = 9 bytes
    try expect(size == 9);
    const bytes = try allocator.alloc(u8, size);
    defer allocator.free(bytes);
    _ = try containerType.serializeToBytes(&obj, bytes);
    const obj2 = try containerType.fromSsz(bytes);
    defer obj2.deinit();
    try expect(containerType.equals(&obj, obj2.value));

    // clone
    const cloned_result = try containerType.clone(&obj);
    defer cloned_result.deinit();
    const obj3 = cloned_result.value;
    try expect(containerType.equals(&obj, obj3));
    try expect(obj3.x == obj.x);
    try expect(obj3.y == obj.y);

    // fromJson
    const json = "{ \"x\": \"18446744073709551615\", \"y\": false }";
    const parsed = try containerType.fromJson(json);
    defer parsed.deinit();
    try expect(parsed.value.x == obj.x);
    try expect(parsed.value.y == obj.y);
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
    const ContainerType0 = createContainerType(SszType0, sha256Hash);
    const ZigType0 = ContainerType0.getZigType();
    const containerType0 = try ContainerType0.init(allocator, SszType0{
        .x = uintType,
        .y = uintType,
    });
    defer containerType0.deinit();

    const SszType1 = struct {
        a: ContainerType0,
        b: ContainerType0,
    };
    const ContainerType1 = createContainerType(SszType1, sha256Hash);
    const ZigType1 = ContainerType1.getZigType();
    var containerType1 = try ContainerType1.init(allocator, SszType1{
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
    const cloned_result = try containerType1.clone(&obj);
    defer cloned_result.deinit();
    const obj3 = cloned_result.value;
    try expect(containerType1.equals(&obj, obj3));
    var root3 = [_]u8{0} ** 32;
    try containerType1.hashTreeRoot(obj3, root3[0..]);
    try std.testing.expectEqualSlices(u8, root[0..], root3[0..]);
    obj3.a.x = 2024;
    try expect(obj.a.x != obj3.a.x);

    // fromJson
    const json = "{ \"a\": { \"x\": \"18446744073709551615\", \"y\": \"0\" }, \"b\": { \"x\": \"0\", \"y\": \"18446744073709551615\" } }";
    const parsed = try containerType1.fromJson(json);
    defer parsed.deinit();
    try expect(parsed.value.a.x == obj.a.x);
    try expect(parsed.value.a.y == obj.a.y);
    try expect(parsed.value.b.x == obj.b.x);
    try expect(parsed.value.b.y == obj.b.y);
    try expect(containerType1.equals(&obj, parsed.value));
}
