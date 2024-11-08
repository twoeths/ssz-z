const std = @import("std");
const merkleizeInto = @import("hash").merkleizeInto;

const BytesRange = struct {
    start: usize,
    end: usize,
};

// create a ssz type from type of an ssz object
// type of zig type will be used once and checked inside hashTreeRoot() function
pub fn createContainerType(comptime ST: type, comptime ZT: type) type {
    const ssz_fields_info = @typeInfo(ST).Struct.fields;
    const max_chunk_count = ssz_fields_info.len;
    const native_endian = @import("builtin").target.cpu.arch.endian();

    const ContainerType = struct {
        allocator: *std.mem.Allocator,
        ssz_fields: ST,
        // a sha256 block is 64 byte
        blocks_bytes: []u8,
        fixed_size: ?usize,
        fixed_end: usize,
        variable_field_count: usize,

        pub fn init(allocator: *std.mem.Allocator, ssz_fields: ST) !@This() {
            var fixed_size: ?usize = 0;
            var fixed_end: usize = 0;
            var variable_field_count: usize = 0;
            inline for (ssz_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = @field(ssz_fields, field_name);
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
                .fixed_size = fixed_size,
                .fixed_end = fixed_end,
                .variable_field_count = variable_field_count,
            };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.blocks_bytes);
        }

        // caller should free the result
        pub fn hashTreeRoot(self: @This(), value: ZT) ![]u8 {
            const result = try self.allocator.alloc(u8, 32);
            @memset(result, 0);
            try self.hashTreeRootInto(value, result);
            return result;
        }

        pub fn hashTreeRootInto(self: @This(), value: ZT, out: []u8) !void {
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
                try ssz_type.hashTreeRootInto(field_value, self.blocks_bytes[(i * 32) .. (i + 1) * 32]);
            }

            const result = try merkleizeInto(self.blocks_bytes, max_chunk_count, out);
            return result;
        }

        pub fn serializeToBytes(self: @This(), value: ZT, out: []u8) !usize {
            var fixed_index = 0;
            var variable_index = self.fixed_end;

            inline for (ssz_fields_info) |field_info| {
                const field_name = field_info.name;
                const field_value = @field(value, field_name);
                const ssz_type = @field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    // write offset
                    const slice = std.mem.bytesAsSlice(u32, out[fixed_index..]);
                    const variable_index_endian = if (native_endian == .big) @byteSwap(variable_index) else variable_index;
                    slice[0] = variable_index_endian;
                    fixed_index += 4;
                    variable_index = try ssz_type.serializeToBytes(field_value, out[variable_index..]);
                } else {
                    fixed_index = try ssz_type.serializeToBytes(field_value, out[fixed_index..]);
                }
            }

            return variable_index;
        }

        // consumer should free the result
        pub fn deserializeFromBytes(self: @This(), data: []const u8) !ZT {
            // TODO: validate data length
            // max_chunk_count is known at compile time so we can allocate on stack
            const field_ranges = [_]BytesRange{.{ .start = 0, .end = 0 }} ** max_chunk_count;
            try self.getFieldRanges(data, field_ranges);
            const obj_ptr = self.allocator.alloc(ZT);
            inline for (ssz_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const ssz_type = @field(self.ssz_fields, field_name);
                const field_range = field_ranges[i];
                const field_data = data[field_range.start..field_range.end];
                const field_value = try ssz_type.deserializeFromBytes(field_data);
                @field(obj_ptr, field_name) = field_value;
            }
        }

        fn getFieldRanges(self: @This(), data: []const u8, out: []BytesRange) !void {
            if (out.len != max_chunk_count) {
                return error.InCorrectLen;
            }

            var fixed_index = 0;

            // TODO: refactor like in readVariableOffsets
            // allocate 1 more for the end of the last variable field so that each variable field can consume 2 offsets
            var offsets: [self.variable_field_count + 1]u32 = [_]u32{0} ** (self.variable_field_count + 1);
            var offset_index = 0;
            inline for (ssz_fields_info) |field_info| {
                const field_name = field_info.name;
                const ssz_type = @field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    const slice = std.mem.bytesAsSlice(u32, data[fixed_index..(fixed_index + 4)]);
                    const variable_index_endian = if (native_endian == .big) @byteSwap(slice[0]) else slice[0];
                    offsets[offset_index] = variable_index_endian;
                    offset_index += 1;
                    fixed_index += 4;
                } else {
                    fixed_index += ssz_type.fixed_size.?;
                }
            }
            offsets[offset_index] = data.len;

            // TODO: deduplicate with the loop above
            offset_index = 0;
            fixed_index = 0;
            inline for (ssz_fields_info, 0..) |field_info, i| {
                const field_name = field_info.name;
                const ssz_type = @field(self.ssz_fields, field_name);
                if (ssz_type.fixed_size == null) {
                    out[i] = .ByteRange{ .start = offsets[offset_index], .end = offsets[offset_index + 1] };
                    fixed_index += 4;
                } else {
                    out[i] = .ByteRange{ .start = fixed_index, .end = fixed_index + ssz_type.fixed_size.? };
                    fixed_index += ssz_type.fixed_size.?;
                }
            }
        }
    };

    return ContainerType;
}

test "createContainerType" {
    var allocator = std.testing.allocator;
    const UintType = @import("./uint.zig").createUintType(8);
    const uintType = try UintType.init(&allocator);
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

    const obj = ZigType{ .x = 0xffffffffffffffff, .y = 0 };
    const result = try containerType.hashTreeRoot(obj);
    std.debug.print("containerType.hashTreeRoot(0xffffffffffffffff) {any}\n", .{result});
    allocator.free(result);

    containerType.deinit();
}

// createContainerType with different number of fields will cause compile error: Number of fields is not the same
// createContainerType with different field name will cause compile error: no field named 'y' in struct 'container.test.createContainerType.ZigType'
// createContainerType with same field name but different type will cause compile error: error: expected type 'u64', found 'bool'
