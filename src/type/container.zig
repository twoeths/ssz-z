const std = @import("std");
const merkleizeInto = @import("hash").merkleizeInto;

pub fn createContainerType(comptime SSZ_TYPE: type, comptime ZIG_TYPE: type) type {
    // make sure both types have the same number of fields
    const ssz_fields = @typeInfo(SSZ_TYPE).Struct.fields;
    const zig_fields = @typeInfo(ZIG_TYPE).Struct.fields;
    const ssz_field_count = ssz_fields.len;
    const zig_field_count = zig_fields.len;
    if (ssz_field_count != zig_field_count) {
        @compileError("SSZ_TYPE and ZIG_TYPE must have the same number of fields");
    }
    const max_chunk_count = ssz_field_count;

    inline for (ssz_fields, zig_fields) |ssz_field, zig_field| {
        if (!std.mem.eql(u8, ssz_field.name, zig_field.name)) {
            @compileError("SSZ_TYPE and ZIG_TYPE must have the same field name " ++ ssz_field.name ++ " vs " ++ zig_field.name);
        }
    }

    const ContainerType = struct {
        allocator: *std.mem.Allocator,
        ssz_fields: SSZ_TYPE,
        chunk_bytes: []u8,

        pub fn init(allocator: *std.mem.Allocator, ssz_fields_obj: SSZ_TYPE) !@This() {
            // same to round up, looks like a "/" round down
            const chunk_bytes_len: usize = ((max_chunk_count + 1) / 2) * 64;
            return @This(){ .allocator = allocator, .ssz_fields = ssz_fields_obj, .chunk_bytes = try allocator.alloc(u8, 32 * chunk_bytes_len) };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.chunk_bytes);
        }

        // caller should free the result
        pub fn hashTreeRoot(self: @This(), value: ZIG_TYPE) ![]u8 {
            const result = try self.allocator.alloc(u8, 32);
            @memset(result, 0);
            try self.hashTreeRootInto(value, result);
            return result;
        }

        pub fn hashTreeRootInto(self: @This(), value: ZIG_TYPE, out: []u8) !void {
            if (out.len != 32) {
                return error.InCorrectLen;
            }

            inline for (ssz_fields, 0..) |field, i| {
                const field_name = field.name;
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
    const ContainerType = createContainerType(SszType, ZigType);
    const containerType = try ContainerType.init(&allocator, SszType{
        .x = uintType,
        .y = uintType,
    });

    const result = try containerType.hashTreeRoot(ZigType{ .x = 0xffffffffffffffff, .y = 0xffffffffffffffff });
    std.debug.print("containerType.hashTreeRoot(0xffffffffffffffff) {any}\n", .{result});
    allocator.free(result);

    containerType.deinit();
}
