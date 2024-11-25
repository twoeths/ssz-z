const std = @import("std");
const array = @import("./array.zig").withElementTypes;
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();

/// ST: ssz element type
/// ZT: zig type
pub fn withElementTypes(comptime ST: type, comptime ZT: type) type {
    const Array = array(ST, ZT);

    const ArrayComposite = struct {
        pub fn maxSize(element_type: *ST, max_count: usize) usize {
            if (element_type.fixed_size == null) {
                return (element_type.max_size + 4) * max_count;
            } else {
                return element_type.fixed_size.? * max_count;
            }
        }

        pub fn serializedSize(element_type: *ST, value: []const ZT) usize {
            if (element_type.fixed_size == null) {
                // variable length
                var size: usize = 0;
                for (value) |*elem| {
                    size += 4 + element_type.serializedSize(elem);
                }

                return size;
            } else {
                // fixed length
                return (element_type.fixed_size * value.len);
            }
        }

        pub fn serializeToBytes(element_type: *ST, value: []const ZT, out: []u8) !usize {
            if (element_type.fixed_size == null) {
                // variable length
                var variable_index = value.len * 4;
                const out_slice = std.mem.bytesAsSlice(u32, out);
                for (value, 0..) |*elem, i| {
                    // write offset
                    // TODO: lodestar always need offset here, confirm if Zig needs this or not thru unit test
                    out_slice[i] = if (native_endian == .big) @byteSwap(variable_index) else variable_index;

                    // write serialized element to variable section
                    variable_index = element_type.serializeToBytes(elem, out[variable_index..]);
                }

                return variable_index;
            } else {
                // fixed length
                const elem_byte_length = element_type.fixed_size;
                for (value, 0..) |*elem, i| {
                    _ = try element_type.serializeToBytes(elem, out[i * elem_byte_length .. (i + 1) * elem_byte_length]);
                }
                return elem_byte_length * value.len;
            }
        }

        pub fn deserializeFromBytes(allocator: *std.mem.Allocator, element_type: *ST, data: []const u8, out: []ZT) !void {
            if (data.len == 0) {
                return;
            }

            const offsets = try readOffsetsArrayComposite(allocator, element_type, data);
            defer allocator.free(offsets);

            for (out, 0..) |*elem, i| {
                const elem_data = if (i == out.len - 1) data[offsets[i]..] else data[offsets[i]..offsets[i + 1]];

                // ZT could be a slice, in that case we should pass elem itself instead of pointer to pointer
                const elem_ptr = if (comptime @typeInfo(ZT) == .Pointer) elem.* else elem;
                try element_type.deserializeFromBytes(elem_data, elem_ptr);
            }
        }

        pub fn valueEquals(element_type: *ST, a: []const ZT, b: []const ZT) bool {
            return Array.valueEquals(element_type, a, b);
        }

        pub fn valueClone(element_type: *ST, value: []const ZT, out: []ZT) !void {
            return Array.valueClone(element_type, value, out);
        }

        // consumer should free the returned array
        fn readOffsetsArrayComposite(allocator: *std.mem.Allocator, element_type: *ST, data: []const u8) ![]usize {
            if (element_type.fixed_size == null) {
                // variable length
                return readVariableOffsetsArrayComposite(allocator, data);
            } else {
                // fixed length
                // There's no valid CompositeType with fixed size 0, it's un-rechable code. But prevents diving by zero
                const element_fixed_size = element_type.fixed_size orelse return error.invalidFixedSize;
                const length: usize = data.len / element_fixed_size;
                const offsets = try allocator.alloc(usize, length);
                for (offsets, 0..) |*offset, i| {
                    offset.* = i * element_fixed_size;
                }

                return offsets;
            }
        }

        /// Reads the values of contiguous variable offsets
        /// This function also validates that all offsets are in range.
        /// consumer should free the returned offsets
        fn readVariableOffsetsArrayComposite(allocator: *std.mem.Allocator, data: []const u8) ![]usize {
            if (data.len == 0) {
                const no_offset = try allocator.alloc(usize, 0);
                return no_offset;
            }
            const data_u32_slice = std.mem.bytesAsSlice(u32, data);
            const first_offset = if (native_endian == .big) @byteSwap(data_u32_slice[0]) else data_u32_slice[0];

            if (first_offset == 0) {
                return error.zeroOffset;
            }

            if (first_offset % 4 != 0) {
                return error.offsetNotDivisibleBy4;
            }
            const offset_count: usize = first_offset / 4;
            const offsets = try allocator.alloc(usize, offset_count);

            // ArrayComposite has a contiguous section of offsets, then the data
            //
            //    [offset 1] [offset 2] [data 1 ..........] [data 2 ..]
            // 0x 08000000   0e000000   010002000300        01000200
            //
            // Ensure that:
            // - Offsets point to regions of > 0 bytes, i.e. are increasing
            // - Offsets don't point to bytes outside of the array's size
            //
            // In the example above the first offset is 8, so 8 / 4 = 2 offsets.
            // Then, read the rest of offsets to get offsets = [8, 14]
            offsets[0] = first_offset;
            for (offsets[1..], 1..) |*offset, i| {
                const off = if (native_endian == .big) @byteSwap(data_u32_slice[i]) else data_u32_slice[i];
                if (off > data.len) {
                    return error.offsetOutOfRange;
                }
                const prev_offset = offsets[i - 1];
                if (off <= prev_offset) {
                    return error.offsetNotIncreasing;
                }
                offset.* = off;
            }

            return offsets;
        }
    };

    return ArrayComposite;
}