const std = @import("std");
const merkleizeInto = @import("hash").merkleizeInto;

// create a ssz type from type of an ssz object
// type of zig type will be used once and checked inside hashTreeRoot() function
pub fn createContainerType(comptime T: type) type {
    const ssz_fields_info = @typeInfo(T).Struct.fields;
    const max_chunk_count = ssz_fields_info.len;

    const ContainerType = struct {
        allocator: *std.mem.Allocator,
        ssz_fields: T,
        chunk_bytes: []u8,

        pub fn init(allocator: *std.mem.Allocator, ssz_fields: T) !@This() {
            // same to round up, looks like a "/" round down
            const chunk_bytes_len: usize = ((max_chunk_count + 1) / 2) * 64;
            return @This(){ .allocator = allocator, .ssz_fields = ssz_fields, .chunk_bytes = try allocator.alloc(u8, 32 * chunk_bytes_len) };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.chunk_bytes);
        }

        // caller should free the result
        pub fn hashTreeRoot(self: @This(), value: anytype) ![]u8 {
            const result = try self.allocator.alloc(u8, 32);
            @memset(result, 0);
            try self.hashTreeRootInto(value, result);
            return result;
        }

        pub fn hashTreeRootInto(self: @This(), value: anytype, out: []u8) !void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            const ValueType = @typeInfo(@TypeOf(value));
            if (ValueType.Struct.fields.len != max_chunk_count) {
                // TODO: more info to error message
                @compileError("Number of fields is not the same");
            }

            // this will also enforce all fields in value match ssz_fields
            inline for (ssz_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const field_value = @field(value, field_name);
                const ssz_type = @field(self.ssz_fields, field_name);
                try ssz_type.hashTreeRootInto(field_value, self.chunk_bytes[(i * 32) .. (i + 1) * 32]);
            }

            const result = try merkleizeInto(self.chunk_bytes, max_chunk_count, out);
            return result;
        }
    };

    return ContainerType;
}

test "createContainerType" {
    var allocator = std.testing.allocator;
    const UintType = @import("./uint.zig").createUintType(u64);
    const uintType = UintType{ .allocator = &allocator };
    const SszType = struct {
        x: UintType,
        y: UintType,
    };
    const ZigType = struct {
        x: u64,
        y: u64,
    };
    const ContainerType = createContainerType(SszType);
    const containerType = try ContainerType.init(&allocator, SszType{
        .x = uintType,
        .y = uintType,
    });

    const result = try containerType.hashTreeRoot(ZigType{ .x = 0xffffffffffffffff, .y = 0 });
    std.debug.print("containerType.hashTreeRoot(0xffffffffffffffff) {any}\n", .{result});
    allocator.free(result);

    containerType.deinit();
}

// createContainerType with different number of fields will cause compile error: Number of fields is not the same
// createContainerType with different field name will cause compile error: no field named 'y' in struct 'container.test.createContainerType.ZigType'
// createContainerType with same field name but different type will cause compile error: error: expected type 'u64', found 'bool'
