/// ST: ssz element type
/// ZT: zig type
pub fn withElementTypes(comptime ST: type, comptime ZT: type) type {
    const ArrayBasic = struct {
        pub fn serializeToBytes(element_type: ST, value: []const ZT, out: []u8) !usize {
            const elem_byte_length = element_type.byte_length;
            const byte_len = elem_byte_length * value.len;
            if (byte_len != out.len) {
                return error.InCorrectLen;
            }

            for (value, 0..) |*elem, i| {
                _ = try element_type.serializeToBytes(elem, out[i * elem_byte_length .. (i + 1) * elem_byte_length]);
            }

            return byte_len;
        }

        pub fn deserializeFromBytes(element_type: ST, data: []const u8, out: []ZT) !void {
            const elem_byte_length = element_type.byte_length;
            if (data.len % elem_byte_length != 0) {
                return error.InCorrectLen;
            }

            const elem_count = data.len / elem_byte_length;
            if (elem_count != out.len) {
                return error.InCorrectLen;
            }

            for (out, 0..) |*elem, i| {
                try element_type.deserializeFromBytes(data[i * elem_byte_length .. (i + 1) * elem_byte_length], elem);
            }
        }

        pub fn valueEquals(element_type: ST, a: []const ZT, b: []const ZT) bool {
            if (a.len != b.len) {
                return false;
            }

            for (a, b) |*a_elem, *b_elem| {
                if (!element_type.equals(a_elem, b_elem)) {
                    return false;
                }
            }

            return true;
        }

        pub fn valueClone(element_type: ST, value: []const ZT, out: []ZT) !void {
            for (value, out) |*elem, *out_elem| {
                try element_type.clone(elem, out_elem);
            }
        }
    };

    return ArrayBasic;
}
